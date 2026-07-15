# Moonata

[![CI](https://github.com/rinnein/moonata/actions/workflows/ci.yml/badge.svg)](https://github.com/rinnein/moonata/actions/workflows/ci.yml)

Moonata 是 [JSONata](https://jsonata.org/) 的 MoonBit 实现。JSONata 是一门面向 JSON 数据的查询与转换语言。

本项目目前提供解析器、求值器、内建函数注册表、对外 facade API 与 native CLI。

## 功能

- JSONata 表达式解析与求值。
- 路径遍历、谓词、通配符、递归下降、变量、块表达式、Lambda、部分应用与函数链。
- 对象、数组、字符串、数值、布尔、日期时间、正则与高阶内建函数。
- Facade API：`evaluate(expr, data)` 与 `compile(expr).run(data)`。
- Embedding & Extending（对齐 [官方文档](https://docs.jsonata.org/embedding-extending)）：`evaluate_with_bindings`、`evaluate_with_options`、`Compiled::assign`、`Compiled::register_function`（支持 JSONata 签名语法 `<nn:n>` 等）。
- Guardrails（对齐 [官方文档](https://docs.jsonata.org/guardrails)）：`EvalOptions` 携带 `stack` / `timeout` / `sequence` 选项，超限分别抛 `D1011` / `D1012` / `D2015`；旧路径保持 `U1001` 向后兼容。
- Native CLI，支持 `--data`、`--file`、`--expr-file`、`--max-depth`、`--stack`、`--timeout`、`--sequence` 输入模式。

## CLI

构建 native 命令：

```bash
moon build cmd/main --target native
```

对 JSON 文件运行表达式：

```bash
moon run --target native cmd/main '$sum(Account.Order.Product.(Price * Quantity))' --file cmd/main/test.json
_build/native/debug/build/cmd/main/main.exe '$sum(Account.Order.Product.(Price * Quantity))' --file cmd/main/test.json
```

针对 `cmd/main/test.json` 的示例表达式：

```text
Account.'Account Name' -> "Firefly"
$sum(Account.Order.Product.(Price * Quantity)) -> 336.36
```

## 库 API

在 MoonBit 代码中调用时，使用根包 facade：

```moonbit nocheck
///|
let data = @json.parse("{\"items\":[{\"price\":10},{\"price\":20}]}")

///|
let result = @moonata.evaluate("$sum(items.price)", data)
```

需要重复求值时，可先编译一次：

```moonbit nocheck
///|
let expr = @moonata.compile("$sum(items.price)")

///|
let result = expr.run(data)
```

Embedding & Extending（对齐 [JSONata 官方文档](https://docs.jsonata.org/embedding-extending)）：

```moonbit nocheck
///|
// 注册自定义函数（含 JSONata 签名）
let expr = @moonata.compile("$add(61, 10005)")
expr.register_function("add", arity=2, signature=Some("<nn:n>"), invoke=fn(args, _ctx) {
  match args[0] {
    Json::Number(a, ..) =>
      match args[1] {
        Json::Number(b, ..) => Json::number(a + b)
        _ => Json::null()
      }
    _ => Json::null()
  }
})

///|
let result = expr.run(Json::null()) // 10066
```

Guardrails（对齐 [JSONata 官方文档](https://docs.jsonata.org/guardrails)）：

```moonbit nocheck
///|
let options = @moonata.EvalOptions::new(
  stack=Some(500), // 最大递归深度，超限抛 D1011
  timeout=Some(1000), // 最大执行时间毫秒，超限抛 D1012
  sequence=Some(1_000_000), // 最大序列长度，超限抛 D2015
)

///|
let result = @moonata.evaluate_with_options("$sum(items.price)", data, options)
```

上述 API 会在语法、运行时、类型、签名与护栏错误时抛出 `JsonataError`。

## 开发

常用验证命令：

```bash
moon check
moon test
moon fmt
moon info
```

提交代码变更前，应运行完整本地门禁，并检查生成的 `.mbti` diff 是否符合预期。提交信息使用 Conventional Commit 风格，例如：

```text
feat(functions): add basic formatNumber support
fix(evaluator): align predicate context semantics
docs: update official test status
```

## CI

仓库使用 GitHub Actions 执行以下门禁：

- `moon check --deny-warn`：类型检查、语法检查，警告视为错误
- `moon fmt --check`：格式校验
- `moon info`：接口生成
- `moon build --deny-warn`：构建，警告视为错误
- `moon test --deny-warn`：测试执行，警告视为错误

## 兼容性状态

固定快照：2026-07-15，CLI 参数解析移入 cmd/main 包阶段。

```text
本地测试：moon test 321/321
官方可比对审计：eligible 1682, pass 1682, fail 0, skip 0
通过率：100%
```

Top failures: 无

官方测试集审计流程与跳过策略记录在 `docs/jsonata-official-workflow.md`。
