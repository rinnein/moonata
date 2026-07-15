///|
/// JSONata 表达式求值。
///
/// 解析并求值 JSONata 表达式，返回 JSON 结果。
pub fn evaluate(expr : String, data : Json) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// JSONata 表达式求值（指定 max_depth）。
///
/// 用于官方审计脚本传递 case 文件中的 `depth` 字段，对齐 jsonata-js test runner
/// 的 `timeboxExpression` 语义。`tail-recursion/case002` 期望 maxDepth=302 触发 U1001。
pub fn evaluate_with_max_depth(
  expr : String,
  data : Json,
  max_depth : Int,
) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = @value.EvalContext::new_with_limits(
    @value.JsonataValue::Json(data),
    max_depth~,
  )
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// JSONata 表达式求值（undefined 上下文）。
///
/// 与 `evaluate` 相同，但使用 `Undefined` 作为根上下文，
/// 对齐 jsonata-js test runner 中 `dataset: null` → `undefined` 的语义。
pub fn evaluate_undefined(expr : String) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = @value.EvalContext::new(@value.JsonataValue::Undefined)
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// JSONata 表达式求值（undefined 上下文，指定 max_depth）。
pub fn evaluate_undefined_with_max_depth(
  expr : String,
  max_depth : Int,
) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = @value.EvalContext::new_with_limits(
    @value.JsonataValue::Undefined,
    max_depth~,
  )
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// JSONata 表达式求值（应用 guardrails 选项）。
///
/// 对齐 JSONata `embedding-extending` 文档 `jsonata(str, options)` 与
/// `guardrails` 文档：`options` 携带 `stack` / `timeout` / `sequence` 护栏，
/// 分别限制递归深度（D1011）、求值步数（D1012，由 timeout 毫秒映射为步数上限）、
/// 序列长度（D2015）。
///
/// - `stack`：>0 时启用，超限抛 `D1011`；未设置（None）时使用默认 `max_depth=8000` 与 `U1001` 语义。
/// - `timeout`：>0 时启用，超限抛 `D1012`；当前 MoonBit 无原生 wall-clock 超时支持，
///   使用 `timeout_ms * 1000` 作为 `max_steps` 近似上限（每步约 1μs 量级）。
/// - `sequence`：>0 时启用，超限抛 `D2015`。
pub fn evaluate_with_options(
  expr : String,
  data : Json,
  options : EvalOptions,
) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = options.build_context(@value.JsonataValue::Json(data))
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// JSONata 表达式求值（undefined 上下文 + guardrails 选项）。
pub fn evaluate_undefined_with_options(
  expr : String,
  options : EvalOptions,
) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = options.build_context(@value.JsonataValue::Undefined)
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// JSONata 表达式求值（应用变量绑定）。
///
/// 对齐 JSONata `embedding-extending` 文档 `expression.evaluate(input, bindings)`：
/// `bindings` 中的变量名（含函数）在求值期间绑定到上下文，覆盖同名内建函数。
/// 值为 `Json` 类型，函数值以 `Json::null` 占位（如需注册函数用 `Compiled::register_function`）。
pub fn evaluate_with_bindings(
  expr : String,
  data : Json,
  bindings : Map[String, Json],
) -> Json raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
  @functions.register_builtins(ctx)
  for name, value in bindings {
    ctx.bind(name, @value.JsonataValue::Json(value))
  }
  let result = @evaluator.eval(ast, ctx)
  result.to_json()
}

///|
/// 编译 JSONata 表达式为可重复求值的 Compiled。
pub fn compile(expr : String) -> Compiled raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  { ast, assigned_bindings: Map([]) }
}

///|
/// 已编译的 JSONata 表达式。
///
/// 对齐 JSONata `embedding-extending` 文档中编译表达式对象：
/// - `run(data)` 对应 `expression.evaluate(input)`
/// - `run_with_options(data, options)` 对应 `jsonata(str, options).evaluate(input)`
/// - `assign(name, value)` 对应 `expression.assign(name, value)`
/// - `register_function(name, impl, signature)` 对应 `expression.registerFunction(name, impl, signature)`
pub(all) struct Compiled {
  ast : @ast.Ast
  mut assigned_bindings : Map[String, @value.JsonataValue]
}

///|
/// 对已编译表达式求值。
pub fn Compiled::run(
  self : Compiled,
  data : Json,
) -> Json raise @error.JsonataError {
  self.run_with_options(data, EvalOptions::default())
}

///|
/// 对已编译表达式求值（应用 guardrails 选项）。
pub fn Compiled::run_with_options(
  self : Compiled,
  data : Json,
  options : EvalOptions,
) -> Json raise @error.JsonataError {
  let ctx = options.build_context(@value.JsonataValue::Json(data))
  @functions.register_builtins(ctx)
  for name, value in self.assigned_bindings {
    ctx.bind(name, value)
  }
  let result = @evaluator.eval(self.ast, ctx)
  result.to_json()
}

///|
/// 对已编译表达式求值（应用变量绑定）。
pub fn Compiled::run_with_bindings(
  self : Compiled,
  data : Json,
  bindings : Map[String, Json],
) -> Json raise @error.JsonataError {
  let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
  @functions.register_builtins(ctx)
  for name, value in self.assigned_bindings {
    ctx.bind(name, value)
  }
  for name, value in bindings {
    ctx.bind(name, @value.JsonataValue::Json(value))
  }
  let result = @evaluator.eval(self.ast, ctx)
  result.to_json()
}

///|
/// 永久绑定一个值到表达式（对齐 `expression.assign(name, value)`）。
///
/// 后续 `run` / `run_with_options` / `run_with_bindings` 调用都会携带此绑定，
/// 直至再次 `assign` 同名变量覆盖。`run_with_bindings` 传入的同名绑定会临时覆盖
/// （仅在本次调用内），对齐 JSONata 文档 "the `bindings` argument in the
/// `expression.evaluate()` call clobbers these values"。
pub fn Compiled::assign(self : Compiled, name : String, value : Json) -> Unit {
  self.assigned_bindings[name] = @value.JsonataValue::Json(value)
}

///|
/// 永久绑定一个函数到表达式（对齐 `expression.registerFunction(name, impl, signature)`）。
///
/// 与 `assign` 不同，`register_function` 接收一个 MoonBit 闭包作为函数实现，
/// 并可选指定 JSONata 签名字符串（如 `<nn:n>`）用于运行时参数类型校验。
/// 签名语法参见 `docs/jsonata-official-workflow.md` 与 JSONata 官方文档
/// `embedding-extending` 章节。
///
/// 闭包接收 `Array[Json]`（已转换自 `JsonataValue`，便于宿主侧处理）和 `EvalContext`
/// （仅在使用 `@`/`$$` 等上下文访问器时需要），返回 `Json` 结果。Moonata 内部会将
/// 返回的 `Json` 包装为 `JsonataValue::Json`。
pub fn Compiled::register_function(
  self : Compiled,
  name : String,
  arity~ : Int,
  signature~ : String?,
  invoke~ : (Array[Json], @value.EvalContext) -> Json raise @error.JsonataError,
) -> Unit {
  let invoke_inner = fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let json_args : Array[Json] = args.map(fn(v) { v.to_json() })
    let result = invoke(json_args, ctx)
    @value.JsonataValue::Json(result)
  }
  self.assigned_bindings[name] = @value.JsonataValue::Func(
    @value.JsonataFunc::new(
      arity~,
      signature~,
      contextual=false,
      invoke=invoke_inner,
    ),
  )
}

///|
/// Guardrails 选项（对齐 JSONata `guardrails` 文档）。
///
/// - `stack`：最大递归深度，超限抛 `D1011`。`None` 时使用默认 `max_depth=8000` + `U1001` 语义。
/// - `timeout`：最大执行时间（毫秒），超限抛 `D1012`。`None` 时不启用超时护栏。
///   MoonBit 当前无原生 wall-clock 超时支持，使用 `timeout_ms * 1000` 作为 `max_steps` 上限近似。
/// - `sequence`：最大序列长度，超限抛 `D2015`。`None` 或 `<= 0` 时不限制。
/// - `max_steps`：直接指定最大步数（扩展选项，超限抛 `D1012`）。优先于 `timeout` 换算值。
pub struct EvalOptions {
  stack : Int?
  timeout : Int?
  sequence : Int?
  max_steps : Int?
} derive(Eq)

///|
/// 默认 guardrails 选项（不启用任何护栏，沿用 legacy `U1001` 语义）。
pub fn EvalOptions::default() -> EvalOptions {
  { stack: None, timeout: None, sequence: None, max_steps: None }
}

///|
/// 构造 guardrails 选项。
pub fn EvalOptions::new(
  stack? : Int? = None,
  timeout? : Int? = None,
  sequence? : Int? = None,
  max_steps? : Int? = None,
) -> EvalOptions {
  { stack, timeout, sequence, max_steps }
}

///|
/// 根据选项构造 EvalContext，应用对应的护栏阈值与错误码。
///
/// - `stack` 为 `Some(n)` 且 `n > 0` 时：`max_depth = n`，`depth_exceeded_code = "D1011"`
/// - `timeout` 为 `Some(ms)` 且 `ms > 0` 时：`max_steps = ms * 1000`，`steps_exceeded_code = "D1012"`
/// - `max_steps` 为 `Some(n)` 且 `n > 0` 时：覆盖 `timeout` 换算值
/// - `sequence` 为 `Some(n)` 且 `n > 0` 时：`max_sequence = n`，`sequence_exceeded_code = "D2015"`
/// - 其余情况使用默认值，错误码保持 `U1001`（向后兼容 jsonata-js test runner）
pub fn EvalOptions::build_context(
  self : EvalOptions,
  root : @value.JsonataValue,
) -> @value.EvalContext {
  let max_depth = match self.stack {
    Some(n) if n > 0 => n
    _ => @value.default_max_depth
  }
  let depth_code = match self.stack {
    Some(n) if n > 0 => "D1011"
    _ => "U1001"
  }
  let max_steps_from_timeout = match self.timeout {
    Some(ms) if ms > 0 => ms * 1000
    _ => @value.default_max_steps
  }
  let max_steps = match self.max_steps {
    Some(n) if n > 0 => n
    _ => max_steps_from_timeout
  }
  let steps_code = match self.timeout {
    Some(_) => "D1012"
    _ =>
      match self.max_steps {
        Some(_) => "D1012"
        _ => "U1001"
      }
  }
  let max_sequence = match self.sequence {
    Some(n) if n > 0 => n
    _ => @value.default_max_sequence
  }
  // sequence_code 始终为 D2015（JSONata 文档默认）
  @value.EvalContext::new_with_guardrails(
    root,
    max_depth~,
    max_steps~,
    max_sequence~,
    depth_exceeded_code=depth_code,
    steps_exceeded_code=steps_code,
    sequence_exceeded_code="D2015",
  )
}

///|
/// 再导出关键类型
pub using @error {type JsonataError}

///|
pub using @ast {type Ast}

///|
pub using @value {type EvalContext}
