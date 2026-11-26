#!/bin/bash
# Upload a reviewed year directory without changing the local dataset.
set +x
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
REPO="AIMedrui/Spine_agentbench"
YEAR=""
DO_UPLOAD=0
WORK=""
STAGES=("病例评估" "影像诊断" "会诊" "手术规划" "术前准备" "手术分期或干预" "并发症" "术后复查")
EXCLUDES=(
    ".DS_Store" "._*" "__MACOSX" ".TemporaryItems" ".Trashes"
    "Thumbs.db" "Desktop.ini" ".git" ".hg" ".svn"
    ".cache" "__pycache__" "*.pyc" ".pytest_cache" ".venv"
    ".env" ".env.*" "*.tmp" "*.temp" "*~" ".gitkeep"
)

usage() {
    cat <<'HELP'
在仓库根目录运行：bash ./scripts/upload_dataset.sh --year YYYY [--upload]

默认仅预览，不联网，不上传。
  --year YYYY      必填；读取仓库旁的 ../dataset/YYYY/，上传到远端 YYYY/
  --upload         检查私有仓库，确认后上传并核对
  --help           显示帮助

示例：
  bash ./scripts/upload_dataset.sh --year 2014
  bash ./scripts/upload_dataset.sh --year 2014 --upload

目标固定为 AIMedrui/Spine_agentbench。仓库和 dataset 必须放在同一个父目录下。
请把最终资料放在 ../dataset/YYYY/。
2017 和 2018 的上传副本排除病例下的「原始资料」。
2018 另保留影像诊断和术后复查内的影像子目录及 DICOM。
使用本机 hf 登录，不接收或保存 Token。只上传已确认存在的私有仓库，
不修改可见性、删除远端文件或修改本地最终版。空阶段通过临时 .gitkeep 保留。
已有同路径文件可能被更新；远端年份目录有额外文件时停止。
Hugging Face 可能自动维护根目录 .gitattributes；其他业务文件必须不变。
HELP
}

die() {
    printf '停止：%s\n' "$*" >&2
    exit 1
}

reset_terminal() {
    if [[ "$DO_UPLOAD" == 1 && -t 0 ]]; then
        stty sane || die "无法恢复终端输入状态，请重新打开终端"
    fi
}

hf_cli() {
    local status=0
    # CLI commands must not consume the later human confirmation.
    command hf "$@" < /dev/null || status=$?
    reset_terminal
    return "$status"
}

cleanup() {
    if [[ "$DO_UPLOAD" == 1 && -t 0 ]]; then
        stty sane 2>/dev/null || true
    fi
    if [[ -n "$WORK" && -d "$WORK" && "${WORK##*/}" == hku-hf-upload.* ]]; then
        find "$WORK" -depth -delete
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

while [[ $# -gt 0 ]]; do
    case "$1" in
        --upload) DO_UPLOAD=1; shift ;;
        --year)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 缺少参数"
            YEAR="$2"
            shift 2
            ;;
        --help|-h) usage; exit 0 ;;
        *) die "未知选项 $1；使用 --help 查看用法" ;;
    esac
done

[[ "$YEAR" =~ ^[0-9]{4}$ ]] || die "请用 --year 指定四位年份，例如 --year 2014"
SOURCE="$ROOT_DIR/dataset/$YEAR"
[[ -d "$SOURCE" && ! -L "$SOURCE" ]] || die "请将最终资料放在仓库旁的 ../dataset/$YEAR/ 中（不能是符号链接）"
SOURCE="$(cd "$SOURCE" && pwd -P)"
[[ "${SOURCE##*/}" == "$YEAR" ]] || die "本地目录名称必须为 $YEAR，避免上传错误年份"
for tool in rsync find mktemp du wc; do
    command -v "$tool" >/dev/null || die "缺少工具：$tool"
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hku-hf-upload.XXXXXX")"
PAYLOAD="$WORK/payload"
mkdir "$PAYLOAD"
RSYNC_ARGS=(-r)
for pattern in "${EXCLUDES[@]}"; do
    RSYNC_ARGS+=(--exclude "$pattern")
done
if [[ "$YEAR" == 2017 || "$YEAR" == 2018 ]]; then
    RSYNC_ARGS+=(--exclude '/*/原始资料/')
fi

# Rsync never follows links; reject them rather than silently dropping material.
while IFS= read -r -d '' path; do
    [[ "$path" != *$'\n'* && "$path" != *$'\t'* && "$path" != *$'\r'* ]] ||
        die "路径中含换行或制表符，请先规范文件名"
    [[ ! -L "$path" ]] || die "目录含符号链接，请先人工处理：$path"
    [[ -d "$path" || -f "$path" ]] || die "目录含非普通文件：$path"
done < <(find "$SOURCE" -print0)

COPYFILE_DISABLE=1 rsync "${RSYNC_ARGS[@]}" -- "$SOURCE/" "$PAYLOAD/"
[[ -f "$PAYLOAD/README.md" ]] || die "年份根目录缺少 README.md"

CASE_COUNT=0
CLINICAL_COUNT=0
DICOM_COUNT=0
PLACEHOLDER_COUNT=0
while IFS= read -r -d '' entry; do
    if [[ -f "$entry" ]]; then
        [[ "${entry##*/}" == README.md ]] || die "年份根目录有额外文件：${entry##*/}"
        continue
    fi
    [[ -d "$entry" ]] || die "无效病例目录：$entry"
    CASE_COUNT=$((CASE_COUNT + 1))
    for stage in "${STAGES[@]}"; do
        [[ -d "$entry/$stage" ]] || die "${entry##*/} 缺少阶段目录：$stage"
    done
    count="$(find "$entry" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d ' ')"
    [[ "$count" == 8 ]] || die "${entry##*/} 必须恰好包含八个阶段目录"
    for stage in "${STAGES[@]}"; do
        STAGE_COUNT=0
        depth=1
        if [[ "$YEAR" == 2018 && ( "$stage" == 影像诊断 || "$stage" == 术后复查 ) ]]; then
            depth=3
        fi
        while IFS= read -r -d '' file; do
            relative="${file#"$entry/$stage/"}"
            if [[ -d "$file" && "$depth" == 3 ]]; then
                case "$relative" in
                    */*/*) die "影像子目录超过检查和序列两层：$file" ;;
                esac
                continue
            fi
            [[ -f "$file" ]] || die "阶段内含嵌套目录或异常对象：$file"
            case "$file" in
                *.[jJ][pP][gG]|*.[jJ][pP][eE][gG]|*.[pP][nN][gG]|*.[gG][iI][fF]|*.[tT][iI][fF]|*.[tT][iI][fF][fF]) ;;
                *.[rR][tT][fF])
                    [[ "$relative" != */* ]] || die "影像子目录内不允许 RTF：$file"
                    ;;
                *.[dD][cC][mM])
                    [[ "$depth" == 3 && "$relative" == */*/* ]] ||
                        die "DICOM 必须位于 2018 影像阶段的检查和序列目录内：$file"
                    DICOM_COUNT=$((DICOM_COUNT + 1))
                    ;;
                *) die "发现本批规范之外的文件，请先人工检查：$file" ;;
            esac
            STAGE_COUNT=$((STAGE_COUNT + 1))
            CLINICAL_COUNT=$((CLINICAL_COUNT + 1))
        done < <(find "$entry/$stage" -mindepth 1 -maxdepth "$depth" -print0)
        if [[ "$STAGE_COUNT" == 0 ]]; then
            : > "$entry/$stage/.gitkeep"
            PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT + 1))
        fi
    done
done < <(find "$PAYLOAD" -mindepth 1 -maxdepth 1 -print0)
[[ "$CASE_COUNT" -gt 0 && "$CLINICAL_COUNT" -gt 0 ]] || die "没有可上传的病例资料"

printf '本地目录：../dataset/%s/\n目标仓库：%s\n远端目录：%s/\n' "$YEAR" "$REPO" "$YEAR"
printf '病例：%s；病例文件：%s；缺项 README：1；空阶段占位：%s\n' \
    "$CASE_COUNT" "$CLINICAL_COUNT" "$PLACEHOLDER_COUNT"
if [[ "$YEAR" == 2017 || "$YEAR" == 2018 ]]; then
    printf '病例下的「原始资料」不上传。\n'
fi
if [[ "$YEAR" == 2018 ]]; then
    printf '其中 DICOM：%s。\n' "$DICOM_COUNT"
fi
printf '上传副本大小：%s\n' "$(du -sh "$PAYLOAD" | cut -f1)"
printf '\n以下是将上传的全部路径：\n'
while IFS= read -r -d '' file; do
    printf '  %s/%s\n' "$YEAR" "${file#"$PAYLOAD/"}"
done < <(find "$PAYLOAD" -type f -print0)
printf '\n已过滤系统文件、缓存、环境文件和旧占位文件；本地最终版未改动。\n'
if [[ "$DO_UPLOAD" == 0 ]]; then
    printf '当前仅预览，没有联网或上传。确认后用同样参数加 --upload。\n'
    exit 0
fi

for tool in hf jq shasum git cmp sort; do
    command -v "$tool" >/dev/null || die "缺少上传核对工具：$tool"
done

printf '\n正在检查登录与私有仓库……\n'
hf_cli auth whoami
if ! hf_cli datasets info "$REPO" --revision main --expand private,sha --json > "$WORK/info.json"; then
    die "无法访问目标仓库。请检查网络、地址及权限；没有上传，也不会自动创建仓库"
fi
jq -e '.private == true and (.sha | type == "string" and length > 0)' "$WORK/info.json" >/dev/null ||
    die "无法确认仓库为私有，取消上传"
BEFORE_SHA="$(jq -r '.sha' "$WORK/info.json")"

list_remote() {
    local revision="$1"
    local destination="$2"
    hf_cli datasets list "$REPO" --revision "$revision" --recursive --json > "$destination.raw"
    # The CLI prints "(empty)" for repositories with no files.
    if [[ "$(cat "$destination.raw")" == "(empty)" ]]; then
        printf '[]\n' > "$destination"
    else
        jq -e 'if type == "array" then . else error("unexpected file listing") end' \
            "$destination.raw" > "$destination"
    fi
}

list_remote "$BEFORE_SHA" "$WORK/before.json"
jq -e --arg year "$YEAR" 'all(.[]; .path != $year or .blob_id == null)' "$WORK/before.json" >/dev/null ||
    die "远端 $YEAR 是文件而不是目录，请先人工检查"
: > "$WORK/local.tsv"
while IFS= read -r -d '' file; do
    relative="$YEAR/${file#"$PAYLOAD/"}"
    bytes="$(wc -c < "$file" | tr -d ' ')"
    sha256="$(shasum -a 256 "$file" | cut -d ' ' -f1)"
    blob="$(git hash-object --no-filters -- "$file")"
    printf '%s\t%s\t%s\t%s\n' "$relative" "$bytes" "$sha256" "$blob" >> "$WORK/local.tsv"
done < <(find "$PAYLOAD" -type f -print0)
jq -Rn '[inputs | split("\t") | {path: .[0], size: (.[1] | tonumber), sha256: .[2], blob_id: .[3]}]' \
    < "$WORK/local.tsv" > "$WORK/local.json"

jq --arg prefix "$YEAR/" --slurpfile expected "$WORK/local.json" \
    '[.[] | select(.blob_id != null and (.path | startswith($prefix))) |
      .path as $path | select(($expected[0] | map(.path) | index($path)) == null) | .path]' \
    "$WORK/before.json" > "$WORK/extras.json"
if [[ "$(jq length "$WORK/extras.json")" != 0 ]]; then
    jq -r '.[]' "$WORK/extras.json" >&2
    die "远端 $YEAR/ 含本地没有的文件。请先确认，脚本不会删除它们或继续混合上传"
fi

printf '\n目标已确认是私有仓库。不会删除远端文件；同路径内容可能更新。\n'
reset_terminal
printf '确认上传 %s？[Y/n]：' "$YEAR"
confirmation=""
IFS= read -r confirmation || die "未收到确认，取消上传"
case "$confirmation" in
    ""|y|Y) ;;
    n|N) printf '已取消，没有上传。\n'; exit 0 ;;
    *) die "请输入 Y 或 n；已取消，没有上传" ;;
esac

# Refuse a changed branch or visibility between the review and upload.
hf_cli datasets info "$REPO" --revision main --expand private,sha --json > "$WORK/recheck.json"
jq -e --arg sha "$BEFORE_SHA" '.private == true and .sha == $sha' "$WORK/recheck.json" >/dev/null ||
    die "仓库可见性或版本在确认期间变化，请重新预览"

UPLOAD_ARGS=(
    upload "$REPO" "$PAYLOAD" "$YEAR"
    --repo-type dataset --revision main --private
    --commit-message "Upload curated $YEAR cases"
)
for pattern in "${EXCLUDES[@]}"; do
    [[ "$pattern" == .gitkeep ]] && continue
    UPLOAD_ARGS+=(--exclude "$pattern")
done
if ! hf_cli "${UPLOAD_ARGS[@]}"; then
    die "上传未正常结束，远端可能已有部分文件。修复网络或权限后重跑同一命令"
fi

printf '\n上传命令结束，正在核对远端文件……\n'
hf_cli datasets info "$REPO" --revision main --expand private,sha --json > "$WORK/after-info.json"
jq -e '.private == true and (.sha | type == "string" and length > 0)' "$WORK/after-info.json" >/dev/null ||
    die "上传后无法确认仓库仍为私有，请立即检查仓库设置"
AFTER_SHA="$(jq -r '.sha' "$WORK/after-info.json")"
list_remote "$AFTER_SHA" "$WORK/after.json"

jq -e --arg prefix "$YEAR/" --slurpfile expected "$WORK/local.json" '
  [.[] | select(.blob_id != null and (.path | startswith($prefix)))] as $actual |
  ($actual | sort_by(.path)) as $sorted |
  ($expected[0] | sort_by(.path)) as $wanted |
  ($sorted | length) == ($wanted | length) and
  all(range(0; $wanted | length);
    . as $i |
    $sorted[$i].path == $wanted[$i].path and
    $sorted[$i].size == $wanted[$i].size and
    (if $sorted[$i].lfs.sha256? != null
      then $sorted[$i].lfs.sha256 == $wanted[$i].sha256
      else $sorted[$i].blob_id == $wanted[$i].blob_id
     end))
' "$WORK/after.json" >/dev/null || die "远端 $YEAR/ 的路径、大小或校验值不一致，请检查；不要当作上传完成"

jq --arg prefix "$YEAR/" \
    '[.[] | select(.blob_id != null and .path != ".gitattributes" and ((.path | startswith($prefix)) | not)) |
      {path, size, blob_id}] | sort_by(.path)' "$WORK/before.json" > "$WORK/outside-before.json"
jq --arg prefix "$YEAR/" \
    '[.[] | select(.blob_id != null and .path != ".gitattributes" and ((.path | startswith($prefix)) | not)) |
      {path, size, blob_id}] | sort_by(.path)' "$WORK/after.json" > "$WORK/outside-after.json"
cmp -s "$WORK/outside-before.json" "$WORK/outside-after.json" ||
    die "核对期间 $YEAR/ 之外的文件发生变化，可能有其他人同时提交，请检查"

printf '完成：%s/%s/ 的全部路径、文件大小和内容校验值一致。\n' "$REPO" "$YEAR"
printf '其他业务文件未变；本地最终版未改动。远端提交：%s\n' "$AFTER_SHA"
