#!/bin/bash
# All remote operations use a local mock CLI; never contact Hugging Face.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/hku-upload-test.XXXXXX")"
trap 'find "$WORK" -depth -delete' EXIT
mkdir -p "$WORK/bin" "$WORK/hku-dataset-curation/scripts" "$WORK/dataset/2014"
cp "$HERE/../upload_dataset.sh" "$WORK/hku-dataset-curation/scripts/upload_dataset.sh"
SCRIPT="$WORK/hku-dataset-curation/scripts/upload_dataset.sh"
SOURCE="$WORK/dataset/2014"
cd "$WORK/hku-dataset-curation"
ln -s "$HERE/mock_hf.sh" "$WORK/bin/hf"
export PATH="$WORK/bin:$PATH"
export MOCK_STATE="$WORK/state"
STAGES=("病例评估" "影像诊断" "会诊" "手术规划" "术前准备" "手术分期或干预" "并发症" "术后复查")
for stage in "${STAGES[@]}"; do
    mkdir -p "$SOURCE/测试患者 0001/$stage"
done
printf '未提供的记录有：\n' > "$SOURCE/README.md"
printf 'test-image\n' > "$SOURCE/测试患者 0001/影像诊断/MRI-01.jpg"
printf 'ignore\n' > "$SOURCE/.DS_Store"
printf 'ignore\n' > "$SOURCE/测试患者 0001/会诊/._image.jpg"
mkdir -p "$SOURCE/__MACOSX" "$SOURCE/.git"
printf 'ignore\n' > "$SOURCE/__MACOSX/junk"
printf 'ignore\n' > "$SOURCE/.git/config"

snapshot() {
    (
        cd "$SOURCE"
        find . -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
    )
}
snapshot > "$WORK/before"
bash "$SCRIPT" --year 2014 > "$WORK/preview.log"
[[ ! -e "$MOCK_STATE/calls" ]]
grep -q '病例文件：1；缺项 README：1；空阶段占位：7' "$WORK/preview.log"
grep -q '2014/README.md' "$WORK/preview.log"
grep -q '本地目录：../dataset/2014/' "$WORK/preview.log"
grep -q '2014/测试患者 0001/会诊/.gitkeep' "$WORK/preview.log"
! grep -q '\.DS_Store\|__MACOSX\|2014/2014/' "$WORK/preview.log"
[[ -z "$(find "$SOURCE" -name .gitkeep -print)" ]]
printf 'PASS: offline preview, filtering, empty stages, and remote prefix\n'

for option in --source --repo; do
    if bash "$SCRIPT" "$option" ignored > "$WORK/option.log" 2>&1; then
        exit 1
    fi
done
if bash "$SCRIPT" > "$WORK/year.log" 2>&1; then
    exit 1
fi
cp -R "$SOURCE" "$WORK/dataset/2015"
bash ./scripts/upload_dataset.sh --year 2015 > "$WORK/2015.log"
grep -q '本地目录：../dataset/2015/' "$WORK/2015.log"
grep -q '远端目录：2015/' "$WORK/2015.log"
printf 'PASS: repository-root usage, another year, and simplified options\n'

for scenario in success public inaccessible extras corruption checksum outside; do
    export MOCK_SCENARIO="$scenario"
    export MOCK_STATE="$WORK/state-$scenario"
    mkdir "$MOCK_STATE"
    if printf '\n' | bash "$SCRIPT" --year 2014 --upload > "$WORK/$scenario.log" 2>&1; then
        [[ "$scenario" == success ]]
        grep -q '全部路径、文件大小和内容校验值一致' "$WORK/$scenario.log"
        [[ -f "$MOCK_STATE/uploaded" ]]
        [[ ! -d "$(cat "$MOCK_STATE/payload-path")" ]]
    else
        [[ "$scenario" != success ]]
        case "$scenario" in
            public|inaccessible|extras) [[ ! -e "$MOCK_STATE/uploaded" ]] ;;
            corruption|checksum|outside) [[ -e "$MOCK_STATE/uploaded" ]] ;;
        esac
    fi
    printf 'PASS: %s\n' "$scenario"
done

export MOCK_SCENARIO=success MOCK_STATE="$WORK/state-cancel"
mkdir "$MOCK_STATE"
printf 'n\n' | bash "$SCRIPT" --year 2014 --upload > "$WORK/cancel.log" 2>&1
[[ ! -e "$MOCK_STATE/uploaded" ]]
printf 'PASS: n cancels without uploading\n'

printf 'unexpected\n' > "$SOURCE/extra.txt"
if bash "$SCRIPT" --year 2014 > "$WORK/extra.log" 2>&1; then
    exit 1
fi
find "$SOURCE" -maxdepth 1 -name extra.txt -delete
ln -s "$WORK/before" "$SOURCE/测试患者 0001/病例评估/link.jpg"
if bash "$SCRIPT" --year 2014 > "$WORK/link.log" 2>&1; then
    exit 1
fi
find "$SOURCE" -type l -delete
snapshot > "$WORK/after"
cmp "$WORK/before" "$WORK/after"
printf 'PASS: unexpected files and symlinks rejected; original files unchanged\n'
