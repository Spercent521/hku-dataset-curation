#!/usr/bin/env python3
"""Compare the offline upload preview with a fixed private Hub revision."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


SCRIPTS = Path(__file__).resolve().parent
DATASET = SCRIPTS.parent.parent / "dataset"
REPO = "AIMedrui/Spine_agentbench"


def run(*args):
    return subprocess.check_output(args, stdin=subprocess.DEVNULL, encoding="utf-8")


def matches(path, entry, placeholder):
    size = 0 if placeholder else path.stat().st_size
    if size != entry["size"]:
        return False
    sha256 = (entry.get("lfs") or {}).get("sha256")
    digest = hashlib.sha256() if sha256 else hashlib.sha1(f"blob {size}\0".encode())
    if not placeholder:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest() == (sha256 or entry["blob_id"])


def verify(year):
    prefix = f"{year}/"
    print("正在生成本地上传预览清单……", flush=True)
    preview = run("bash", str(SCRIPTS / "upload_dataset.sh"), "--year", year)
    expected = {
        line[2:] for line in preview.split("\n") if line.startswith(f"  {prefix}")
    }
    if not expected:
        raise ValueError("本地预览没有文件清单")

    info = json.loads(run("hf", "datasets", "info", REPO, "--revision", "main",
                          "--expand", "private,sha", "--json"))
    revision = info.get("sha")
    if info.get("private") is not True or not revision:
        raise ValueError("无法确认目标为私有仓库或取得远端提交")

    print(f"正在比对 {len(expected):,} 份文件……", flush=True)
    listing = run("hf", "datasets", "list", REPO, "--revision", revision,
                  "--recursive", "--json").strip()
    entries = [] if listing == "(empty)" else json.loads(listing)
    if not isinstance(entries, list):
        raise ValueError("远端清单格式异常")
    remote = {
        entry["path"]: entry for entry in entries
        if entry.get("blob_id") and entry["path"].startswith(prefix)
    }
    different = []
    for name in sorted(expected & remote.keys()):
        relative = Path(name)
        if not matches(DATASET / relative, remote[name], relative.name == ".gitkeep"):
            different.append(name)

    groups = [
        ("远端缺少", expected - remote.keys()),
        ("远端多出", remote.keys() - expected),
        ("大小或内容不同", different),
    ]
    for label, paths in groups:
        if paths:
            print(f"{label}：{len(paths):,} 份（最多显示 10 条）")
            for path in sorted(paths)[:10]:
                print(f"  {path}")
    if any(paths for _, paths in groups):
        print("核验未通过。请先检查差异，不要直接重传。")
        return 1
    print(f"核验通过：{len(expected):,} 份文件的路径、大小和内容一致。")
    print(f"远端提交：{revision}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="只读核验已上传的年度数据集")
    parser.add_argument("--year", required=True, help="四位年份，例如 2018")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]{4}", args.year):
        parser.error("--year 必须是四位年份")
    try:
        return verify(args.year)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"核验中止：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
