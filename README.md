# HKU-数据集整理

将混乱的骨科病例材料整理为统一的八阶段病例目录，保留缺项，只整理原始材料已有的事实。

这是供 AI 助手执行的 skill，不是一键分类程序，也不是临床诊断工具。目前的规范主要来自脊柱病例整理实践；其他骨科场景应结合使用者提供的样例核对适用性。名称不表示任何机构的官方认可或背书。

## 整理结果

每个病例一个文件夹，每例恰有以下八个阶段目录：

```text
<输出目录>/
  README.md
  <病例标识>/
    病例评估/
    影像诊断/
    会诊/
    手术规划/
    术前准备/
    手术分期或干预/
    并发症/
    术后复查/
```

- 缺项留空，不补写诊断、参数、医生评价或阴性结论。
- 提取实际的 X线、CT、MRI、照片、参数表和医学报告，不交付整页 PPT 截图或聊天界面。
- 保留医学标注、时间关系及有意义的对照，文件名描述内容，而非“微信图片”等来源。
- 已有病史、查体和诊疗叙述按规范整理为 RTF；原有完整报告或参数表可保留为图像。
- 批次根目录另附一份极简缺项 `README.md`，开头为“未提供的记录有：”，按“患者姓名 → 阶段 → 缺失记录”列树状清单；只列缺项，不逐项重复“未提供”，不列已有内容或分析。
- 缺项以确认的样例或项目清单及实际检查为依据；质量排除、未读和待确认不混写为未提供。最终目录不附其他整理报告、来源表、待确认区或中间文件。

## 安装

### 推荐：使用 npx 安装

需要 Node.js 22.20 或更高版本。在项目目录中运行：

```bash
npx skills add Spercent521/hku-dataset-curation
```

按提示选择 skill 和目标 AI 工具（如 Codex）。默认安装到当前项目；希望跨项目使用时，加上 `-g`：

```bash
npx skills add Spercent521/hku-dataset-curation -g
```

这里使用的是开源的 [skills 安装工具](https://github.com/vercel-labs/skills)，它从 GitHub 获取本 skill，无需手动下载或复制文件。安装位置由该工具管理，不必再执行下面的手动安装。

### 备选：手动安装

不使用 npx 时，可将本仓库完整放入 Codex 的个人 skill 目录，目录名保持为 `hku-dataset-curation`：

```text
~/.codex/skills/hku-dataset-curation/
  SKILL.md
  agents/
  references/
  scripts/
```

可以从 GitHub 克隆完整仓库：

```bash
git clone https://github.com/Spercent521/hku-dataset-curation.git ~/.codex/skills/hku-dataset-curation
```

不要只复制 `SKILL.md`，配套规范和辅助脚本也需要保留。如果目标目录已经存在，应先检查已有版本，不要直接覆盖。

## 使用

向支持本地文件访问和图文检查的 AI 助手提供原始材料位置、独立输出位置，以及可选的参考样例。例如：

```text
使用 $hku-dataset-curation 整理这批病例。
原始材料：<原始材料目录>
输出位置：<新的输出目录>
参考样例：<可选的样例目录>
只整理已有内容，缺项留空，不修改原始材料。
```

支持的材料包括 PPT/PPTX、图片、报告和文档，以及不规则的多层目录。实际读取能力取决于执行环境中的本地查看、转换和 OCR 工具。无法读取或存在阻断性归属问题时，助手必须说明限制，不能声称已完成。

## 文件说明

| 文件                            | 用途                           |
| ------------------------------- | ------------------------------ |
| `SKILL.md`                      | 入口、工作流程与不可违反的边界 |
| `agents/openai.yaml`            | 显示名称和默认调用提示         |
| `references/sample-standard.md` | 八阶段布局、内容类型和命名规范 |
| `references/evidence-rules.md`  | 来源、时间关系、保真与冲突处理 |
| `references/quality-check.md`   | 核对与验收规则                 |
| `scripts/inspect_pptx.py`       | 本地盘点 PPTX 对象的辅助工具   |

辅助脚本仅依赖 Python 3.8+ 标准库：

```bash
python3 scripts/inspect_pptx.py /path/to/source.pptx
python3 scripts/inspect_pptx.py /path/to/source.pptx --output /path/to/work/inventory.json
```

该脚本不导出病例成品、不识别图片语义，也不自动决定病例归属或阶段。输出清单属于临时核对资料，不应放进最终病例目录。旧 PPT 需先在本地工作副本中转换，并核对转换保真。

## 隐私与边界

- 本仓库不包含真实病例、患者图片、检查报告或数据集。
- 在使用者有权处理的资料范围内使用；默认本地处理，不主动上传第三方服务。
- 公开问题、讨论和贡献中不要包含患者身份信息、原始影像或未脱敏日志。
- 本 skill 不替代临床诊断、医学建议、隐私合规审核或专业人员复核。

## 许可证

本仓库的规则文本和辅助代码采用 [MIT License](LICENSE)。许可证不授予任何病例数据或第三方材料的使用权。
