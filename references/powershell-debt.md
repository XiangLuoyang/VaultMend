# PowerShell 5.1 系统债 (4 条硬性规则)

> Windows PowerShell 5.1 (Desktop edition) 是 Windows 内置默认 shell，与 PowerShell 7+ 行为不一致。
> Loopen 工具链**仅**依赖 PS 5.1 + .NET API。下列 4 条债是从 v0.1-v0.9 实战中沉淀的硬性规则。

## 债 1: Get-Content 读 UTF-8 中文 → mojibake

**症状** `Get-Content $path` 把 UTF-8 中文按系统 codepage（中文 Windows = GBK/936）解读，得到乱码

**复现**
```powershell
Get-Content .\prd.json
# 期望: 中文 key/value 正确显示
# 实际: 出现"寰呰ˉ"等 mojibake 字符
```

**治本** 用 .NET API 显式 UTF-8 no-BOM
```powershell
$content = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false))
```

## 债 2: 函数必须在脚本顶部

**症状** `function X { ... }` 写在 `[CmdletBinding()]` 之上，PowerShell 报 parser error

**治本** 所有 function 定义必须在 `[CmdletBinding()]` 之前

## 债 3: Set-Location 中文路径 → 路径锁死

**症状** `Set-Location` 后切换到中文路径，跨 PS 5.1 / 7 行为不一致，且 cwd 依赖进程环境

**治本** 改用 `git -C $path <cmd>` 命令级
```powershell
git -C "C:\path\to\vault" add <file>
git -C "C:\path\to\vault" commit -F msg.txt
```

## 债 4: inline regex `(?ms)` 零长度 bug

**症状** `[regex]::Match($content, '(?ms)^...$')` 在 PS 5.1 脚本 context 下，inline options 被解析成 zero-width lookahead/lookbehind，导致整个 group 永远空捕获

**复现**
```powershell
$fmPattern = '(?ms)^---\r?\n(.*?)\r?\n---'
$fmMatch = [regex]::Match($content, $fmPattern)
# Success=True, Groups[1].Length=0  ← BUG
```

**治本** 构造 Regex 对象 + named group
```powershell
$fmPattern = New-Object System.Text.RegularExpressions.Regex('^---\r?\n(?<body>.*?)\r?\n---', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$fmMatch = $fmPattern.Match($content)
$body = $fmMatch.Groups['body'].Value
```

---

## 反事实: 为什么不升级到 PowerShell 7+

- **兼容**: PS 7+ 与 .NET Framework 一些组件兼容需测试
- **部署**: PS 7+ 不预装，OpenClaw Scheduled Tasks 强依赖 PS 5.1
- **治本充分**: 4 条债用 .NET API + named group + git -C 已全部绕开
- **6 个月后还成立**: 成立（除非 OpenClaw 改 PS 7+ 默认）

## 可复用的 lesson

- 任何调用 stdout / 文件 API 的链路都要显式切到 .NET / git 自身 UTF-8 通道
- Windows 终端环境对 UTF-8 **非原生**支持是 Loopen 工具栈的**系统性底层债**
- 这 4 条债是**踩坑治本**后的稳态，新加 PS 脚本时**先验证是否踩这 4 条**
