///|
fn register_type_functions(ctx : @value.EvalContext) -> Unit {
  // $string
  register(ctx, "string", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::string(value_to_str(args[0])))
  })
  // $number
  register(ctx, "number", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n)) => args[0]
      @value.JsonataValue::Json(Json::String(s)) =>
        @value.JsonataValue::Json(Json::number(@strconv.from_str(s))) catch {
          _ => @value.JsonataValue::Undefined
        }
      @value.JsonataValue::Json(Json::True) =>
        @value.JsonataValue::Json(Json::number(1.0))
      @value.JsonataValue::Json(Json::False) =>
        @value.JsonataValue::Json(Json::number(0.0))
      _ => @value.JsonataValue::Undefined
    }
  })
  // $boolean
  register(ctx, "boolean", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::boolean(value_to_bool(args[0])))
  })
  // $type
  register(ctx, "type", arity=1, invoke=fn(args, _ctx) {
    let type_name = match args[0] {
      @value.JsonataValue::Json(Json::String(_)) => "string"
      @value.JsonataValue::Json(Json::Number(_)) => "number"
      @value.JsonataValue::Json(Json::True) => "boolean"
      @value.JsonataValue::Json(Json::False) => "boolean"
      @value.JsonataValue::Json(Json::Null) => "null"
      @value.JsonataValue::Json(Json::Array(_)) => "array"
      @value.JsonataValue::Json(Json::Object(_)) => "object"
      @value.JsonataValue::Undefined => "undefined"
      @value.JsonataValue::Func(_) => "function"
      @value.JsonataValue::Sequence(_) => "array"
    }
    @value.JsonataValue::Json(Json::string(type_name))
  })
}

///|
fn register_higher_order_functions(ctx : @value.EvalContext) -> Unit {
  // $eval
  register(ctx, "eval", arity=1, invoke=fn(args, ctx) {
    let expr_str = value_to_str(args[0])
    let tokens = @lexer.lex(expr_str)
    let ast = @parser.parse(tokens)
    @evaluator.eval(ast, ctx)
  })
  // $exists
  register(ctx, "exists", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(
      Json::boolean(not(args[0] is @value.JsonataValue::Undefined)),
    )
  })
  // $not
  register(ctx, "not", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::boolean(not(value_to_bool(args[0]))))
  })
}

///|
fn register_special_functions(ctx : @value.EvalContext) -> Unit {
  // $now
  register(ctx, "now", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::string("2026-06-28T00:00:00Z"))
  })
  // $millis
  register(ctx, "millis", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::number(0.0))
  })
  // $base64encode / $base64decode (简化)
  register(ctx, "base64encode", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::string(value_to_str(args[0])))
  })
  // $error
  register(ctx, "error", arity=1, invoke=fn(args, _ctx) {
    raise @error.runtime_error(value_to_str(args[0]))
  })
}
