# Moonata

Moonata 是 [JSONata](https://jsonata.org/) 的 MoonBit 实现。JSONata 是一门面向 JSON 数据的查询与转换语言。

本项目目前提供解析器、求值器、内建函数注册表、对外 facade API 与 native CLI。项目仍在对齐上游 `jsonata-js` 官方测试集，因此当前状态是“可用但尚未完全替代原版 JSONata”。

## 功能

- JSONata 表达式解析与求值。
- 路径遍历、谓词、通配符、递归下降、变量、块表达式、Lambda、部分应用与函数链。
- 对象、数组、字符串、数值、布尔、日期时间、正则与高阶内建函数。
- Facade API：`evaluate(expr, data)` 与 `compile(expr).run(data)`。
- Native CLI，支持 `--data` 与 `--file` 输入模式。
- MoonBit 包结构与生成的 `.mbti` 接口文件。

## CLI

构建 native 命令：

```bash
moon build cmd/main --target native
```

对 JSON 文件运行表达式：

```bash
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

## 兼容性状态

固定快照：2026-06-29，P11 `in` 运算符修复阶段。

```text
moon test: 165/165
official comparable audit: eligible 1251, pass 979, fail 272, skip 431
```

当前剩余失败最多的官方测试分组：

```text
function-tomillis 34
joins 28
parent-operator 20
function-formatNumber 16
sorting 16
function-fromMillis 15
object-constructor 14
flattening 13
transforms 11
descendent-operator 7
```

官方测试集审计流程与跳过策略记录在 `.codebuddy/rules/moonata_项目实现指南.mdc`。
