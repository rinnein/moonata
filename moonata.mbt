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
/// 编译 JSONata 表达式为可重复求值的 Compiled。
pub fn compile(expr : String) -> Compiled raise @error.JsonataError {
  let tokens = @lexer.lex(expr)
  let ast = @parser.parse(tokens)
  { ast, }
}

///|
/// 已编译的 JSONata 表达式。
pub(all) struct Compiled {
  ast : @ast.Ast
}

///|
/// 对已编译表达式求值。
pub fn Compiled::run(
  self : Compiled,
  data : Json,
) -> Json raise @error.JsonataError {
  let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
  @functions.register_builtins(ctx)
  let result = @evaluator.eval(self.ast, ctx)
  result.to_json()
}

///|
/// 再导出关键类型
pub using @error {type JsonataError}

///|
pub using @ast {type Ast}
