# R1-R6 规则定义

Loopen 对 Obsidian vault 做质量审查的 6 条规则。规则集可扩展（新增 R7、R8 写在新增章节，**不**改本节）。

## R1: frontmatter 完整性

**要求** frontmatter 必须包含 6 字段: `title`, `created`, `updated`, `type`, `status`, `narrative`

**检测** 正则 `^---\r?\n(?<body>.*?)\r?\n---` (Singleline, named group)

**修复** v0.9 A 起走 full content 模式（不生成 diff patch）——phase1-auto 写 `proposed-changes/<orig-filename>` 完整文件，phase2-batch 直接 cp 到 vault。created/updated 时间戳需要 LLM 判断（"v0.9 A 治本 = R1 auto-fix 路径决策"）

## R2: H1 位置

**要求** `# 标题` 必须在 `> [!abstract]` 之后（如果文档有 abstract callout）

**检测** 找 H1 行 + 找 abstract 行，比较位置

**修复** 移动 H1 到 abstract 块之后（auto-fix OK）

## R3: broken wikilinks

**要求** `[[name]]` 必须指向 vault 中存在的文件（递归扫 vault 全 .md 文件名）

**检测** 提取所有 `[[...]]` 链接，检查是否在 vault 文件名集合中

**修复** 替换为 `[TODO: 待补 name]`（auto-fix OK）
- 建议 commit message: `lint: R3 N broken wikilinks to TODO`

## R4: 交叉引用一致性

**要求** 文档中提到的其他概念/项目应该在 vault 中有对应文件

**检测** 提取文档中所有 `[[wikilink]]` 和明显的概念名引用，比对 vault 文件树

**修复** 需要 LLM 判断哪些是真实引用 / 哪些是字面表述（品牌名/H1/markdown link/表格内 都不强制）

## R5: BOM

**要求** 文件不能有 UTF-8 BOM

**检测** 检查文件前 3 字节是否为 `EF BB BF`

**修复** 手动删除 BOM（PS 5.1 + Get-Content 不读 BOM，但 .NET WriteAllText + UTF8Encoding 会写 BOM，需要显式 `new($false)`）

## R6: 内容语义一致性

**要求** 文档内容与 frontmatter metadata 一致（narrative type / tags / summary 匹配）

**检测** 需要 LLM（按 confidence 分 high/medium/low 三档）

**修复** 详见 `references/r6-llm-judge.md`

---

## 规则扩展约定

- **新增 R7+ 必须沉淀到本文件**（R1-R6 节保持稳定，新规则写新章节）
- **每条规则有 4 段**: 要求 / 检测 / 修复 / 当前状态（"当前状态" 在 dogfood 后填，commit message 里 cite）
- **auto-fix 风险高的规则**（R1）必须 LLM 判断；auto-fix 风险低的（R2/R3）可直接 phase2-batch 批量

## 反事实测试

如果只有 R1-R5（不要 R6 LLM judge）会怎样？
- 答: 大量"叙事风格不符"的文件通过 verifier，被 false-positive 标记为 NEEDS-REVIEW
- R6 LLM judge 的作用: 把"风格不一致"从 false-positive 降到 0
- 来源: v0.5 收口记录
