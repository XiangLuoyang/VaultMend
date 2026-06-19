# R6 LLM Judge 准则

> R6 = 内容语义一致性（frontmatter 与 body 一致性）。需要 LLM 按 confidence 分档处理。

## 三档 confidence

| 档 | 含义 | 处理 |
|----|------|------|
| **High** | 结构性 bug (R1 缺 closing `---`, R2 H1 错位, R2 缺 H1) | auto-apply（无需人 review） |
| **Medium** | 启发式推断 (缺 tags, 缺 summary) | auto-apply + 1-2 tags per file, 域检测用 file name 前缀 |
| **Low** | 主观性 (narrative type 偏差, 风格不符) | 用户审（不 auto-apply） |

## 6 条硬性规则

1. **frontmatter 完整性**: 6 字段必须齐全 (title/created/updated/type/status/narrative)
2. **summary 必填**: 一句话总结文档核心内容
3. **tags 必填**: 至少 1 个 tag（推荐 `concept` + 域）
4. **H1 唯一性**: 只能有一个 H1（在 abstract 之后，如果有 abstract callout）
5. **narrative type 必填**: analytical / reflective / practical / theoretical / narrative / prescriptive
6. **类型匹配**: 域检测按 file name 前缀（`concept-` / `entity-` / `synthesis-` / `tool-` / `template-` / `index-`），不扫描 body（避免误判）

## 治本两个 bug

- **duplicate tags 行**: medium 档算法第一版把"file name 前缀"和"body 关键词"叠加，导致同一文件出现两行 `tags:` → 治本：单源 = file name 前缀
- **bad domain detection**: 第一版把 "Adobe PDF" 误判为 "AI" 域（body 扫描）→ 治本：放弃 body 扫描，只用 file name 前缀

## 适用 R6 的代价

- LLM call 数 ≈ 文档数（每文档一次）
- 1-2 tag per file 限制让 tag 系统可用（无限制 → 噪音）
- 治本后 0 false positive

## 反事实验证

如果按"全 LLM judge 后 auto apply"会怎样？
- 答: token 成本 ×10，autonomous mode 下不必要
- 治本: 三档 confidence（high auto / medium heuristic / low user）省 token + 可解释
