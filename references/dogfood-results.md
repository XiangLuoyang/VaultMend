# Dogfood 战绩 (≥ 7 个独立 target)

> Dogfood = 用 Loopen 工具链 audit + 修 Loopen 自身（or 任意 Obsidian vault）。
> "独立 target" = 至少 1 个差异轴 (size / topic / broken count / file type)。
> 单 target PASS 不足以下结论"pipeline OK"。

## 战绩总览

| 版本 | 工具 | dogfood target | PASS 率 | 暴露盲区 |
|------|------|----------------|---------|----------|
| v0.1 | run-loop | 2 | 100% | 2 真盲区 (patch 格式 + UTF-8) |
| v0.2 | + patch validator | 5 | 100% | 修盲区 |
| v0.2.1 | bug fix | 6 | 100% | — |
| v0.2.2 | bug fix | 7 | 100% | 稳定基线 |
| v0.3 | + phase1-auto | 38 vault files | 35 applied + 3 skipped | R3 false positive (漏子目录) |
| v0.7 | autonomous mode | 5 targets | 100% | real-world vault apply PASS |
| v0.8.0 | advisory | 2 targets | 100% | FAIL→WARN 降级 |
| v0.8.1 | rollback | 2 targets | 100% | all-or-nothing 验证 |
| v0.8.2 | concurrent | 3 tasks | 100% in 1.33s | multi-process 收口 |

**累计**: ≥ 7 个独立 target（v0.1-v0.2.2）+ ≥ 12 个 v0.3+ target，跨 9 个版本，0 false negative。

## 反事实

- **单 target PASS 不足**: v0.1 时 1 个 target 通过，2 个真盲区在 v0.2 才暴露 → ≥3 target 是 pipeline 验证最小剂量
- **同形态 target 不够**: 多个 50 行 concept doc PASS 仍漏 500 行 + broken wikilink 多的文件 → size / topic 维度必须有差异
