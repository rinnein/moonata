# Moonata 架构设计

> 将 [JSONata](https://jsonata.org/) 移植至 MoonBit 语言的架构设计文档。
> 本文档为项目的权威架构依据，所有代码实现须遵循此处定义的包结构、类型边界与依赖关系。

## 1. 项目目标

- 在 MoonBit 中实现 JSONata 语言的核心语义：路径表达式、谓词、排序、分组、Lambda、60+ 内建函数、序列模型与函数签名系统。
- 对外暴露与 `@json.JsonValue` 互通的简洁 facade API。
- 保持与 MoonBit 工具链（`moon check/test/fmt/info`）兼容，遵循 block 风格（`///|`）。
- 通过分阶段开发，每阶段可独立验证并提交 Git。

## 2. JSONata 核心特性清单

| 类别 | 特性 |
| --- | --- |
| 字面量 | string / number / boolean / null |
| 路径 | 标识符、字段访问、`.*`、递归降序 `**`、数组下标 `[n]`、切片 `[a:b]` |
| 谓词 | 过滤表达式 `[expr]`（布尔或位置） |
| 表达式 | 算术、比较、布尔、字符串拼接、`&` 合并 |
| 序列 | 平坦序列、单例提升、`undefined` 传播 |
| 分组 | `{ ... }` 分组表达式、多级分组 |
| 排序 | `^(...)` 排序表达式 |
| Lambda | `function($a, $b){ ... }`、部分应用、函数链 ` ~> ` |
| 变量 | `$var`、`$` 根、`@` 当前、`$$` 父级 |
| 内建函数 | 60+：字符串、数值、聚合、数组、对象、类型转换、高阶、正则、日期等 |
| 函数签名 | 类型化参数与返回值、类型检查 |
| 嵌入/扩展 | 注册自定义函数、超时与递归护栏 |

## 3. MoonBit 兼容性评估

| 维度 | JSONata 需求 | MoonBit 支持 | 评估 |
| --- | --- | --- | --- |
| 代数数据类型 | AST 节点（20+ 种） | `enum` + 模式匹配 | 完美匹配 |
| 错误处理 | 语法/运行时/类型错误 | `suberror` + `raise` | 完美匹配 |
| JSON 互操作 | 输入/输出 JSON | `@json.JsonValue` | 完美匹配 |
| 闭包/高阶 | Lambda、`$map`/`$filter` 等 | 闭包、一等函数 | 完美匹配 |
| 有序映射 | 分组、对象保留顺序 | `Map[String, T]`（插入有序） | 完美匹配 |
| 双精度浮点 | 数值计算 | `Double` | 完美匹配 |
| 字符串处理 | 大量字符串函数 | `String`（UTF-16）、`@utf8` | 良好 |
| 正则表达式 | `$match`/`$contains` | 标准库无内建正则 | 需评估第三方或简化实现 |
| 模式匹配 | AST 求值 | `match` + 标签字段 | 完美匹配 |
| 块组织 | 大型代码组织 | `///|` block 风格 | 完美匹配 |
| 测试 | 快照/断言 | `inspect`/`assert_eq`/`debug_inspect` | 完美匹配 |

**结论**：除正则外，MoonBit 与 JSONata 高度兼容。正则相关函数延后至阶段 6 评估。

## 4. 包架构

```
moonata/                       # facade 包（根），对外暴露 evaluate/compile API
├── moon.mod
├── moon.pkg                   # 依赖 error/ast/value/evaluator/functions
├── moonata.mbt                # facade 实现
├── moonata_test.mbt           # 黑盒测试
├── moonata_wbtest.mbt         # 白盒测试
├── error/                     # 错误类型层级
│   └── moon.pkg               # 无内部依赖（最底层）
├── ast/                       # AST 定义
│   └── moon.pkg               # 依赖 error
├── value/                     # 运行时值类型
│   └── moon.pkg               # 依赖 error（与 ast 解耦）
├── lexer/                     # 词法分析
│   └── moon.pkg               # 依赖 error
├── parser/                    # 语法分析
│   └── moon.pkg               # 依赖 error/ast/lexer
├── evaluator/                 # 求值器
│   └── moon.pkg               # 依赖 error/ast/value
├── functions/                 # 60+ 内建函数
│   └── moon.pkg               # 依赖 error/ast/value/evaluator
└── cmd/
    └── main/                  # CLI 入口
        ├── moon.pkg           # is-main，依赖 moonata
        └── main.mbt
```

共 **8 个库包** + **1 个 CLI 包**。

### 4.1 依赖图（无环）

```
        error (底层，无依赖)
        /  |  \    \
      ast  value lexer
        \   |   /
         parser
            |
        evaluator
            |
         functions
            |
         moonata (facade)
            |
         cmd/main
```

依赖方向严格自底向上，禁止反向依赖。

### 4.2 各包职责

| 包 | 职责 | 公开类型 |
| --- | --- | --- |
| `error` | 错误类型层级，所有包共享 | `JsonataError` 及其变体 |
| `ast` | AST 节点定义、遍历、相等 | `Ast` enum、`Step`、`SortTerm` |
| `value` | 运行时值、序列操作、单例提升 | `JsonataValue`、`EvalContext` |
| `lexer` | 词法 token、词法分析 | `Token`、`Lexer` |
| `parser` | 递归下降语法分析 | `Parser`、`parse` |
| `evaluator` | AST→值求值、序列语义 | `Evaluator`、`eval` |
| `functions` | 60+ 内建函数实现与注册 | `register_builtins`、签名 |
| `moonata` | facade：编译/求值入口 | `evaluate`、`compile` |

## 5. 关键类型设计

### 5.1 Ast（`ast` 包）

```moonbit
pub(all) enum Ast {
  String(String)
  Number(Double)
  Boolean(Bool)
  Null
  // 路径
  Path(steps : Array[Step])
  // 标识符片段
  Name(name : String, recursive~ : Bool)
  Wildcard(recursive~ : Bool)
  // 下标/切片/过滤
  Index(Int)
  Slice(start~ : Int?, end~ : Int?)
  Filter(expr : Ast)
  // 表达式
  Binary(op~ : String, lhs~ : Ast, rhs~ : Ast)
  Unary(op~ : String, expr : Ast)
  // 序列构造
  Construct(items : Array[Ast])
  // 分组
  Group(pairs : Array[(Ast, Ast)])
  // 排序
  Sort(expr : Ast, terms~ : Array[SortTerm])
  // Lambda
  Lambda(params : Array[String], body : Ast)
  // 变量与函数调用
  Var(name : String)
  Bind(name~ : String, value~ : Ast, body~ : Ast)
  Apply(func : Ast, args : Array[Ast])
  // 函数链
  Chain(stages : Array[Ast])
  // 块
  Block(exprs : Array[Ast])
} derive(Debug)

pub(all) struct Step {
  kind : StepKind
  stage : StepStage
} derive(Debug)

pub(all) enum StepKind { Name(String); Wildcard; Index(Int); Slice(Int?, Int?); Filter(Ast) }
pub(all) enum StepStage { Single; Recursive }
pub(all) struct SortTerm { expr : Ast; descending~ : Bool } derive(Debug)
```

### 5.2 JsonataValue（`value` 包）

```moonbit
pub enum JsonataValue {
  Json(@json.JsonValue)          // 单个 JSON 值
  Sequence(Array[JsonataValue])  // 平坦序列（元素均为 Json）
  Func(JsonataFunc)              // 函数值
  Undefined                      // undefined
} derive(Debug)

pub(struct) JsonataFunc {
  arity : Int
  invoke : (Array[JsonataValue], EvalContext) -> JsonataValue raise JsonataError
}
```

序列语义：序列元素恒为 `Json`（已展平）；单例在需要时提升为 `Sequence`；`Undefined` 参与传播。

### 5.3 JsonataError（`error` 包）

```moonbit
pub(all) suberror JsonataError {
  SyntaxError(message~ : String, position~ : Int?, token~ : String?)
  RuntimeError(message~ : String)
  TypeError(message~ : String, expected~ : String?, actual~ : String?)
  SignatureError(message~ : String, func~ : String?)
  GuardrailError(message~ : String, limit~ : String?)
} derive(Debug, Show)
```

### 5.4 EvalContext（`value` 包）

```moonbit
pub struct EvalContext {
  root : JsonataValue            // $ 根数据
  mut bindings : Map[String, JsonataValue]
  mut depth : Int                // 递归深度（护栏）
  max_depth : Int
  mut steps : Int                // 求值步数（护栏）
  max_steps : Int
}
```

## 6. 处理管线

```
源码 String
   │
   ▼
 Lexer ──► Array[Token]
   │
   ▼
 Parser ──► Ast
   │
   ▼
 Evaluator(+EvalContext, +Functions 注册表) ──► JsonataValue
   │
   ▼
 (to @json.JsonValue)
```

facade `evaluate` 串联以上流程；`compile` 可缓存 Ast 以支持多次求值。

## 7. 设计原则

1. **包边界即类型所有权**：公开类型定义在其所属包，facade 通过 `pub using` 再导出，禁止把公开具体类型放进 `internal/*`。
2. **block 风格**：所有 `.mbt` 顶层定义以 `///|` 分隔，便于按 block 重构。
3. **错误显式传播**：可能失败的函数声明 `raise JsonataError`，调用方自动传播，仅本地处理用 `catch`。
4. **序列扁平化**：求值器统一处理序列展平与单例提升，函数实现无需重复处理。
5. **测试优先**：每个公开 API 配套黑盒测试；稳定结果用 `assert_eq`，结构化调试输出用 `debug_inspect` + `derive(Debug)`。
