"""Exercise real Return input in a pseudo-terminal, using only a mock HF."""

import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import termios
import time


here = Path(__file__).resolve().parent
stages = [
    "病例评估", "影像诊断", "会诊", "手术规划",
    "术前准备", "手术分期或干预", "并发症", "术后复查",
]
with tempfile.TemporaryDirectory(prefix="hku-upload-tty-test.") as root:
    root = Path(root)
    source = root / "dataset" / "2014"
    repo = root / "hku-dataset-curation"
    (repo / "scripts").mkdir(parents=True)
    script = repo / "scripts" / "upload_dataset.sh"
    shutil.copyfile(here.parent / "upload_dataset.sh", script)
    for stage in stages:
        (source / "测试患者" / stage).mkdir(parents=True)
    (source / "README.md").write_text("未提供的记录有：\n")
    (source / "测试患者" / "影像诊断" / "MRI.jpg").write_bytes(b"test-image")
    (root / "bin").mkdir()
    (root / "state").mkdir()
    (root / "bin" / "hf").symlink_to(here / "mock_hf.sh")
    env = {
        **os.environ,
        "PATH": str(root / "bin") + os.pathsep + os.environ["PATH"],
        "MOCK_STATE": str(root / "state"),
        "MOCK_SCENARIO": "tty",
    }
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ["bash", "./scripts/upload_dataset.sh", "--year", "2014", "--upload"],
        stdin=slave, stdout=slave, stderr=slave, env=env, cwd=repo,
    )
    output = bytearray()
    sent = False
    deadline = time.monotonic() + 30
    try:
        while process.poll() is None:
            if time.monotonic() > deadline:
                raise AssertionError("Timed out waiting for terminal confirmation")
            readable, _, _ = select.select([master], [], [], 0.1)
            if readable:
                output.extend(os.read(master, 65536))
            if not sent and "[Y/n]：".encode() in output:
                attrs = termios.tcgetattr(slave)
                assert attrs[0] & termios.ICRNL, "Return is not mapped to newline"
                assert attrs[3] & termios.ICANON, "Canonical input not restored"
                os.write(master, b"\r")
                sent = True
        while select.select([master], [], [], 0)[0]:
            output.extend(os.read(master, 65536))
        assert sent and process.returncode == 0, output.decode(errors="replace")
        assert (root / "state" / "uploaded").exists()
        assert termios.tcgetattr(slave)[0] & termios.ICRNL
        print("PASS: real Return works after mock CLI disrupts terminal settings; no network used")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
