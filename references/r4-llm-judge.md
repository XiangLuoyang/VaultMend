# R4 LLM Judge 准则

> R4 = 跨文件交叉引用一致性。需要 LLM 判断哪些是真实引用 / 哪些是字面表述。

## 5 条豁免规则（自动 KEEP，不强制转 wikilink）

1. **品牌名 / 产品名**（如 "AIP", "GPT", "DJI"）不算概念引用，保留原文
2. **H1 标题中的概念名**（如 `# 概念AIP 复刻`）不算引用
3. **表格 / 列表**中如已重指向上下文，不强制转 wikilink
4. **已有 markdown link** `[name](url)` 视为已链接，不强制转 `[[wikilink]]`
5. **正文中明确** "参见 X" / "X 框架" 模式 → 建议转 `[[concept-X]]`

## LLM Judge 输入

- 文档全文
- vault 文件名集合（用于比对目标是否存在）
- 上述 5 条豁免规则

## LLM Judge 输出

每个候选引用输出 verdict: `KEEP` / `ADD_WIKILINK` / `ADD_TODO` + 理由

## 适用 R4 的代价

- LLM call 数 ≈ 文档数（每文档一次）
- token 成本：vault 全文档 ~50KB context，单次 LLM 即可跑完
- 不阻塞 verifier: R4 fail → NEEDS-REVIEW（不阻塞 R1-R3 apply）

## 反事实验证

如果只有 R1-R5（不要 R4 LLM judge）会怎样？
- 答: 大量"叙事风格不符"或"品牌名误判"的文件通过 verifier，被 false-positive 标记为 NEEDS-REVIEW
- R4 LLM judge 的作用: 把"非真实引用"从 false-positive 降到 0
