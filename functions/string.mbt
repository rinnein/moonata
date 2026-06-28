///|
fn register_string_functions(ctx : @value.EvalContext) -> Unit {
  // $substring(str, start, length?)
  register(ctx, "substring", arity=2, signature=Some("sn"), invoke=fn(
    args,
    _ctx,
  ) {
    let s = value_to_str(args[0])
    let start = value_to_int(args[1])
    let len = s.length()
    let actual_start = if start < 0 { len + start } else { start }
    if actual_start < 0 || actual_start >= len {
      @value.JsonataValue::Json(Json::string(""))
    } else {
      let end = if args.length() > 2 {
        let l = value_to_int(args[2])
        actual_start + l
      } else {
        len
      }
      let actual_end = end.min(len)
      if actual_end <= actual_start {
        @value.JsonataValue::Json(Json::string(""))
      } else {
        let result = s.unsafe_substring(start=actual_start, end=actual_end)
        @value.JsonataValue::Json(Json::string(result))
      }
    }
  })
  // $length
  register(ctx, "length", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::String(s)) =>
        @value.JsonataValue::Json(
          Json::number(s.to_array().length().to_double()),
        )
      @value.JsonataValue::Json(Json::Array(arr)) =>
        @value.JsonataValue::Json(Json::number(arr.length().to_double()))
      @value.JsonataValue::Json(Json::Object(map)) =>
        @value.JsonataValue::Json(Json::number(map.length().to_double()))
      @value.JsonataValue::Sequence(arr) =>
        @value.JsonataValue::Json(Json::number(arr.length().to_double()))
      _ => @value.JsonataValue::Undefined
    }
  })
  // $trim
  register(ctx, "trim", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(
      Json::string(value_to_str(args[0]).trim().to_owned()),
    )
  })
  // $split
  register(ctx, "split", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let sep = value_to_str(args[1])
    let arr : Array[Json] = []
    for p in s.split(sep) {
      arr.push(Json::string(p.to_owned()))
    }
    @value.JsonataValue::Json(Json::array(arr))
  })
  // $concat
  register(ctx, "concat", arity=1, invoke=fn(args, _ctx) {
    let buf = StringBuilder::new()
    match args[0] {
      @value.JsonataValue::Json(Json::Array(arr)) =>
        for v in arr {
          buf.write_string(value_to_json_str(@value.JsonataValue::Json(v)))
        }
      @value.JsonataValue::Sequence(arr) =>
        for v in arr {
          buf.write_string(value_to_json_str(v))
        }
      _ => buf.write_string(value_to_json_str(args[0]))
    }
    @value.JsonataValue::Json(Json::string(buf.to_string()))
  })
  // $uppercase / $lowercase
  register(ctx, "uppercase", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::string(value_to_str(args[0]).to_upper()))
  })
  register(ctx, "lowercase", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::Json(Json::string(value_to_str(args[0]).to_lower()))
  })
  // $contains
  register(ctx, "contains", arity=2, signature=Some("ss"), invoke=fn(
    args,
    _ctx,
  ) {
    let s = value_to_str(args[0])
    let sub = value_to_str(args[1])
    @value.JsonataValue::Json(Json::boolean(s.contains(sub)))
  })
  // $replace(str, pattern, replacement?)
  register(ctx, "replace", arity=3, signature=Some("sss"), invoke=fn(
    args,
    _ctx,
  ) {
    let s = value_to_str(args[0])
    let pattern = value_to_str(args[1])
    let replacement = if args.length() > 2 { value_to_str(args[2]) } else { "" }
    @value.JsonataValue::Json(
      Json::string(s.replace_all(old=pattern, new=replacement)),
    )
  })
  // $substringBefore(str, chars)
  register(ctx, "substringBefore", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let chars = value_to_str(args[1])
    let idx = s.find(chars)
    match idx {
      Some(i) => @value.JsonataValue::Json(Json::string(s[:i].to_owned()))
      None => @value.JsonataValue::Json(Json::string(s))
    }
  })
  // $substringAfter(str, chars)
  register(ctx, "substringAfter", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let chars = value_to_str(args[1])
    let idx = s.find(chars)
    match idx {
      Some(i) =>
        @value.JsonataValue::Json(
          Json::string(s[i + chars.length():].to_owned()),
        )
      None => @value.JsonataValue::Json(Json::string(s))
    }
  })
  // $pad(str, width, char?)
  register(ctx, "pad", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let width = value_to_int(args[1])
    let target = if width < 0 { -width } else { width }
    let len = s.to_array().length()
    if len >= target {
      @value.JsonataValue::Json(Json::string(s))
    } else {
      let pad_chars = if args.length() > 2 {
        let chars = value_to_str(args[2]).to_array()
        if chars.length() == 0 {
          [' ']
        } else {
          chars
        }
      } else {
        [' ']
      }
      let pad_str = make_pad_string(target - len, pad_chars)
      let result = if width < 0 { pad_str + s } else { s + pad_str }
      @value.JsonataValue::Json(Json::string(result))
    }
  })
}

///|
fn make_pad_string(count : Int, chars : Array[Char]) -> String {
  let out = StringBuilder::new()
  for i in 0..<count {
    out.write_char(chars[i % chars.length()])
  }
  out.to_string()
}

///|
fn value_to_str(v : @value.JsonataValue) -> String {
  match v {
    @value.JsonataValue::Json(Json::String(s)) => s
    @value.JsonataValue::Json(Json::Number(n, ..)) => n.to_string()
    @value.JsonataValue::Json(Json::True) => "true"
    @value.JsonataValue::Json(Json::False) => "false"
    @value.JsonataValue::Json(Json::Null) => "null"
    @value.JsonataValue::Undefined => ""
    _ => v.to_json().stringify()
  }
}

///|
fn value_to_int(v : @value.JsonataValue) -> Int {
  match v {
    @value.JsonataValue::Json(Json::Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
fn value_to_json_str(v : @value.JsonataValue) -> String {
  value_to_str(v)
}
