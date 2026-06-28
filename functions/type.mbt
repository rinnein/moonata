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
    let exists = match args[0] {
      @value.JsonataValue::Undefined => false
      _ => true
    }
    @value.JsonataValue::Json(Json::boolean(exists))
  })
  // $not
  register(ctx, "not", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::boolean(!value_to_bool(args[0])))
  })
  // $assert — 断言条件为真，否则抛错
  register(ctx, "assert", arity=1, invoke=fn(args, _ctx) {
    if value_to_bool(args[0]) {
      @value.JsonataValue::Json(Json::boolean(true))
    } else {
      let msg = if args.length() > 1 {
        value_to_str(args[1])
      } else {
        "断言失败"
      }
      raise @error.runtime_error(msg)
    }
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
  // $base64encode
  register(ctx, "base64encode", arity=1, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    @value.JsonataValue::Json(Json::string(base64_encode(s)))
  })
  // $base64decode
  register(ctx, "base64decode", arity=1, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    @value.JsonataValue::Json(Json::string(base64_decode(s)))
  })
  // $error
  register(ctx, "error", arity=1, invoke=fn(args, _ctx) {
    raise @error.runtime_error(value_to_str(args[0]))
  })
}

///|
/// Base64 编码表
let base64_chars : String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
fn base64_encode(s : String) -> String {
  let chars = s.to_array()
  let result = StringBuilder::new()
  let len = chars.length()
  let mut i = 0
  while i + 3 <= len {
    let b0 = chars[i].to_int()
    let b1 = chars[i + 1].to_int()
    let b2 = chars[i + 2].to_int()
    let n = (b0 << 16) | (b1 << 8) | b2
    result.write_char(base64_char_at((n >> 18) & 0x3F))
    result.write_char(base64_char_at((n >> 12) & 0x3F))
    result.write_char(base64_char_at((n >> 6) & 0x3F))
    result.write_char(base64_char_at(n & 0x3F))
    i += 3
  }
  let remaining = len - i
  if remaining == 1 {
    let b0 = chars[i].to_int()
    let n = b0 << 16
    result.write_char(base64_char_at((n >> 18) & 0x3F))
    result.write_char(base64_char_at((n >> 12) & 0x3F))
    result.write_string("==")
  } else if remaining == 2 {
    let b0 = chars[i].to_int()
    let b1 = chars[i + 1].to_int()
    let n = (b0 << 16) | (b1 << 8)
    result.write_char(base64_char_at((n >> 18) & 0x3F))
    result.write_char(base64_char_at((n >> 12) & 0x3F))
    result.write_char(base64_char_at((n >> 6) & 0x3F))
    result.write_string("=")
  }
  result.to_string()
}

///|
fn base64_char_at(idx : Int) -> Char {
  match base64_chars.get_char(idx) {
    Some(c) => c
    None => 'A'
  }
}

///|
fn base64_decode(s : String) -> String {
  let lookup : Map[Char, Int] = {}
  for i, c in base64_chars {
    lookup[c] = i
  }
  let result = StringBuilder::new()
  let chars = s.to_array()
  let mut i = 0
  while i + 4 <= chars.length() {
    let c0 = lookup.get(chars[i]).unwrap_or(0)
    let c1 = lookup.get(chars[i + 1]).unwrap_or(0)
    let c2_val = lookup.get(chars[i + 2])
    let c3_val = lookup.get(chars[i + 3])
    let n = (c0 << 18) | (c1 << 12)
    result.write_char(Char::from_int((n >> 16) & 0xFF))
    match c2_val {
      Some(c2) => {
        let n2 = n | (c2 << 6)
        result.write_char(Char::from_int((n2 >> 8) & 0xFF))
        match c3_val {
          Some(c3) => {
            let n3 = n2 | c3
            result.write_char(Char::from_int(n3 & 0xFF))
          }
          None => ()
        }
      }
      None => ()
    }
    i += 4
  }
  result.to_string()
}
