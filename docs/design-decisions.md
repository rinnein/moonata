# Moonata 设计决策

> 关键设计决策、代码骨架与风险分析。实现时遇到取舍，以本文档为准。

## 1. AST 表示：单一 enum + 标签字段

**决策**：所有 AST 节点统一为 `Ast` enum，子结构（`Step`/`SortTerm`）独立定义。

**理由**：
- MoonBit `enum` + 模式匹配天然适合 AST，避免多态类层次的开销。
- 标签字段（`op~`、`lhs~`）让构造与匹配可读且无歧义。
- `derive(Debug)` 即可用于 `debug_inspect` 快照测试。

**反例**：用 `struct` + trait 对象表示节点——MoonBit 无运行时多态类，且模式匹配更繁琐。

## 2. 运行时值：四态 enum

**决策**：`JsonataValue` = `Json` | `Sequence` | `Func` | `Undefined`。

**理由**：
- `Json` 直接包装 `@json.JsonValue`，零成本与外部互操作。
- `Sequence` 显式表示平坦序列，元素恒为 `Json`（已展平），避免无限嵌套。
- `Func` 持有闭包，使 Lambda 与内建函数统一为一等公民。
- `Undefined` 是 JSONata 语义一等值，参与传播，不能等同于 `null`。

**序列语义规则**：
1. 序列元素若本身是序列，递归展平。
2. 长度为 1 的序列在标量上下文提升为单例。
3. `Undefined` 参与运算时按 JSONata 规则传播（多数运算结果为 `Undefined`）。

## 3. 错误层级：单一 suberror + 变体

**决策**：定义 `JsonataError` 单一 suberror，含 5 个变体（`SyntaxError`/`RuntimeError`/`TypeError`/`SignatureError`/`GuardrailError`）。

**理由**：
- 调用方用一次 `raise JsonataError` 即可传播所有错误，简化签名。
- 需要精细处理时用模式匹配区分变体。
- 每个变体携带结构化字段（`position`/`token`/`expected`/`actual`），便于定位。

## 4. 上下文与护栏

**决策**：`EvalContext` 持有根数据、绑定表与两个可变计数器（`depth`/`steps`）。

**护栏**：
- `max_depth`（默认 1000）：递归深度超限抛 `GuardrailError`。
- `max_steps`（默认 1_000_000）：求值步数超限抛 `GuardrailError`。

**理由**：JSONata 是图灵完备的（Lambda + 递归），需防止恶意/无限输入。

## 5. 函数注册表：Map + 闭包

**决策**：内建函数注册为 `Map[String, JsonataFunc]`，每个 `JsonataFunc` 持有闭包。

**骨架**：
```moonbit
// functions 包
pub fn register_builtins(ctx : EvalContext) -> Unit {
  ctx.bindings["$sum"] = Func(JsonataFunc::new(
    arity=1,
    invoke=fn(args, _ctx) {
      match args[0] {
        Sequence(arr) => Json(JsonValue::number(arr.fold(0.0, ...)))
        Json(JsonValue::Array(arr)) => ...
        Undefined => Json(JsonValue::number(0.0))
        _ => raise JsonataError::TypeError(...)
      }
    }
  ))
  // ... 其余 60+ 函数
}
```

**理由**：闭包统一内建函数与用户 Lambda 的调用方式；签名检查在 `invoke` 内完成。

## 6. facade API

```moonbit
// moonata 包
pub fn evaluate(
  expr : String,
  data : @json.JsonValue,
) -> @json.JsonValue raise JsonataError {
  let ast = @parser.parse(@lexer.lex(expr))?
  let ctx = @value.EvalContext::new(Json(@data))
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

pub fn compile(expr : String) -> Compiled raise JsonataError {
  let ast = @parser.parse(@lexer.lex(expr))?
  Compiled(ast)
}

pub struct Compiled { ast : @ast.Ast }

pub fn Compiled::run(self : Compiled, data : @json.JsonValue) -> @json.JsonValue raise JsonataError {
  ...
}
```

## 7. 包依赖原则

- `error` 是最底层，不依赖任何内部包。
- `ast` 与 `value` 都只依赖 `error`，二者**互不依赖**（AST 是纯数据，值是运行时表示）。
- `parser` 依赖 `ast`/`lexer`/`error`，不依赖 `value`/`evaluator`。
- `evaluator` 依赖 `ast`/`value`/`error`。
- `functions` 依赖 `value`/`error`（注册到上下文），可选依赖 `evaluator`（若需 `$eval`）。
- `moonata` facade 依赖所有上层包，通过 `pub using` 再导出公开 API。

**禁止**：任何反向依赖或循环依赖。

## 8. 测试策略

| 测试类型 | 文件 | 工具 | 用途 |
| --- | --- | --- | --- |
| 黑盒 | `*_test.mbt` | `@moonata.fn` | 公开 API 行为 |
| 白盒 | `*_wbtest.mbt` | 直接调用 | 内部辅助函数 |
| 快照 | `*_test.mbt` | `debug_inspect` + `moon test --update` | AST 结构、调试输出 |
| 断言 | `*_test.mbt` | `assert_eq` | 稳定数值/字符串结果 |
| 错误 | `*_test.mbt` | `try ... catch ... noraise` | 期望失败 |

**原则**：
- 稳定结果优先 `assert_eq`；结构化输出用 `debug_inspect` + `derive(Debug)`。
- 不为调试派生 `Show`，除非需要专门展示格式。
- 每个公开函数至少一个正向 + 一个边界用例。

## 9. 风险登记

| 编号 | 风险 | 概率 | 影响 | 缓解 | 状态 |
| --- | --- | --- | --- | --- | --- |
| R1 | MoonBit 标准库无正则 | 高 | 中 | ~~P6 评估第三方库~~ **已引入 `moonbitlang/regexp@0.3.5`**（`compile` + `Regexp::execute` + `MatchResult`），P9.4 实现 `$match`/`$contains`/`$split`/`$replace` | ✅ 已解决 |
| R2 | 序列展平语义复杂 | 中 | 高 | P1 集中实现并单测覆盖 | ✅ 已实现 |
| R3 | 递归/Lambda 导致无限循环 | 中 | 高 | `EvalContext` 护栏（depth/steps） | ✅ 已实现 |
| R4 | 官方测试套件庞大 | 高 | 中 | P9.5 选取核心分类用例，滚动补齐 | ⏳ 待执行 |
| R5 | `@json.JsonValue` 与 JSONata 数值精度差异 | 低 | 低 | 统一用 `Double`，文档标注 | ✅ 已实现 |

## 10. 可行性结论

- **技术可行性**：高。MoonBit 的 enum/suberror/闭包/`@json` 几乎 1:1 对应 JSONata 需求。
- **正则支持**：~~主要不确定项，需在 P6 验证~~ **已解决**，通过 `moonbitlang/regexp@0.3.5` 提供 `compile`/`execute`/`MatchResult`，P9.4 实现正则函数。
- **工程可行性**：8 包结构清晰，依赖无环，分阶段可独立验证。P1–P8 已完成，P9 为语义修复与函数补全。
- **预估工作量**：P1–P8 共 47 人日（17 节点）已完成；P9 新增 12 人日（5 节点），总计 59 人日 / 22 节点。
