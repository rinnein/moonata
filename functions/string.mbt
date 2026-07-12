///|
fn register_string_functions(ctx : @value.EvalContext) -> Unit {
  // $substring(str, start, length?)
  // JSONata 签名 <s-nn?:s>：首参字符串，次参整数，第三参可选整数。
  // 使用复杂签名 "s-nn?"：`-` 让 validate_args 处理上下文替换（T0411），
  // `n?` 让第三参可缺省。arity=2（最少提供 start）。
  // 同时在 invoke 内部对手动调用做数量与类型校验，对齐 JSONata-js T0410 行为。
  register(
    ctx,
    "substring",
    arity=2,
    signature=Some("s-nn?"),
    contextual=false,
    invoke=(args, _ctx) => {
      match args[0] {
        @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
        @value.JsonataValue::Json(Json::String(_)) => ()
        _ =>
          raise @error.signature_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
      match args[1] {
        @value.JsonataValue::Json(Json::Number(_, ..)) => ()
        _ =>
          raise @error.signature_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
      // 第三参可选：validate_args 在缺省时会追加 Undefined，需将其视为未提供。
      // 仅在显式提供且非 Undefined 时校验类型。
      let has_length = if args.length() > 2 {
        match args[2] {
          @value.JsonataValue::Undefined => false
          @value.JsonataValue::Json(Json::Number(_, ..)) => true
          _ =>
            raise @error.signature_error(
              "T0410: Arguments are not of expected type",
              code=Some("T0410"),
            )
        }
      } else {
        false
      }
      let s = value_to_str(args[0])
      let start = value_to_int(args[1])
      let chars = s.to_array()
      let len = chars.length()
      let actual_start = if start < 0 { (len + start).max(0) } else { start }
      if actual_start >= len {
        @value.JsonataValue::Json(Json::string(""))
      } else {
        let end = if has_length {
          let l = value_to_int(args[2])
          actual_start + l
        } else {
          len
        }
        let actual_end = end.min(len)
        if actual_end <= actual_start {
          @value.JsonataValue::Json(Json::string(""))
        } else {
          let result = chars_to_string(chars, actual_start, actual_end)
          @value.JsonataValue::Json(Json::string(result))
        }
      }
    },
  )
  // $length（非上下文感知，直接绑定）
  ctx.bind(
    "length",
    @value.JsonataValue::Func(
      @value.JsonataFunc::new(arity=1, contextual=false, invoke=(args, _ctx) => {
        if args.length() < 1 {
          raise @error.runtime_error("T0411: Incorrect number of arguments")
        }
        if args.length() > 1 {
          raise @error.runtime_error(
            "T0410: Arguments are not of expected type",
          )
        }
        match args[0] {
          @value.JsonataValue::Json(Json::String(s)) =>
            @value.JsonataValue::Json(
              Json::number(unicode_char_count(s).to_double()),
            )
          @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
          _ =>
            raise @error.runtime_error(
              "T0410: Arguments are not of expected type",
            )
        }
      }),
    ),
  )
  // $trim
  register(ctx, "trim", arity=1, invoke=fn(args, _ctx) {
    if args[0].is_undefined() ||
      args[0] is @value.JsonataValue::Json(Json::Null) {
      return @value.JsonataValue::Undefined
    }
    @value.JsonataValue::Json(
      Json::string(normalize_whitespace(value_to_str(args[0]))),
    )
  })
  // $split（实际实现在 regex.mbt 中注册，此处仅占位）
  // register(ctx, "split", arity=2, invoke=(args, _ctx) => { ... })
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
  // JSONata 签名 <s-:s>：首参为字符串，`-` 表示缺省时使用上下文。
  // 此处使用复杂签名 "s-" 并关闭 apply_context_argument 的前置上下文行为，
  // 让 validate_args 通过 `-` 修饰符正确处理上下文替换与 T0411 语义。
  // 同时在 invoke 内部对手动调用（chain 调用等绕过 validate_args 的路径）
  // 做参数数量与类型校验，对齐 JSONata-js T0410 行为。
  register(ctx, "uppercase", arity=1, signature=Some("s-"), contextual=false, invoke=(
    args,
    _ctx,
  ) => {
    match args[0] {
      @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
      @value.JsonataValue::Json(Json::String(_)) => ()
      _ =>
        raise @error.signature_error(
          "T0410: Arguments are not of expected type",
          code=Some("T0410"),
        )
    }
    @value.JsonataValue::Json(Json::string(value_to_str(args[0]).to_upper()))
  })
  register(ctx, "lowercase", arity=1, signature=Some("s-"), contextual=false, invoke=(
    args,
    _ctx,
  ) => {
    match args[0] {
      @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
      @value.JsonataValue::Json(Json::String(_)) => ()
      _ =>
        raise @error.signature_error(
          "T0410: Arguments are not of expected type",
          code=Some("T0410"),
        )
    }
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
  // $replace(str, pattern, replacement) — 字面量替换版本。
  // 注意：regex.mbt 会随后注册同名 $replace（支持正则 pattern），覆盖此处注册。
  // 保留此处字面量版本作为内部参考与回退路径。
  register(ctx, "replace_literal", arity=3, signature=Some("sss"), invoke=(
    args,
    _ctx,
  ) => {
    match args[0] {
      @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
      _ => ()
    }
    let s = value_to_str(args[0])
    let pattern = value_to_str(args[1])
    let replacement = if args.length() > 2 { value_to_str(args[2]) } else { "" }
    @value.JsonataValue::Json(
      Json::string(s.replace_all(old=pattern, new=replacement)),
    )
  })
  // $substringBefore(str, chars)
  // JSONata 签名 <s-s:s>：首参 `s-` 缺省时使用上下文，第二参 `s` 必需。
  // 使用复杂签名 "s-s" + contextual=false，让 validate_args 处理上下文替换，
  // 在上下文类型不匹配时抛 T0411（对齐 JSONata-js）。
  // invoke 内部仅校验参数类型（数量校验交给 validate_args；
  // $each 等回调路径会传入额外参数，需宽松处理）。
  register(
    ctx,
    "substringBefore",
    arity=2,
    signature=Some("s-s"),
    contextual=false,
    invoke=(args, _ctx) => {
      match args[0] {
        @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
        @value.JsonataValue::Json(Json::String(_)) => ()
        _ =>
          raise @error.signature_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
      match args[1] {
        @value.JsonataValue::Json(Json::String(_)) => ()
        _ =>
          raise @error.signature_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
      let s = value_to_str(args[0])
      let chars = value_to_str(args[1])
      let idx = s.find(chars)
      match idx {
        Some(i) => @value.JsonataValue::Json(Json::string(s[:i].to_owned()))
        None => @value.JsonataValue::Json(Json::string(s))
      }
    },
  )
  // $substringAfter(str, chars)
  // JSONata 签名 <s-s:s>：同 $substringBefore。
  register(
    ctx,
    "substringAfter",
    arity=2,
    signature=Some("s-s"),
    contextual=false,
    invoke=(args, _ctx) => {
      match args[0] {
        @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
        @value.JsonataValue::Json(Json::String(_)) => ()
        _ =>
          raise @error.signature_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
      match args[1] {
        @value.JsonataValue::Json(Json::String(_)) => ()
        _ =>
          raise @error.signature_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
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
    },
  )
  // $pad(str, width, char?)
  register(ctx, "pad", arity=2, invoke=fn(args, _ctx) {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
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
fn normalize_whitespace(s : String) -> String {
  let out = StringBuilder::new()
  let mut in_space = false
  let mut wrote = false
  for c in s.trim() {
    if c.is_whitespace() {
      if wrote && !in_space {
        out.write_char(' ')
        in_space = true
      }
    } else {
      out.write_char(c)
      wrote = true
      in_space = false
    }
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

///|
/// 统计字符串的 Unicode 码点数量（正确处理代理对）。
fn unicode_char_count(s : String) -> Int {
  let chars = s.to_array()
  let mut count = 0
  let mut i = 0
  while i < chars.length() {
    let c = chars[i].to_int()
    // 高代理项（U+D800-U+DBFF）与低代理项（U+DC00-U+DFFF）构成一个码点
    if c >= 0xD800 && c <= 0xDBFF && i + 1 < chars.length() {
      let next = chars[i + 1].to_int()
      if next >= 0xDC00 && next <= 0xDFFF {
        i += 2
        count += 1
        continue
      }
    }
    i += 1
    count += 1
  }
  count
}
