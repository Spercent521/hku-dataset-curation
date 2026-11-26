# 上传数据集

## 文件怎么放

新建一个父目录，下面叫它 `root`。它可以叫任何名字。
把本仓库和 `dataset` 文件夹放在一起：

```text
root/
├── hku-dataset-curation/        本仓库
│   ├── README.md
│   └── scripts/
│       ├── README.md
│       ├── upload_dataset.sh
│       └── verify_uploaded_dataset.py
└── dataset/                    已审核的最终资料
    ├── 2014/
    │   ├── README.md           缺失记录
    │   └── 患者文件夹/
    │       ├── 病例评估/
    │       ├── 影像诊断/
    │       ├── 会诊/
    │       ├── 手术规划/
    │       ├── 术前准备/
    │       ├── 手术分期或干预/
    │       ├── 并发症/
    │       └── 术后复查/
    └── 2015/
```

`dataset` 不要放进仓库里。它和仓库是同级文件夹。
每个年份需要一份缺失记录 `README.md`。
每个患者需要八个阶段文件夹，缺资料的文件夹留空。
阶段内可放 JPG、JPEG、PNG、GIF、TIFF 或 RTF 文件，默认不嵌套目录。
2017 和 2018 的上传副本会排除病例下的「原始资料」，本地原件不动。
2018 的「影像诊断」和「术后复查」允许最多两层影像子目录；DICOM 按「检查目录 → 序列目录 → `.dcm` 文件」保留，不打平序列。

## 登录

电脑需要安装 `hf`、`jq`、Git 和 rsync。脚本使用 Bash，不需要激活 Conda。
在仓库根目录打开终端，执行：

```bash
hf auth login
hf auth whoami
```

每个人用自己的 HF 账号和 Token 登录。
账号和 Token 都要有目标仓库的直接写入权限。
不要把 Token 写进脚本。

## 上传 2014

以下命令都在 `hku-dataset-curation` 仓库根目录执行。

先预览：

```bash
bash ./scripts/upload_dataset.sh --year 2014
```

脚本读取 `../dataset/2014/`，列出准备上传的文件。预览不联网、不上传。

确认文件正确，再上传：

```bash
bash ./scripts/upload_dataset.sh --year 2014 --upload
```

出现 `确认上传 2014？[Y/n]：` 时，按回车继续，输入 `n` 取消。
看到“完成”才表示上传和核对都成功。

目标固定为私有仓库 `AIMedrui/Spine_agentbench`。
2014 年的文件直接放在远端根目录的 `2014/` 下。

## 上传其他年份

把 2015 年的最终资料放在 `../dataset/2015/`。
预览和上传命令分别是：

```bash
bash ./scripts/upload_dataset.sh --year 2015
bash ./scripts/upload_dataset.sh --year 2015 --upload
```

以后每年只改年份，不需要改脚本。

## 只核验，不重传

如果上传命令已返回成功，但随后的远端核验中断，先不要重跑 `--upload`。
保持本地发布版不变，在仓库根目录运行（需要 Python 3 和已登录的 `hf`）：

```bash
python3 ./scripts/verify_uploaded_dataset.py --year 2018
```

脚本从离线预览取得预期清单，只读查询目标私有仓库的固定提交，并对比年度目录下每份文件的路径、大小和内容校验值。出现差异时会按缺少、多出或内容不同分别列出；先确认本地版是否在上传后改过。该核验不会修改远端，也不检查其他年份在上传期间是否发生变化。

## 哪些东西不会改

脚本不修改本地最终资料，不上传其他年份，不删除远端文件。
`.DS_Store` 等系统文件会被过滤。
空阶段会在上传副本中加入 `.gitkeep`，让远端保留这些文件夹。
远端同路径文件可能被更新。
该年份下存在本地没有的文件时，脚本会停止。

## 其他脚本

`inspect_pptx.py` 用来检查 PPTX 内部对象，与上传无关。
`tests/` 用来测试上传脚本，日常使用不需要运行。
