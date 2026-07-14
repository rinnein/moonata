///|
fn register_type_functions(ctx : @value.EvalContext) -> Unit {
  // $string
  // 对齐 jsonata-js `<x-b?:s>`：0 参时使用上下文作为首参；
  // 1 参正常转换；2 参 pretty；3 参（HOF 回调 (item, index, source)）忽略 index/source。
  register(ctx, "string", arity=0, invoke=(args, ctx) => {
    let value = if args.length() == 0 { ctx.current() } else { args[0] }
    // HOF 回调 (item, index, source) 允许 3 个参数；超过 3 个抛 T0410
    if args.length() > 3 {
      raise @error.runtime_error(
        "T0410: Arguments are not of expected type",
        code=Some("T0410"),
      )
    }
    // 第二参数（若提供）必须是布尔值
    // args.length()==3 时是 HOF 回调的 index 参数，跳过布尔校验
    if args.length() == 2 {
      match args[1] {
        @value.JsonataValue::Json(Json::True) => ()
        @value.JsonataValue::Json(Json::False) => ()
        @value.JsonataValue::Undefined => ()
        _ =>
          raise @error.runtime_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
    }
    if value.is_undefined() {
      return @value.JsonataValue::Undefined
    }
    // args.length()==3 时不使用 args[1] 作为 pretty（HOF 注入的 index）
    let pretty = args.length() == 2 && value_to_bool(args[1])
    @value.JsonataValue::Json(Json::string(jsonata_string(value, pretty)))
  })
  // $number
  register(ctx, "number", arity=1, signature=Some("j"), invoke=(args, _ctx) => {
    if args.length() > 1 {
      raise @error.runtime_error("T0410: Wrong number of arguments")
    }
    match args[0] {
      @value.JsonataValue::Json(Json::Number(_, ..)) => args[0]
      @value.JsonataValue::Json(Json::String(s)) =>
        match parse_number_literal(s) {
          Some(n) => @value.JsonataValue::Json(Json::number(n))
          None =>
            raise @error.runtime_error(
              "D3030: Unable to cast value to a number",
            )
        }
      @value.JsonataValue::Json(Json::True) =>
        @value.JsonataValue::Json(Json::number(1.0))
      @value.JsonataValue::Json(Json::False) =>
        @value.JsonataValue::Json(Json::number(0.0))
      @value.JsonataValue::Json(Json::Null) =>
        raise @error.runtime_error(
          "T0410: It is not possible to cast a null value to a number",
        )
      @value.JsonataValue::Json(Json::Array(_)) =>
        raise @error.runtime_error(
          "T0410: It is not possible to cast an array to a number",
        )
      @value.JsonataValue::Json(Json::Object(_)) =>
        raise @error.runtime_error(
          "T0410: It is not possible to cast an object to a number",
        )
      @value.JsonataValue::Func(_) =>
        raise @error.runtime_error(
          "T0410: It is not possible to cast a function to a number",
        )
      _ => @value.JsonataValue::Undefined
    }
  })
  // $boolean allows the three-argument HOF callback convention, but rejects
  // the ordinary two-argument invocation.
  register(ctx, "boolean", arity=1, invoke=(args, _ctx) => {
    if args.length() == 2 {
      raise @error.runtime_error(
        "T0410: Arguments are not of expected type",
        code=Some("T0410"),
      )
    }
    match args[0] {
      @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
      _ => @value.JsonataValue::Json(Json::boolean(value_to_bool(args[0])))
    }
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
      @value.JsonataValue::Object(_) => "object"
      @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
      @value.JsonataValue::Func(_) => "function"
      @value.JsonataValue::Regex(_) => "function"
      @value.JsonataValue::Sequence(_) => "array"
    }
    @value.JsonataValue::Json(Json::string(type_name))
  })
}

///|
fn jsonata_string(
  value : @value.JsonataValue,
  pretty : Bool,
) -> String raise @error.JsonataError {
  match value {
    @value.JsonataValue::Json(Json::String(s)) => s
    @value.JsonataValue::Json(Json::Number(n, ..)) =>
      // D3001: 直接对 Infinity/NaN 调用 $string
      if n.is_nan() || n.is_inf() {
        raise @error.runtime_error(
          "D3001: Attempting to invoke string function on Infinity or NaN",
          code=Some("D3001"),
        )
      } else {
        jsonata_string_number(n)
      }
    @value.JsonataValue::Json(Json::True) => "true"
    @value.JsonataValue::Json(Json::False) => "false"
    @value.JsonataValue::Json(Json::Null) => "null"
    @value.JsonataValue::Undefined => ""
    @value.JsonataValue::Func(_) => ""
    @value.JsonataValue::Regex(_) => ""
    _ => {
      // D1001: 对象/数组中嵌套的 Infinity/NaN 抛 D1001
      check_no_infinity(value)
      let json = jsonata_string_json(value)
      if pretty {
        json.stringify(indent=2)
      } else {
        json.stringify()
      }
    }
  }
}

///|
/// 递归检查值中是否包含 Infinity/NaN，若包含则抛 D1001。
fn check_no_infinity(
  value : @value.JsonataValue,
) -> Unit raise @error.JsonataError {
  match value {
    @value.JsonataValue::Json(Json::Number(n, ..)) =>
      if n.is_nan() || n.is_inf() {
        raise @error.runtime_error(
          "D1001: Number out of range: \{n}",
          code=Some("D1001"),
        )
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for item in arr {
        check_no_infinity(@value.JsonataValue::Json(item))
      }
    @value.JsonataValue::Json(Json::Object(map)) =>
      for _, item in map {
        check_no_infinity(@value.JsonataValue::Json(item))
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        check_no_infinity(item)
      }
    _ => ()
  }
}

///|
fn jsonata_string_json(value : @value.JsonataValue) -> Json {
  match value {
    @value.JsonataValue::Func(_) => Json::string("")
    @value.JsonataValue::Regex(_) => Json::string("")
    @value.JsonataValue::Undefined => Json::null()
    @value.JsonataValue::Sequence(arr) => {
      let out : Array[Json] = []
      for item in arr {
        out.push(jsonata_string_json(item))
      }
      Json::array(out)
    }
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let out : Array[Json] = []
      for item in arr {
        out.push(jsonata_string_json(@value.JsonataValue::Json(item)))
      }
      Json::array(out)
    }
    @value.JsonataValue::Json(Json::Object(map)) => {
      let out : Map[String, Json] = Map([])
      for entry in map {
        let (key, item) = entry
        out[key] = jsonata_string_json(@value.JsonataValue::Json(item))
      }
      Json::object(out)
    }
    @value.JsonataValue::Object(map) => {
      let out : Map[String, Json] = Map([])
      for entry in map {
        let (key, item) = entry
        out[key] = jsonata_string_json(item)
      }
      Json::object(out)
    }
    @value.JsonataValue::Json(json) => json
  }
}

///|
fn jsonata_string_number(n : Double) -> String {
  if n == 0.0 {
    return "0"
  }
  let negative = n < 0.0
  let abs_n = if negative { -n } else { n }
  if abs_n >= 1.0e21 || abs_n < 1.0e-6 {
    return n.to_string()
  }
  let digits_before = decimal_integer_digit_count(abs_n)
  let decimals = (15 - digits_before).max(0)
  let rounded_abs = round_to_decimal_places(abs_n, decimals)
  let body = fixed_decimal_string(rounded_abs, decimals)
  if negative {
    "-" + body
  } else {
    body
  }
}

///|
fn decimal_integer_digit_count(n : Double) -> Int {
  let mut digits = 1
  let mut value = n
  while value >= 10.0 {
    value = value / 10.0
    digits = digits + 1
  }
  digits
}

///|
fn round_to_decimal_places(n : Double, places : Int) -> Double {
  if places <= 0 {
    n.round()
  } else {
    let scale = @math.pow(10.0, places.to_double())
    (n * scale).round() / scale
  }
}

///|
fn fixed_decimal_string(n : Double, places : Int) -> String {
  if places <= 0 {
    return integer_digits(n)
  }
  let int_part = n.floor()
  let scale = @math.pow(10.0, places.to_double())
  let mut frac_number = ((n - int_part) * scale).round().to_int64()
  let mut int_text = integer_digits(int_part)
  let scale_int = scale.round().to_int64()
  if frac_number >= scale_int {
    int_text = integer_digits(int_part + 1.0)
    frac_number = 0
  }
  let frac = trim_trailing_zeroes(
    left_pad_number(frac_number.to_string(), places),
  )
  if frac.length() == 0 {
    int_text
  } else {
    int_text + "." + frac
  }
}

///|
fn left_pad_number(s : String, width : Int) -> String {
  let out = StringBuilder::new()
  for _ in 0..<(width - s.length()).max(0) {
    out.write_char('0')
  }
  out.write_string(s)
  out.to_string()
}

///|
fn trim_trailing_zeroes(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] == '0' {
    end = end - 1
  }
  s[:end].to_owned()
}

///|
fn parse_number_literal(s : String) -> Double? {
  if s.length() > 2 && s[0] == '0' {
    let radix = match s[1] {
      'x' | 'X' => 16
      'b' | 'B' => 2
      'o' | 'O' => 8
      _ => 0
    }
    if radix != 0 {
      return parse_radix_number(s, radix, 2)
    }
  }
  Some(@strconv.from_str(s)) catch {
    _ => None
  }
}

///|
fn parse_radix_number(s : String, radix : Int, start : Int) -> Double? {
  let mut value = 0
  let mut i = start
  if i >= s.length() {
    return None
  }
  while i < s.length() {
    let digit = match s.get_char(i) {
      Some(c) => radix_digit(c)
      None => return None
    }
    if digit < 0 || digit >= radix {
      return None
    }
    value = value * radix + digit
    i = i + 1
  }
  Some(value.to_double())
}

///|
fn radix_digit(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn register_higher_order_functions(ctx : @value.EvalContext) -> Unit {
  // $eval
  register(ctx, "eval", arity=0, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    if args.length() > 0 && args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    let expr_str = value_to_str(args[0])
    let tokens = @lexer.lex(expr_str) catch {
      _ =>
        raise @error.runtime_error(
          "D3120: Syntax error in expression passed to function eval",
          code=Some("D3120"),
        )
    }
    let ast = @parser.parse(tokens) catch {
      _ =>
        raise @error.runtime_error(
          "D3120: Syntax error in expression passed to function eval",
          code=Some("D3120"),
        )
    }
    // 第二参数作为求值上下文的数据根；无第二参数时使用当前上下文
    try {
      if args.length() > 1 && !args[1].is_undefined() {
        let eval_ctx = @value.EvalContext::new(args[1])
        eval_ctx.inherit_missing_bindings_from(ctx)
        @evaluator.eval(ast, eval_ctx)
      } else {
        @evaluator.eval(ast, ctx)
      }
    } catch {
      _ =>
        raise @error.runtime_error(
          "D3121: Dynamic error evaluating the expression passed to function eval",
          code=Some("D3121"),
        )
    }
  })
  // $exists
  register(ctx, "exists", arity=1, contextual=false, invoke=(args, _ctx) => {
    if args.length() == 0 || args.length() > 1 {
      raise @error.runtime_error(
        "T0410: Arguments are not of expected type",
        code=Some("T0410"),
      )
    }
    let exists = match args[0] {
      @value.JsonataValue::Undefined => false
      _ => true
    }
    @value.JsonataValue::Json(Json::boolean(exists))
  })
  // $not
  register(ctx, "not", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
      _ => @value.JsonataValue::Json(Json::boolean(!value_to_bool(args[0])))
    }
  })
  // $assert — JSONata spec: true→undefined, non-boolean→T0410, false→error
  // 对齐 jsonata-js：失败时抛 D3141（携带 code 字段），无消息时使用
  // 默认 "$assert() statement failed"（function-assert/case006）。
  register(ctx, "assert", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    match args[0] {
      @value.JsonataValue::Json(Json::True) => @value.JsonataValue::Undefined
      @value.JsonataValue::Json(Json::False) => {
        let msg = if args.length() > 1 && !args[1].is_undefined() {
          value_to_str(args[1])
        } else {
          "$assert() statement failed"
        }
        raise @error.runtime_error(msg, code=Some("D3141"))
      }
      _ =>
        raise @error.runtime_error("T0410: Arguments are not of expected type")
    }
  })
}

///|
fn register_special_functions(ctx : @value.EvalContext) -> Unit {
  // $now — 当前时间戳（ISO 8601 格式，简化版）
  register(ctx, "now", arity=0, invoke=fn(
    _args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let millis = @env.now().to_double()
    @value.JsonataValue::Json(Json::string(format_iso_time(millis)))
  })
  // $millis — 当前时间戳（毫秒数）
  register(ctx, "millis", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::number(@env.now().to_double()))
  })
  // $fromMillis — 毫秒数转 ISO 8601 字符串
  register(ctx, "fromMillis", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    let millis = match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) => n
      _ => 0.0
    }
    let result = if args.length() > 1 {
      let offset = if args.length() > 2 {
        parse_timezone_string(value_to_str(args[2]))
      } else {
        0
      }
      if args[1].is_undefined() {
        format_default_date_time(millis, offset)
      } else {
        format_date_picture(millis, value_to_str(args[1]), offset)
      }
    } else {
      format_iso_time(millis)
    }
    @value.JsonataValue::Json(Json::string(result))
  })
  // $toMillis — ISO 8601 字符串转毫秒数
  // JSONata 签名 <s-(s):n>：首参字符串，可选第二参 picture 字符串。
  // 无 picture 时严格校验 ISO 8601 格式，不匹配抛 D3110。
  // 有 picture 时按 picture 解析；输入不匹配 picture 返回 undefined（对齐 JSONata-js）。
  register(ctx, "toMillis", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    match args[0] {
      @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
      _ => {
        let s = value_to_str(args[0])
        // Use context timestamp for default date components (today's date)
        let now_millis = @env.now().to_double()
        let millis_opt = if args.length() > 1 && !args[1].is_undefined() {
          parse_date_picture_with_now(s, value_to_str(args[1]), now_millis)
        } else {
          parse_iso_millis(s)
        }
        match millis_opt {
          None => @value.JsonataValue::Undefined
          Some(m) => @value.JsonataValue::Json(Json::number(m))
        }
      }
    }
  })
  // $formatDateTime — JSONata 日期时间 picture 格式化
  register(ctx, "formatDateTime", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let millis = match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) => n
      _ => 0.0
    }
    let result = if args.length() > 1 {
      let offset = if args.length() > 2 {
        parse_timezone_string(value_to_str(args[2]))
      } else {
        0
      }
      if args[1].is_undefined() {
        format_default_date_time(millis, offset)
      } else {
        format_date_picture(millis, value_to_str(args[1]), offset)
      }
    } else {
      format_iso_time(millis)
    }
    @value.JsonataValue::Json(Json::string(result))
  })
  // $base64encode
  register(ctx, "base64encode", arity=1, invoke=fn(args, _ctx) {
    if args[0].is_undefined() ||
      args[0] is @value.JsonataValue::Json(Json::Null) {
      return @value.JsonataValue::Undefined
    }
    let s = value_to_str(args[0])
    @value.JsonataValue::Json(Json::string(base64_encode(s)))
  })
  // $base64decode
  register(ctx, "base64decode", arity=1, invoke=fn(args, _ctx) {
    if args[0].is_undefined() ||
      args[0] is @value.JsonataValue::Json(Json::Null) {
      return @value.JsonataValue::Undefined
    }
    let s = value_to_str(args[0])
    @value.JsonataValue::Json(Json::string(base64_decode(s)))
  })
  // $error — JSONata spec: string message → D3137, undefined/missing arg →
  // 默认 "$error() function evaluated"（function-error/case009/case010）。
  // 对齐 jsonata-js：始终携带 code=D3137，使 audit 脚本可对 `code` 字段做子串匹配。
  // 关闭 `contextual`：避免 `$error()` 0 参调用时被自动前置上下文，
  // 让 `args.length() == 0` 分支直接走默认消息路径（jsonata-js 同语义）。
  register(ctx, "error", arity=1, contextual=false, invoke=(args, _ctx) => {
    if args.length() == 0 || args[0].is_undefined() {
      raise @error.runtime_error(
        "$error() function evaluated",
        code=Some("D3137"),
      )
    }
    match args[0] {
      @value.JsonataValue::Json(Json::String(s)) =>
        raise @error.runtime_error(s, code=Some("D3137"))
      _ =>
        raise @error.runtime_error("T0410: Arguments are not of expected type")
    }
  })
  // $encodeUrl — 对整个 URL 做百分号编码，保留 URL 保留字符
  // 对齐 jsonata-js：输入含 lone surrogate（U+D800–U+DFFF）时抛 D3140，
  // 消息包含 functionName 与原值（function-encodeUrl/case002）。
  register(ctx, "encodeUrl", arity=1, invoke=fn(
    args,
    _ctx,
  ) -> @value.JsonataValue raise @error.JsonataError {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    let s = value_to_str(args[0])
    reject_url_surrogate(s, "encodeUrl")
    @value.JsonataValue::Json(Json::string(percent_encode(s, UrlMode::FullUrl)))
  })
  // $decodeUrl — 解码百分号编码的 URL
  // 对齐 jsonata-js：百分号解码后做严格 UTF-8 校验，遇非法字节序列抛 D3140，
  // 消息包含函数名与原始输入（function-decodeUrl/case002）。
  register(ctx, "decodeUrl", arity=1, invoke=fn(
    args,
    _ctx,
  ) -> @value.JsonataValue raise @error.JsonataError {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    let s = value_to_str(args[0])
    let decoded = percent_decode_strict(s, "decodeUrl")
    @value.JsonataValue::Json(Json::string(decoded))
  })
  // $encodeUrlComponent — 对 URL 组件做百分号编码（不保留任何保留字符）
  register(ctx, "encodeUrlComponent", arity=1, invoke=fn(
    args,
    _ctx,
  ) -> @value.JsonataValue raise @error.JsonataError {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    let s = value_to_str(args[0])
    reject_url_surrogate(s, "encodeUrlComponent")
    @value.JsonataValue::Json(
      Json::string(percent_encode(s, UrlMode::Component)),
    )
  })
  // $decodeUrlComponent — 解码百分号编码的 URL 组件
  register(ctx, "decodeUrlComponent", arity=1, invoke=fn(
    args,
    _ctx,
  ) -> @value.JsonataValue raise @error.JsonataError {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    let s = value_to_str(args[0])
    let decoded = percent_decode_strict(s, "decodeUrlComponent")
    @value.JsonataValue::Json(Json::string(decoded))
  })
}

///|
/// 将毫秒时间戳格式化为 ISO 8601 字符串
fn format_iso_time(millis : Double) -> String raise @error.JsonataError {
  let dt = datetime_from_millis(millis, 0)
  "\{pad4(dt.year())}-\{pad2(dt.month())}-\{pad2(dt.day())}T\{pad2(dt.hour())}:\{pad2(dt.minute())}:\{pad2(dt.second())}.\{pad3(dt.nanosecond() / 1_000_000)}Z"
}

///|
fn datetime_from_millis(
  millis : Double,
  offset_seconds : Int,
) -> @time.ZonedDateTime raise @error.JsonataError {
  let total_millis = millis.to_int64()
  let seconds = floor_div64(total_millis, 1000L)
  let millisecond = (total_millis - seconds * 1000L).to_int()
  let nanosecond = millisecond * 1_000_000
  let zone = if offset_seconds == 0 {
    @time.utc_zone
  } else {
    @time.fixed_zone(offset_id(offset_seconds), offset_seconds) catch {
      _ => raise @error.runtime_error("invalid timezone offset")
    }
  }
  @time.ZonedDateTime::from_unix_second(seconds, nanosecond~, zone~) catch {
    _ => raise @error.runtime_error("invalid unix timestamp")
  }
}

///|
fn floor_div64(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  let r = a % b
  if r != 0L && (r < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
fn format_default_date_time(
  millis : Double,
  offset_seconds : Int,
) -> String raise @error.JsonataError {
  format_date_picture(
    millis, "[Y0001]-[M01]-[D01]T[H01]:[m01]:[s01].[f001][Z01:01t]", offset_seconds,
  )
}

///|
fn format_date_picture(
  millis : Double,
  picture : String,
  offset_seconds : Int,
) -> String raise @error.JsonataError {
  let dt = datetime_from_millis(millis, offset_seconds)
  // 预扫描：检查所有 marker 是否有匹配的 ']'，无匹配则抛 D3135
  // 对齐 JSONata-js 在解析阶段先于格式化阶段检查
  validate_date_picture_brackets(picture)
  let out = StringBuilder::new()
  let chars = picture.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '[' {
      if i + 1 < chars.length() && chars[i + 1] == '[' {
        out.write_char('[')
        i += 2
      } else {
        let mut j = i + 1
        while j < chars.length() && chars[j] != ']' {
          j += 1
        }
        // j < chars.length() 保证成立（预扫描已验证）
        out.write_string(
          format_date_marker(
            dt,
            chars_to_string(chars, i + 1, j),
            offset_seconds,
          ),
        )
        i = j + 1
      }
    } else if chars[i] == ']' && i + 1 < chars.length() && chars[i + 1] == ']' {
      out.write_char(']')
      i += 2
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}

///|
/// 验证 date picture 中所有 marker 都有匹配的 ']'，否则抛 D3135。
/// 跳过 `[[`（转义的 `[`）和 `]]`（转义的 `]`）。
fn validate_date_picture_brackets(
  picture : String,
) -> Unit raise @error.JsonataError {
  let chars = picture.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    if chars[i] == '[' {
      if i + 1 < n && chars[i + 1] == '[' {
        // 转义的 [[
        i += 2
      } else {
        // 查找匹配的 ]
        let mut j = i + 1
        let mut found = false
        while j < n {
          if chars[j] == ']' {
            found = true
            break
          }
          j += 1
        }
        if !found {
          raise @error.runtime_error(
            "D3135: The picture contains a component with no closing bracket ']'",
            code=Some("D3135"),
          )
        }
        i = j + 1
      }
    } else if chars[i] == ']' && i + 1 < n && chars[i + 1] == ']' {
      // 转义的 ]]
      i += 2
    } else {
      i += 1
    }
  }
}

///|
fn format_date_marker(
  dt : @time.ZonedDateTime,
  marker : String,
  offset_seconds : Int,
) -> String raise @error.JsonataError {
  let marker = normalize_marker(marker)
  match marker {
    "Y" => dt.year().to_string()
    "Y0001" => pad4(dt.year())
    "Y9,999,*" => group_thousands(dt.year())
    "YI" => to_roman(dt.year())
    "Yi" => to_roman(dt.year()).to_lower()
    "Yw" => number_to_words(dt.year().to_double())
    "Ywo" => number_to_ordinal_words(dt.year().to_double())
    "X0001" => pad4(iso_week_year(dt))
    "M" | "M#1" => dt.month().to_string()
    "M01" => pad2(dt.month())
    "M1,2" => pad2(dt.month())
    "MA" => to_letters(dt.month())
    "Ma" => to_letters(dt.month()).to_lower()
    "MNn" => month_name(dt.month(), "title")
    "MN" => month_name(dt.month(), "upper")
    "MNn,3-3" =>
      month_name(dt.month(), "title").unsafe_substring(start=0, end=3)
    "D" | "D#1" => dt.day().to_string()
    "D01" => pad2(dt.day())
    "D#1,2" | "D1" => pad2(dt.day())
    "DA" => to_letters(dt.day())
    "Da" => to_letters(dt.day()).to_lower()
    "D1o" => "\{dt.day()}\{ordinal_suffix(dt.day())}"
    "Dwo" => number_to_ordinal_words(dt.day().to_double())
    "H" | "H#1" => dt.hour().to_string()
    "H01" => pad2(dt.hour())
    "h" | "h#1" => hour12(dt.hour()).to_string()
    "h01" => pad2(hour12(dt.hour()))
    "m" | "m#1" => pad2(dt.minute())
    "m01" => pad2(dt.minute())
    "s" | "s#1" => pad2(dt.second())
    "s01" => pad2(dt.second())
    "f" | "f001" => pad3(dt.nanosecond() / 1_000_000)
    "d" => dt.ordinal().to_string()
    "d001" => pad3(dt.ordinal())
    "dwo" => number_to_ordinal_words(dt.ordinal().to_double())
    "W" => iso_week(dt).to_string()
    "W01" => pad2(iso_week(dt))
    "w" => week_in_month(dt).to_string()
    "w01" => pad2(week_in_month(dt))
    "Z" => offset_colon(offset_seconds)
    "Z0" => offset_compact(offset_seconds)
    "Z01:01" => offset_colon(offset_seconds)
    "Z01:01t" =>
      if offset_seconds == 0 {
        "Z"
      } else {
        offset_colon(offset_seconds)
      }
    "Z0101t" =>
      if offset_seconds == 0 {
        "Z"
      } else {
        offset_digits(offset_seconds)
      }
    "z" => "GMT\{offset_colon(offset_seconds)}"
    "F" => weekday_name(dt, "lower")
    "F0" => weekday_number(dt).to_string()
    "F1" => weekday_number(dt).to_string()
    "FNn" => weekday_name(dt, "title")
    "FN" => weekday_name(dt, "upper")
    "FNn,3-3" => weekday_name(dt, "title").unsafe_substring(start=0, end=3)
    "P" | "Pn" => if dt.hour() < 12 { "am" } else { "pm" }
    "PN" => if dt.hour() < 12 { "AM" } else { "PM" }
    "E" | "C" => "ISO"
    "xNn" => month_name(week_numbering_month(dt), "title")
    "xN" => month_name(week_numbering_month(dt), "upper")
    _ =>
      if marker.length() > 0 && marker.get_char(0) == Some('Y') {
        if marker.contains("N") {
          // [YN] year name 不支持 → D3133
          raise @error.runtime_error(
            "D3133: The 'N' name modifier is only valid for month (M) and day (F) components",
            code=Some("D3133"),
          )
        }
        if marker.contains(",2-2") {
          pad2(dt.year() % 100)
        } else {
          // [Y,n] width spec: truncate year to last n digits
          let width = picture_year_digits(marker)
          let y = if width > 0 && width < 4 {
            dt.year() % pow10(width)
          } else {
            dt.year()
          }
          y.to_string()
        }
      } else if marker.length() > 0 && marker.get_char(0) == Some('Z') {
        // D3134: timezone 数字位数超过 4 → 错误
        // 仅允许 1-4 位数字（1-2: hours, 3-4: hours+minutes）
        let mut digit_count = 0
        for k in 1..<marker.length() {
          let c = marker.get_char(k).unwrap_or('\u{0}')
          if c >= '0' && c <= '9' {
            digit_count = digit_count + 1
          }
        }
        if digit_count > 4 {
          raise @error.runtime_error(
            "D3134: The timezone marker has too many digits: \{marker}",
            code=Some("D3134"),
          )
        }
        offset_digits(offset_seconds)
      } else if marker.length() > 0 && marker.get_char(0) == Some('M') {
        dt.month().to_string()
      } else if marker.length() > 0 && marker.get_char(0) == Some('D') {
        dt.day().to_string()
      } else {
        ""
      }
  }
}

///|
fn normalize_marker(marker : String) -> String {
  let out = StringBuilder::new()
  for c in marker {
    if c != ' ' && c != '\n' && c != '\t' && c != '\r' {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// Picture segment types for date parsing
enum PictureSegment {
  Literal(String)
  Marker(String) // normalized marker
} derive(Debug)

///|
/// Components extracted from a date string via picture parsing
struct DateComponents {
  mut year : Int?
  mut month : Int?
  mut day : Int?
  mut hour24 : Int?
  mut hour12 : Int?
  mut minute : Int?
  mut second : Int?
  mut millis : Int?
  mut offset : Int?
  mut day_of_year : Int?
  mut am_pm : Bool? // true=PM
  mut weekday : Int?
} derive(Debug)

///|
fn parse_date_picture_with_now(
  s : String,
  picture : String,
  now_millis : Double,
) -> Double? raise @error.JsonataError {
  let segments = split_picture(picture)
  // 若 picture 中无 marker（全 literal），对齐 JSONata-js 返回 undefined
  let has_marker = segments
    .iter()
    .any(fn(seg) { seg is PictureSegment::Marker(_) })
  if !has_marker {
    return None
  }
  match extract_date_components(s, segments) {
    None => None
    Some(comps) =>
      Some(build_date_from_components_with_now(comps, picture, now_millis))
  }
}

///|
/// Split a picture string into Literal and Marker segments.
fn split_picture(picture : String) -> Array[PictureSegment] {
  let chars = picture.to_array()
  let result : Array[PictureSegment] = []
  let mut i = 0
  let mut lit_buf = StringBuilder::new()
  while i < chars.length() {
    if chars[i] == '[' {
      if i + 1 < chars.length() && chars[i + 1] == '[' {
        lit_buf.write_char('[')
        i += 2
      } else {
        if lit_buf.to_string().length() > 0 {
          result.push(PictureSegment::Literal(lit_buf.to_string()))
          lit_buf = StringBuilder::new()
        }
        let mut j = i + 1
        while j < chars.length() && chars[j] != ']' {
          j += 1
        }
        if j < chars.length() {
          let marker = normalize_marker(chars_to_string(chars, i + 1, j))
          result.push(PictureSegment::Marker(marker))
          i = j + 1
        } else {
          lit_buf.write_char(chars[i])
          i += 1
        }
      }
    } else if chars[i] == ']' && i + 1 < chars.length() && chars[i + 1] == ']' {
      lit_buf.write_char(']')
      i += 2
    } else {
      lit_buf.write_char(chars[i])
      i += 1
    }
  }
  if lit_buf.to_string().length() > 0 {
    result.push(PictureSegment::Literal(lit_buf.to_string()))
  }
  result
}

///|
/// Extract date components from input string using picture segments.
fn extract_date_components(
  input : String,
  segments : Array[PictureSegment],
) -> DateComponents? raise @error.JsonataError {
  let comps = DateComponents::default()

  // Build a flat token list: literal segments become delimiters
  // Markers extract values from the input.
  // Strategy: scan both picture segments and input simultaneously.
  // Each marker consumes as many characters from input as its format dictates,
  // and the following literal acts as the delimiter.

  let input_chars = input.to_array()
  let mut pos = 0

  // Process segments in order
  for idx, seg in segments {
    match seg {
      PictureSegment::Literal(lit) => {
        // Match the literal exactly in the input
        let lit_chars = lit.to_array()
        if pos + lit_chars.length() > input_chars.length() {
          if idx == segments.length() - 1 && pos == input_chars.length() {
            // trailing literal at end, ok
          } else {
            // 输入不匹配 picture literal，对齐 JSONata-js 返回 undefined
            return None
          }
        } else {
          let mut matched = true
          for j in 0..<lit_chars.length() {
            if input_chars[pos + j] != lit_chars[j] {
              matched = false
              break
            }
          }
          if !matched {
            // 输入不匹配 picture literal，对齐 JSONata-js 返回 undefined
            return None
          }
          pos += lit_chars.length()
        }
      }
      PictureSegment::Marker(marker) => {
        // Determine if there's a trailing literal delimiter
        let delim = find_next_literal(segments, idx)
        // Find the end of this marker's value in the input
        let end_pos = find_marker_end(input_chars, pos, delim, marker)
        if pos >= end_pos && marker_is_optional(marker) {
          continue // e.g., timezone that defaults to UTC
        }
        if pos >= end_pos {
          // marker 未消费任何字符且非可选，输入不匹配
          return None
        }
        let value = chars_to_string(input_chars, pos, end_pos)
        // Parse value according to marker type。
        // D3110 (invalid numeric value) 视为输入不匹配 picture，返回 None（对齐 JSONata-js）。
        // D3132/D3133/D3136 等 picture 错误仍然向上传播。
        extract_marker_value(comps, marker, value) catch {
          @error.JsonataError::RuntimeError(code=Some("D3110"), ..) =>
            return None
          e => raise e
        }
        pos = end_pos
      }
    }
  }
  // If we haven't consumed all input, input doesn't match picture
  if pos < input_chars.length() {
    return None
  }
  // 若没有任何组件被提取，对齐 JSONata-js 返回 undefined
  let has_any = comps.year is Some(_) ||
    comps.month is Some(_) ||
    comps.day is Some(_) ||
    comps.day_of_year is Some(_) ||
    comps.hour24 is Some(_) ||
    comps.hour12 is Some(_) ||
    comps.minute is Some(_) ||
    comps.second is Some(_) ||
    comps.millis is Some(_) ||
    comps.offset is Some(_) ||
    comps.am_pm is Some(_) ||
    comps.weekday is Some(_)
  if !has_any {
    return None
  }
  Some(comps)
}

///|
/// Find the next literal after a marker in segments
fn find_next_literal(segments : Array[PictureSegment], start : Int) -> String? {
  let mut i = start + 1
  while i < segments.length() {
    match segments[i] {
      PictureSegment::Literal(lit) => return Some(lit)
      _ => i += 1
    }
  }
  None
}

///|
/// Find the end position of a marker's value in the input.
/// If there's a delimiter, find it; if fixed-width, use that; otherwise consume to end.
fn find_marker_end(
  chars : Array[Char],
  start : Int,
  delim : String?,
  marker : String,
) -> Int {
  // First try: determine fixed width from marker
  let width = marker_char_width(marker)
  match width {
    Some(w) => {
      let end = start + w
      if end > chars.length() {
        start
      } else {
        end
      }
    }
    None => find_delim_end(chars, start, delim)
  }
}

///|
/// Determine the character width of a marker from its format specifier.
/// Returns None for variable-width markers (named, ordinal, etc.).
fn marker_char_width(marker : String) -> Int? {
  if marker.length() == 0 {
    return None
  }
  let c0 = match marker.get_char(0) {
    Some(c) => c
    None => return None
  }
  match c0 {
    'Y' => {
      // Y0001 -> 4, Y00 -> 2, Y0000 -> 4
      // Y1 -> variable ([0-9]+), Y -> variable
      // Y,*-4 -> fixed 4 (width modifier max), YI/Yi -> roman, Yw -> word
      let has_I = marker.contains("I")
      let has_i = marker.contains("i")
      let has_w = marker.contains("w")
      if has_I || has_i || has_w {
        None
      } else {
        match parse_marker_width_mod(marker) {
          Some(w) => Some(w)
          None =>
            // No width modifier: mandatory digits > 1 => fixed, else variable
            if marker == "Y" {
              None
            } else {
              let count = marker_placeholder_count(marker)
              if count > 1 {
                Some(count)
              } else {
                None
              }
            }
        }
      }
    }
    'M' =>
      if marker.has_prefix("MN") {
        None // Named month
      } else if marker.contains("i") ||
        marker.contains("A") ||
        marker.contains("a") {
        None // Roman numeral or abbreviated
      } else {
        match parse_marker_width_mod(marker) {
          Some(w) => Some(w)
          None =>
            // M01 -> 2, M#1 -> variable, M -> variable, M1 -> variable
            if marker.contains("#") || marker == "M" {
              None
            } else {
              let count = marker_placeholder_count(marker)
              if count > 1 {
                Some(count)
              } else {
                None
              }
            }
        }
      }
    'D' => {
      let has_o = marker.contains("o")
      let has_Ww = marker.contains("Ww")
      let starts_Dw = marker.has_prefix("Dw") || marker.has_prefix("DW")
      let has_a = marker.contains("a")
      let has_A = marker.contains("A")
      if has_o || has_Ww || starts_Dw || has_a || has_A {
        None // Ordinal, word, or abbreviated
      } else {
        match parse_marker_width_mod(marker) {
          Some(w) => Some(w)
          None =>
            if marker.contains("#") || marker == "D" {
              None
            } else {
              let count = marker_placeholder_count(marker)
              if count > 1 {
                Some(count)
              } else {
                None
              }
            }
        }
      }
    }
    'H' | 'h' =>
      match parse_marker_width_mod(marker) {
        Some(w) => Some(w)
        None =>
          if marker == "H" || marker == "h" || marker.contains("#") {
            None
          } else {
            let count = marker_placeholder_count(marker)
            if count > 1 {
              Some(count)
            } else {
              None
            }
          }
      }
    'm' =>
      match parse_marker_width_mod(marker) {
        Some(w) => Some(w)
        None =>
          if marker == "m" || marker.contains("#") {
            None
          } else {
            let count = marker_placeholder_count(marker)
            if count > 1 {
              Some(count)
            } else {
              None
            }
          }
      }
    's' =>
      match parse_marker_width_mod(marker) {
        Some(w) => Some(w)
        None =>
          if marker == "s" || marker.contains("#") {
            None
          } else {
            let count = marker_placeholder_count(marker)
            if count > 1 {
              Some(count)
            } else {
              None
            }
          }
      }
    'f' =>
      // f001 -> 3, f -> variable, f1 -> variable
      if marker == "f" || marker == "f1" {
        None
      } else {
        Some(marker_placeholder_count(marker))
      }
    'd' =>
      if marker.contains("wo") {
        None // Word ordinal
      } else if marker == "d" {
        None
      } else {
        let count = marker_placeholder_count(marker)
        if count > 1 {
          Some(count)
        } else {
          None
        }
      }
    'F' => None // Named or numeric weekday
    'Z' | 'z' => None // Variable timezone
    'P' => None // AM/PM
    'X' | 'x' | 'W' | 'w' => None
    _ => None
  }
}

///|
/// Parse the width modifier (the part after the comma) of a marker.
/// Per XPath/XQuery fn:format-integer §9.8.4.2, the modifier is `min` or
/// `min-max`, where each may be `*` (unbounded). For Y, the `max` value
/// pins the mandatory digit count and thus the parse width.
/// Returns Some(width) only when a fixed width can be derived; None otherwise.
fn parse_marker_width_mod(marker : String) -> Int? {
  let comma = match marker.find(",") {
    Some(idx) => idx
    None => return None
  }
  let width_mod = marker[comma + 1:].to_owned()
  let dash = match width_mod.find("-") {
    Some(idx) => idx
    None =>
      // single value = min only
      return None
  }
  let max_str = width_mod[dash + 1:].trim().to_owned()
  if max_str == "*" || max_str.length() == 0 {
    return None
  }
  match parse_int_opt(max_str) {
    Some(n) => Some(n)
    None => None
  }
}

///|
/// Count digit placeholder characters in a marker (0, 1, #)
fn marker_placeholder_count(marker : String) -> Int {
  let mut count = 0
  for c in marker {
    match c {
      '0' | '1' | '#' => count += 1
      _ => ()
    }
  }
  count
}

///|
/// Find end position by scanning for delimiter or end of input
fn find_delim_end(chars : Array[Char], start : Int, delim : String?) -> Int {
  match delim {
    Some(d) => {
      let mut i = start
      let del_chars = d.to_array()
      while i + del_chars.length() <= chars.length() {
        let mut matched = true
        for j in 0..<del_chars.length() {
          if chars[i + j] != del_chars[j] {
            matched = false
            break
          }
        }
        if matched {
          return i
        }
        i += 1
      }
      chars.length()
    }
    None => chars.length()
  }
}

///|
fn marker_is_optional(marker : String) -> Bool {
  marker == "Z" ||
  marker.has_prefix("Z0") ||
  marker.has_prefix("z") ||
  marker == "P" ||
  marker == "Pn" ||
  marker == "PN"
}

///|
/// Parse a marker value string into components
fn extract_marker_value(
  comps : DateComponents,
  marker : String,
  value : String,
) -> Unit raise @error.JsonataError {
  // Determine marker type from first character
  if marker.length() == 0 {
    return
  }
  let c0 = match marker.get_char(0) {
    Some(c) => c
    None => return
  }
  match c0 {
    'Y' =>
      if marker.contains("N") {
        // [YN] named year → D3133: 'N' name modifier only valid for M and F
        raise @error.runtime_error(
          "D3133: The 'name' modifier can only be applied to months and days in the date/time picture string, not Y",
          code=Some("D3133"),
        )
      } else if marker.contains("I") || marker.contains("i") {
        // Roman numeral year
        comps.year = Some(parse_roman_numeral(value))
      } else if marker.contains("w") {
        // Word year
        comps.year = Some(parse_word_number(value))
      } else {
        comps.year = parse_int_opt(value)
        if comps.year is None {
          raise @error.runtime_error("D3110: invalid year", code=Some("D3110"))
        }
      }
    'M' =>
      if marker.has_prefix("MN") {
        // Named month
        let m = parse_month_name(value)
        comps.month = Some(m)
      } else if marker.contains("i") {
        // Roman numeral month
        comps.month = Some(parse_roman_numeral(value))
      } else if marker.contains("A") || marker.contains("a") {
        // Letter-based month (A=1, B=2, ..., AA=27, etc.)
        comps.month = Some(letters_to_decimal(value))
      } else {
        comps.month = parse_int_opt(value)
        if comps.month is None {
          raise @error.runtime_error("D3110: invalid month", code=Some("D3110"))
        }
      }
    'D' =>
      if marker.contains("Wwo") {
        // Word-ordinal day like "Twelfth", "Twenty-first"
        let d = parse_word_ordinal(value)
        comps.day = Some(d)
      } else if marker.has_prefix("Dw") || marker.has_prefix("DW") {
        // Word day like "twenty-seven", "twenty-seventh" (case-insensitive)
        let d = parse_word_number(value)
        comps.day = Some(d)
      } else if marker.contains("o") {
        // Numeric ordinal day like "27th"
        let d = parse_ordinal_day(value)
        comps.day = Some(d)
      } else if marker.contains("A") || marker.contains("a") {
        // Letter-based day (A=1, B=2, ..., AA=27, etc.)
        comps.day = Some(letters_to_decimal(value))
      } else {
        comps.day = parse_int_opt(value)
        if comps.day is None {
          raise @error.runtime_error("D3110: invalid day", code=Some("D3110"))
        }
      }
    'F' =>
      // Weekday - parse name or number
      if marker.has_prefix("FN") {
        let wd = parse_weekday_name(value)
        comps.weekday = Some(wd)
      } else if marker == "F0" || marker == "F1" {
        comps.weekday = parse_int_opt(value)
      } else if marker == "F" {
        let wd = parse_weekday_name(value)
        comps.weekday = Some(wd)
      }
    'H' => {
      comps.hour24 = parse_int_opt(value)
      if comps.hour24 is None {
        raise @error.runtime_error("D3110: invalid hour", code=Some("D3110"))
      }
    }
    'h' => {
      comps.hour12 = parse_int_opt(value)
      if comps.hour12 is None {
        raise @error.runtime_error("D3110: invalid hour", code=Some("D3110"))
      }
    }
    'm' => {
      comps.minute = parse_int_opt(value)
      if comps.minute is None {
        raise @error.runtime_error("D3110: invalid minute", code=Some("D3110"))
      }
    }
    's' => {
      comps.second = parse_int_opt(value)
      if comps.second is None {
        raise @error.runtime_error("D3110: invalid second", code=Some("D3110"))
      }
    }
    'f' => comps.millis = Some(parse_fraction_from_string(value))
    'd' =>
      if marker.contains("wo") {
        // Word-ordinal day of year
        let doy = parse_word_number(value)
        comps.day_of_year = Some(doy)
      } else {
        comps.day_of_year = parse_int_opt(value)
        if comps.day_of_year is None {
          raise @error.runtime_error(
            "D3110: invalid day of year",
            code=Some("D3110"),
          )
        }
      }
    'Z' | 'z' =>
      if value != "" {
        comps.offset = Some(parse_picture_timezone(value))
      }
    'P' => comps.am_pm = Some(parse_am_pm(value))
    'X' =>
      raise @error.runtime_error(
        "D3136: unsupported picture component",
        code=Some("D3136"),
      )
    'x' =>
      raise @error.runtime_error(
        "D3136: unsupported picture component",
        code=Some("D3136"),
      )
    'W' =>
      raise @error.runtime_error(
        "D3136: unsupported picture component",
        code=Some("D3136"),
      )
    'w' =>
      raise @error.runtime_error(
        "D3136: unsupported picture component",
        code=Some("D3136"),
      )
    'C' | 'E' => ()
    _ =>
      // Try to handle Y-variant markers that start differently
      if marker.contains(",2-2") {
        comps.year = parse_int_opt(value)
      } else {
        // 未知组件标识符 → D3132（对齐 JSONata-js analyseDateTimePicture）
        raise @error.runtime_error(
          "D3132: Unknown component specifier \{c0} in date/time picture string",
          code=Some("D3132"),
        )
      }
  }
}

///|
fn parse_int_opt(s : String) -> Int? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if chars[0] == '+' {
    i = 1
  } else if chars[0] == '-' {
    i = 1
    neg = true
  }
  if i >= chars.length() {
    return None
  }
  let mut val = 0
  while i < chars.length() {
    if !is_digit(chars[i]) {
      return None
    }
    val = val * 10 + digit_value(chars[i])
    i += 1
  }
  if neg {
    Some(-val)
  } else {
    Some(val)
  }
}

///|
/// Parse spreadsheet-style letters to decimal (A=1, B=2, ..., Z=26, AA=27, etc.)
/// Case-insensitive: "ae" -> 31, "w" -> 23, "A" -> 1
fn letters_to_decimal(s : String) -> Int {
  let mut value = 0
  for _, c0 in s {
    // Normalize to uppercase
    let c = if c0 >= 'a' && c0 <= 'z' {
      Int::unsafe_to_char(c0.to_int() - 32)
    } else {
      c0
    }
    if c >= 'A' && c <= 'Z' {
      value = value * 26 + (c.to_int() - 'A'.to_int() + 1)
    }
  }
  value
}

///|
/// Parse ordinal day like "1st", "21st", "2nd", "3rd", "4th"
fn parse_ordinal_day(s : String) -> Int raise @error.JsonataError {
  // Strip ordinal suffix
  let trimmed = s.trim().to_owned()
  if trimmed.length() < 2 {
    raise @error.runtime_error("D3110: invalid ordinal", code=Some("D3110"))
  }
  let mut num_end = trimmed.length()
  // Remove trailing ordinal suffix
  let has_st = trimmed.has_suffix("st")
  let has_nd = trimmed.has_suffix("nd")
  let has_rd = trimmed.has_suffix("rd")
  let has_th = trimmed.has_suffix("th")
  if has_st || has_nd || has_rd || has_th {
    num_end -= 2
  }
  let num_part = trimmed[:num_end].to_owned()
  match parse_int_opt(num_part) {
    Some(n) => n
    None =>
      raise @error.runtime_error(
        "D3110: invalid ordinal day",
        code=Some("D3110"),
      )
  }
}

///|
/// Parse month name (January, Jan, JANUARY, etc.)
fn parse_month_name(s : String) -> Int raise @error.JsonataError {
  let lower = s.trim().to_lower()
  match lower {
    "january" | "jan" => 1
    "february" | "feb" => 2
    "march" | "mar" => 3
    "april" | "apr" => 4
    "may" => 5
    "june" | "jun" => 6
    "july" | "jul" => 7
    "august" | "aug" => 8
    "september" | "sep" | "sept" => 9
    "october" | "oct" => 10
    "november" | "nov" => 11
    "december" | "dec" => 12
    _ =>
      raise @error.runtime_error(
        "D3110: invalid month name",
        code=Some("D3110"),
      )
  }
}

///|
/// Parse weekday name
fn parse_weekday_name(s : String) -> Int raise @error.JsonataError {
  let lower = s.trim().to_lower()
  match lower {
    "monday" | "mon" => 1
    "tuesday" | "tue" | "tues" => 2
    "wednesday" | "wed" => 3
    "thursday" | "thu" | "thur" | "thurs" => 4
    "friday" | "fri" => 5
    "saturday" | "sat" => 6
    "sunday" | "sun" => 7
    _ =>
      raise @error.runtime_error(
        "D3110: invalid weekday name",
        code=Some("D3110"),
      )
  }
}

///|
/// Parse fractional seconds string into millis
fn parse_fraction_from_string(s : String) -> Int {
  let mut value = 0
  let mut count = 0
  for c in s {
    if is_digit(c) && count < 3 {
      value = value * 10 + digit_value(c)
      count += 1
    }
  }
  while count < 3 {
    value *= 10
    count += 1
  }
  value
}

///|
/// Parse AM/PM from a string
fn parse_am_pm(s : String) -> Bool {
  let lower = s.trim().to_owned().to_lower()
  if lower == "pm" || lower == "p.m." || lower == "p" {
    true
  } else {
    false
  }
}

///|
/// Parse timezone from picture-extracted value
fn parse_picture_timezone(s : String) -> Int {
  let trimmed = s.trim().to_owned()
  if trimmed == "" || trimmed == "Z" || trimmed == "z" {
    return 0
  }
  // Handle GMT±HH:MM or GMT±HHMM or GMT±H
  if trimmed.has_prefix("GMT") {
    let rest = trimmed[3:].trim().to_owned()
    return parse_tz_offset_body(rest)
  }
  // Handle ±HH:MM or ±HHMM or ±HH
  parse_tz_offset_body(trimmed)
}

///|
fn parse_tz_offset_body(s : String) -> Int {
  if s == "" {
    return 0
  }
  let chars = s.to_array()
  if chars[0] == '+' || chars[0] == '-' {
    return parse_timezone_offset(chars, 0)
  }
  0
}

///|
/// Word-ordinal value parsing (for [DWwo], [dwo])
fn parse_word_ordinal(s : String) -> Int raise @error.JsonataError {
  let lower = s.trim().to_lower()
  match lower {
    "first" | "1st" => 1
    "second" | "2nd" => 2
    "third" | "3rd" => 3
    "fourth" | "4th" => 4
    "fifth" | "5th" => 5
    "sixth" | "6th" => 6
    "seventh" | "7th" => 7
    "eighth" | "8th" => 8
    "ninth" | "9th" => 9
    "tenth" | "10th" => 10
    "eleventh" | "11th" => 11
    "twelfth" | "12th" => 12
    "thirteenth" | "13th" => 13
    "fourteenth" | "14th" => 14
    "fifteenth" | "15th" => 15
    "sixteenth" | "16th" => 16
    "seventeenth" | "17th" => 17
    "eighteenth" | "18th" => 18
    "nineteenth" | "19th" => 19
    "twentieth" | "20th" => 20
    "twenty-first" | "twentyfirst" | "21st" => 21
    "twenty-second" | "twentysecond" | "22nd" => 22
    "twenty-third" | "twentythird" | "23rd" => 23
    "twenty-fourth" | "twentyfourth" | "24th" => 24
    "twenty-fifth" | "twentyfifth" | "25th" => 25
    "twenty-sixth" | "twentysixth" | "26th" => 26
    "twenty-seventh" | "twentyseventh" | "27th" => 27
    "twenty-eighth" | "twentyeighth" | "28th" => 28
    "twenty-ninth" | "twentyninth" | "29th" => 29
    "thirtieth" | "30th" => 30
    "thirty-first" | "thirtyfirst" | "31st" => 31
    _ =>
      // Try parsing as number with optional ordinal suffix
      parse_ordinal_day(s)
  }
}

///|
/// Parse a Roman numeral string to integer
fn parse_roman_numeral(s : String) -> Int raise @error.JsonataError {
  let upper = s.trim().to_owned().to_upper()
  let mut total = 0
  let mut prev = 0
  let chars = upper.to_array()
  let mut i = chars.length()
  while i > 0 {
    i -= 1
    let val = match chars[i] {
      'I' => 1
      'V' => 5
      'X' => 10
      'L' => 50
      'C' => 100
      'D' => 500
      'M' => 1000
      _ =>
        raise @error.runtime_error(
          "D3110: invalid roman numeral",
          code=Some("D3110"),
        )
    }
    if val < prev {
      total -= val
    } else {
      total += val
    }
    prev = val
  }
  total
}

///|
/// Parse a word number like "one thousand, nine hundred and eighty-four"
fn parse_word_number(s : String) -> Int {
  // Clean the input: remove commas, hyphens, "and"
  let lower = s.to_lower()
  let trimmed = lower.trim()
  let cleaned = trimmed.to_owned()
  // Remove commas, hyphens, and standalone "and"
  let no_commas = cleaned.replace_all(old=",", new="")
  let no_hyphens = no_commas.replace_all(old="-", new=" ")
  let no_and = no_hyphens.replace_all(old=" and ", new=" ")
  let final_text = no_and.trim().to_owned()
  let words = split_words(final_text)

  // Map of word values
  let singles : Map[String, Int] = {
    "zero": 0,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
    "eleven": 11,
    "twelve": 12,
    "thirteen": 13,
    "fourteen": 14,
    "fifteen": 15,
    "sixteen": 16,
    "seventeen": 17,
    "eighteen": 18,
    "nineteen": 19,
  }
  let tens : Map[String, Int] = {
    "twenty": 20,
    "thirty": 30,
    "forty": 40,
    "fifty": 50,
    "sixty": 60,
    "seventy": 70,
    "eighty": 80,
    "ninety": 90,
  }
  let multipliers : Map[String, Int] = { "hundred": 100, "thousand": 1000 }

  let mut result = 0
  let mut current = 0

  for w in words {
    let mut value = 0
    // Strip ordinal suffix if present
    let base_word = strip_ordinal_suffix(w)

    match singles.get(base_word) {
      Some(v) => value = v
      None =>
        match tens.get(base_word) {
          Some(v) => value = v
          None =>
            match multipliers.get(base_word) {
              Some(v) => {
                if current == 0 {
                  current = 1
                }
                if v == 1000 {
                  result += current * v
                  current = 0
                } else {
                  // v == 100
                  current *= v
                }
                continue
              }
              None => continue
            }
        }
    }
    current += value
  }
  result += current
  result
}

///|
/// Strip ordinal suffix (st, nd, rd, th) from a word.
/// Only strips if the remaining base is a known number component.
fn strip_ordinal_suffix(w : String) -> String {
  let len = w.length()
  if len > 2 {
    let suffix = w[len - 2:].to_owned()
    if suffix == "st" || suffix == "nd" || suffix == "rd" || suffix == "th" {
      let base = w[:len - 2].to_owned()
      let result = ordinal_base_to_cardinal(base)
      // Accept if result is a valid cardinal (in singles/tens/multipliers)
      // This handles both transformed forms ("fir" -> "one") and
      // already-cardinal forms ("seven" -> "seven")
      if is_valid_word_number_component(result) {
        return result
      }
    }
  }
  w
}

///|
/// Check if a word is a valid number component (singles, tens, or multiplier)
fn is_valid_word_number_component(word : String) -> Bool {
  let singles = [
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
    "eighteen", "nineteen",
  ]
  let tens = [
    "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
  ]
  let multipliers = ["hundred", "thousand"]
  singles.contains(word) || tens.contains(word) || multipliers.contains(word)
}

///|
/// Convert ordinal base form to cardinal form
fn ordinal_base_to_cardinal(base : String) -> String {
  match base {
    "fir" => "one"
    "seco" => "two"
    "thi" | "thir" => "three"
    "four" => "four"
    "fif" => "five"
    "six" => "six"
    "seven" => "seven"
    "eigh" | "eigth" => "eight"
    "nin" | "nint" => "nine"
    "ten" => "ten"
    "eleven" => "eleven"
    "twelf" => "twelve"
    "thirteen" => "thirteen"
    "fourteen" => "fourteen"
    "fifteen" => "fifteen"
    "sixteen" => "sixteen"
    "seventeen" => "seventeen"
    "eighteen" => "eighteen"
    "nineteen" => "nineteen"
    "twentie" | "twent" => "twenty"
    "thirtie" | "thirt" => "thirty"
    "fortie" | "fort" => "forty"
    "fiftie" | "fift" => "fifty"
    "sixtie" | "sixt" => "sixty"
    "seventie" | "sevent" => "seventy"
    "eightie" | "eight" => "eighty"
    "ninetie" | "ninet" => "ninety"
    "hundred" => "hundred"
    "thousand" => "thousand"
    _ => base
  }
}

///|
/// Split a string into words by whitespace
fn split_words(s : String) -> Array[String] {
  let result : Array[String] = []
  let chars = s.to_array()
  let mut i = 0
  while i < chars.length() {
    // Skip whitespace
    while i < chars.length() && is_whitespace(chars[i]) {
      i += 1
    }
    if i >= chars.length() {
      break
    }
    let start = i
    while i < chars.length() && !is_whitespace(chars[i]) {
      i += 1
    }
    result.push(chars_to_string(chars, start, i))
  }
  result
}

///|
fn is_whitespace(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Build millis from extracted components with "now" reference for unspecified parts.
/// Per JSONata spec §9.8.4.4:
/// - Unspecified parts to the LEFT of specified parts default to "now" (current timestamp)
/// - Unspecified parts to the RIGHT of specified parts default to 1 (month/day) or 0 (time)
fn build_date_from_components_with_now(
  comps : DateComponents,
  _picture : String,
  now_millis : Double,
) -> Double raise @error.JsonataError {
  // Get current date/time components from now_millis if needed
  let now_dt = if now_millis > 0.0 {
    datetime_from_millis(now_millis, 0)
  } else {
    // Use epoch as fallback
    datetime_from_millis(0.0, 0)
  }

  // Determine the "most significant specified" and "least significant specified"
  // Order: Y M D H m s f (date: Y M D, time: H m s f)
  // For date: year > month > day
  // For time: hour > minute > second > fraction

  // Check what's specified
  let has_date = comps.year is Some(_) ||
    comps.month is Some(_) ||
    comps.day is Some(_) ||
    comps.day_of_year is Some(_)
  let has_time = comps.hour24 is Some(_) ||
    comps.hour12 is Some(_) ||
    comps.minute is Some(_) ||
    comps.second is Some(_) ||
    comps.millis is Some(_)

  // 间隔检测（对齐 JSONata-js parseDateTime D3136）：
  // 按组件显著性顺序（Y M D H m s f）逐项扫描，跟踪 startSpecified/endSpecified。
  // 一旦某项已指定后又遇到未指定项，标记 endSpecified；之后再遇到已指定项则抛 D3136。
  // 使用 day_of_year 时，它替代 M+D，不检查 M/D 间隔。
  let date_comps : Array[Bool] = if comps.day_of_year is Some(_) {
    [comps.year is Some(_), true] // Y, d (day_of_year 替代 M+D)
  } else {
    [comps.year is Some(_), comps.month is Some(_), comps.day is Some(_)] // Y, M, D
  }
  let time_comps : Array[Bool] = [
    comps.hour24 is Some(_) || comps.hour12 is Some(_), // H
    comps.minute is Some(_), // m
    comps.second is Some(_), // s
    comps.millis is Some(_), // f
  ]
  let all_comps : Array[Bool] = date_comps + time_comps
  let mut start_specified = false
  let mut end_specified = false
  for spec in all_comps {
    if spec {
      if end_specified {
        raise @error.runtime_error(
          "D3136: The date/time picture string is missing specifiers required to parse the timestamp",
          code=Some("D3136"),
        )
      }
      start_specified = true
    } else if start_specified {
      end_specified = true
    }
  }
  // 对齐 jsonata-js：dateC (XxwF) 与 dateD (XWF) ISO 周日期格式未实现，抛 D3136。
  // 当前实现仅支持 YMD 与 Yd (day_of_year) 格式，无需在此检测。

  // Apply defaults per JSONata rules:
  // - Before first specified: use now
  // - After last specified: use 1 for date (month/day), 0 for time

  // Year
  let year = match comps.year {
    Some(y) => y
    None =>
      if has_date {
        // Some date component specified but not year: default to now
        now_dt.year()
      } else {
        // No date specified: use now
        now_dt.year()
      }
  }

  // Handle day_of_year first if present (it overrides month/day)
  match comps.day_of_year {
    Some(doy) => {
      let (m, d) = day_of_year_to_month_day(year, doy)
      return millis_from_date_time(
        year,
        m,
        d,
        resolve_hour(comps, has_time, now_dt),
        resolve_minute(comps, has_time),
        resolve_second(comps, has_time),
        resolve_millis(comps),
        resolve_offset(comps),
      )
    }
    None => ()
  }

  // Month
  let month = match comps.month {
    Some(m) => m
    None =>
      if comps.day is Some(_) {
        // Day specified but not month: default to now's month
        now_dt.month()
      } else if has_date {
        // Year specified but not month/day: default month to 1
        1
      } else {
        // No date specified
        now_dt.month()
      }
  }

  // Day
  let day = match comps.day {
    Some(d) => d
    None =>
      if has_date {
        // Year or month specified but not day: default to 1
        1
      } else {
        // No date specified
        now_dt.day()
      }
  }

  millis_from_date_time(
    year,
    month,
    day,
    resolve_hour(comps, has_time, now_dt),
    resolve_minute(comps, has_time),
    resolve_second(comps, has_time),
    resolve_millis(comps),
    resolve_offset(comps),
  )
}

///|
fn resolve_hour(
  comps : DateComponents,
  has_time : Bool,
  now_dt : @time.ZonedDateTime,
) -> Int {
  match comps.hour24 {
    Some(h) => h
    None =>
      match comps.hour12 {
        Some(h12) => {
          let h24 = if h12 == 12 { 0 } else { h12 }
          match comps.am_pm {
            Some(pm) => if pm { h24 + 12 } else { h24 }
            None => h24
          }
        }
        None =>
          if has_time &&
            (
              comps.minute is Some(_) ||
              comps.second is Some(_) ||
              comps.millis is Some(_)
            ) {
            now_dt.hour()
          } else if has_time {
            now_dt.hour()
          } else {
            0
          }
      }
  }
}

///|
fn resolve_minute(comps : DateComponents, has_time : Bool) -> Int {
  match comps.minute {
    Some(m) => m
    None =>
      if comps.second is Some(_) || comps.millis is Some(_) {
        // Not reachable for has_time since minute would be after specified second
        // but keep for completeness
        0
      } else if has_time {
        0
      } else {
        0
      }
  }
}

///|
fn resolve_second(comps : DateComponents, has_time : Bool) -> Int {
  match comps.second {
    Some(s) => s
    None => if comps.millis is Some(_) { 0 } else if has_time { 0 } else { 0 }
  }
}

///|
fn resolve_millis(comps : DateComponents) -> Int {
  match comps.millis {
    Some(ms) => ms
    None => 0
  }
}

///|
fn resolve_offset(comps : DateComponents) -> Int {
  match comps.offset {
    Some(o) => o
    None => 0
  }
}

///|
/// Convert day of year to (month, day)
fn day_of_year_to_month_day(year : Int, doy : Int) -> (Int, Int) {
  let days_in_months = [
    31,
    if is_leap_year(year) {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  let mut remaining = doy
  let mut m = 1
  while m <= 12 {
    if remaining <= days_in_months[m - 1] {
      return (m, remaining)
    }
    remaining -= days_in_months[m - 1]
    m += 1
  }
  (12, 31)
}

///|
fn DateComponents::default() -> DateComponents {
  {
    year: None,
    month: None,
    day: None,
    hour24: None,
    hour12: None,
    minute: None,
    second: None,
    millis: None,
    offset: None,
    day_of_year: None,
    am_pm: None,
    weekday: None,
  }
}

///|
fn parse_timezone_string(s : String) -> Int {
  if s == "" || s == "Z" || s == "z" || s == "0000" {
    return 0
  }
  parse_timezone_offset(s.to_array(), 0)
}

///|
/// 校验字符串是否符合 ISO 8601 格式（对齐 JSONata-js iso8601regex）。
/// regex: ^\d{4}(-[01]\d)?(-[0-3]\d)?(T[0-2]\d:[0-5]\d:[0-5]\d)?(\.\d+)?([+-][0-2]\d:?[0-5]\d|Z)?$
fn is_iso8601(chars : Array[Char]) -> Bool {
  let n = chars.length()
  if n < 4 {
    return false
  }
  // 4-digit year
  for i in 0..<4 {
    if !is_digit(chars[i]) {
      return false
    }
  }
  let mut pos = 4
  // Optional -MM
  if pos < n && chars[pos] == '-' {
    if pos + 2 >= n {
      return false
    }
    if !is_digit(chars[pos + 1]) || !is_digit(chars[pos + 2]) {
      return false
    }
    let mm = (chars[pos + 1].to_int() - 48) * 10 +
      (chars[pos + 2].to_int() - 48)
    if mm < 1 || mm > 12 {
      return false
    }
    pos += 3
    // Optional -DD
    if pos < n && chars[pos] == '-' {
      if pos + 2 >= n {
        return false
      }
      if !is_digit(chars[pos + 1]) || !is_digit(chars[pos + 2]) {
        return false
      }
      let dd = (chars[pos + 1].to_int() - 48) * 10 +
        (chars[pos + 2].to_int() - 48)
      if dd < 1 || dd > 31 {
        return false
      }
      pos += 3
    }
  }
  // Optional Thh:mm:ss
  if pos < n && chars[pos] == 'T' {
    if pos + 8 >= n {
      return false
    }
    if !is_digit(chars[pos + 1]) ||
      !is_digit(chars[pos + 2]) ||
      chars[pos + 3] != ':' ||
      !is_digit(chars[pos + 4]) ||
      !is_digit(chars[pos + 5]) ||
      chars[pos + 6] != ':' ||
      !is_digit(chars[pos + 7]) ||
      !is_digit(chars[pos + 8]) {
      return false
    }
    let hh = (chars[pos + 1].to_int() - 48) * 10 +
      (chars[pos + 2].to_int() - 48)
    let mi = (chars[pos + 4].to_int() - 48) * 10 +
      (chars[pos + 5].to_int() - 48)
    let ss = (chars[pos + 7].to_int() - 48) * 10 +
      (chars[pos + 8].to_int() - 48)
    if hh > 23 || mi > 59 || ss > 59 {
      return false
    }
    pos += 9
    // Optional .fff
    if pos < n && chars[pos] == '.' {
      pos += 1
      if pos >= n || !is_digit(chars[pos]) {
        return false
      }
      while pos < n && is_digit(chars[pos]) {
        pos += 1
      }
    }
    // Optional timezone: Z or +hh:mm or +hhmm or -hh:mm or -hhmm
    if pos < n {
      if chars[pos] == 'Z' {
        pos += 1
      } else if chars[pos] == '+' || chars[pos] == '-' {
        pos += 1
        if pos + 1 >= n || !is_digit(chars[pos]) || !is_digit(chars[pos + 1]) {
          return false
        }
        let tzh = (chars[pos].to_int() - 48) * 10 +
          (chars[pos + 1].to_int() - 48)
        if tzh > 23 {
          return false
        }
        pos += 2
        if pos < n && chars[pos] == ':' {
          pos += 1
        }
        if pos + 1 < n && is_digit(chars[pos]) && is_digit(chars[pos + 1]) {
          let tzm = (chars[pos].to_int() - 48) * 10 +
            (chars[pos + 1].to_int() - 48)
          if tzm > 59 {
            return false
          }
          pos += 2
        }
      }
    }
  }
  pos == n
}

///|
fn parse_iso_millis(s : String) -> Double? raise @error.JsonataError {
  let chars = s.to_array()
  // ISO 8601 严格校验，对齐 JSONata-js iso8601regex:
  // ^\d{4}(-[01]\d)?(-[0-3]\d)?(T[0-2]\d:[0-5]\d:[0-5]\d)?(\.\d+)?([+-][0-2]\d:?[0-5]\d|Z)?$
  // 不匹配时抛 D3110。
  if !is_iso8601(chars) {
    raise @error.runtime_error(
      "D3110: The argument of the toMillis function must be an ISO 8601 formatted timestamp. Given \{s}",
      code=Some("D3110"),
    )
  }
  if chars.length() == 4 && all_digits(chars, 0, 4) {
    return Some(millis_from_date(parse_digits(chars, 0, 4), 1, 1))
  }
  if chars.length() < 10 {
    // 4-digit year only (already validated by is_iso8601)
    return Some(millis_from_date(parse_digits(chars, 0, 4), 1, 1))
  }
  let year = parse_digits(chars, 0, 4)
  let month = parse_digits(chars, 5, 7)
  let day = parse_digits(chars, 8, 10)
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut millis = 0
  let mut offset = 0
  if chars.length() > 10 {
    hour = parse_digits(chars, 11, 13)
    minute = parse_digits(chars, 14, 16)
    second = parse_digits(chars, 17, 19)
    let mut pos = 19
    if pos < chars.length() && chars[pos] == '.' {
      pos += 1
      let start = pos
      while pos < chars.length() && is_digit(chars[pos]) {
        pos += 1
      }
      millis = parse_fraction_millis(chars, start, pos)
    }
    if pos < chars.length() {
      offset = parse_timezone_offset(chars, pos)
    }
  }
  let zone = if offset == 0 {
    @time.utc_zone
  } else {
    @time.fixed_zone(offset_id(offset), offset) catch {
      _ => @time.utc_zone
    }
  }
  let dt = @time.ZonedDateTime::of(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    nanosecond=millis * 1_000_000,
    zone~,
  ) catch {
    _ =>
      raise @error.runtime_error(
        "D3110: The argument of the toMillis function must be an ISO 8601 formatted timestamp. Given \{s}",
        code=Some("D3110"),
      )
  }
  Some(dt.to_unix_second().to_double() * 1000.0 + millis.to_double())
}

///|
fn _parse_compact_date(
  s : String,
  has_day~ : Bool,
  has_time~ : Bool,
) -> Double raise @error.JsonataError {
  let chars = s.to_array()
  let min_len = if has_time { 14 } else if has_day { 8 } else { 6 }
  if chars.length() < min_len || !all_digits(chars, 0, min_len) {
    raise @error.runtime_error("invalid date time")
  }
  let year = parse_digits(chars, 0, 4)
  let month = parse_digits(chars, 4, 6)
  let day = if has_day { parse_digits(chars, 6, 8) } else { 1 }
  let hour = if has_time { parse_digits(chars, 8, 10) } else { 0 }
  let minute = if has_time { parse_digits(chars, 10, 12) } else { 0 }
  let second = if has_time { parse_digits(chars, 12, 14) } else { 0 }
  millis_from_date_time(year, month, day, hour, minute, second, 0, 0)
}

///|
fn millis_from_date(
  year : Int,
  month : Int,
  day : Int,
) -> Double raise @error.JsonataError {
  millis_from_date_time(year, month, day, 0, 0, 0, 0, 0)
}

///|
fn millis_from_date_time(
  year : Int,
  month : Int,
  day : Int,
  hour : Int,
  minute : Int,
  second : Int,
  millis : Int,
  offset : Int,
) -> Double raise @error.JsonataError {
  let zone = if offset == 0 {
    @time.utc_zone
  } else {
    @time.fixed_zone(offset_id(offset), offset) catch {
      _ => @time.utc_zone
    }
  }
  let dt = @time.ZonedDateTime::of(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    nanosecond=millis * 1_000_000,
    zone~,
  ) catch {
    _ => raise @error.runtime_error("invalid date time")
  }
  dt.to_unix_second().to_double() * 1000.0 + millis.to_double()
}

///|
fn _parse_slash_date(s : String) -> Double raise @error.JsonataError {
  let chars = s.to_array()
  let slash1 = find_char(chars, '/', 0)
  let slash2 = find_char(chars, '/', slash1 + 1)
  if slash1 < 0 || slash2 < 0 {
    // parse_iso_millis 现在返回 Double?；非 ISO 8601 会抛 D3110
    match parse_iso_millis(s) {
      Some(m) => return m
      None => raise @error.runtime_error("invalid date time")
    }
  }
  let day = parse_digits(chars, 0, slash1)
  let month = parse_digits(chars, slash1 + 1, slash2)
  let year = parse_digits(chars, slash2 + 1, chars.length())
  let dt = @time.ZonedDateTime::of(year, month, day) catch {
    _ => raise @error.runtime_error("invalid date")
  }
  dt.to_unix_second().to_double() * 1000.0
}

///|
fn parse_timezone_offset(chars : Array[Char], start : Int) -> Int {
  if chars[start] == 'Z' || chars[start] == 'z' {
    return 0
  }
  if chars[start] != '+' && chars[start] != '-' {
    return 0
  }
  let sign = if chars[start] == '-' { -1 } else { 1 }
  let hour = parse_digits(chars, start + 1, start + 3)
  let minute = if start + 3 < chars.length() && chars[start + 3] == ':' {
    parse_digits(chars, start + 4, start + 6)
  } else {
    parse_digits(chars, start + 3, start + 5)
  }
  sign * (hour * 3600 + minute * 60)
}

///|
fn parse_fraction_millis(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut value = 0
  let mut i = start
  let mut count = 0
  while i < end && count < 3 {
    value = value * 10 + digit_value(chars[i])
    i += 1
    count += 1
  }
  while count < 3 {
    value *= 10
    count += 1
  }
  value
}

///|
fn parse_digits(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut value = 0
  let mut i = start
  while i < end && i < chars.length() {
    value = value * 10 + digit_value(chars[i])
    i += 1
  }
  value
}

///|
fn parse_int_strict(s : String) -> Int raise @error.JsonataError {
  @string.parse_int(s) catch {
    _ => raise @error.runtime_error("invalid number")
  }
}

///|
fn all_digits(chars : Array[Char], start : Int, end : Int) -> Bool {
  if end > chars.length() {
    return false
  }
  let mut i = start
  while i < end {
    if !is_digit(chars[i]) {
      return false
    }
    i += 1
  }
  true
}

///|
fn digit_value(c : Char) -> Int {
  c.to_int() - '0'.to_int()
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn find_char(chars : Array[Char], target : Char, start : Int) -> Int {
  let mut i = start
  while i < chars.length() {
    if chars[i] == target {
      return i
    }
    i += 1
  }
  -1
}

///|
fn chars_to_string(chars : Array[Char], start : Int, end : Int) -> String {
  let out = StringBuilder::new()
  let mut i = start
  while i < end {
    out.write_char(chars[i])
    i += 1
  }
  out.to_string()
}

///|
fn group_thousands(n : Int) -> String {
  let s = n.to_string()
  let out = StringBuilder::new()
  let chars = s.to_array()
  for i, c in chars {
    if i > 0 && (chars.length() - i) % 3 == 0 {
      out.write_char(',')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
fn hour12(hour : Int) -> Int {
  let h = hour % 12
  if h == 0 {
    12
  } else {
    h
  }
}

///|
fn month_name(month : Int, style : String) -> String {
  let name = match month {
    1 => "January"
    2 => "February"
    3 => "March"
    4 => "April"
    5 => "May"
    6 => "June"
    7 => "July"
    8 => "August"
    9 => "September"
    10 => "October"
    11 => "November"
    12 => "December"
    _ => ""
  }
  match style {
    "upper" => name.to_upper()
    "lower" => name.to_lower()
    _ => name
  }
}

///|
fn weekday_number(dt : @time.ZonedDateTime) -> Int {
  match dt.weekday() {
    @time.Weekday::Monday => 1
    @time.Weekday::Tuesday => 2
    @time.Weekday::Wednesday => 3
    @time.Weekday::Thursday => 4
    @time.Weekday::Friday => 5
    @time.Weekday::Saturday => 6
    @time.Weekday::Sunday => 7
  }
}

///|
fn iso_week(dt : @time.ZonedDateTime) -> Int {
  let week = (dt.ordinal() - weekday_number(dt) + 10) / 7
  if week < 1 {
    weeks_in_iso_year(dt.year() - 1)
  } else if week > weeks_in_iso_year(dt.year()) {
    1
  } else {
    week
  }
}

///|
fn iso_week_year(dt : @time.ZonedDateTime) -> Int {
  let week = (dt.ordinal() - weekday_number(dt) + 10) / 7
  if week < 1 {
    dt.year() - 1
  } else if week > weeks_in_iso_year(dt.year()) {
    dt.year() + 1
  } else {
    dt.year()
  }
}

///|
fn weeks_in_iso_year(year : Int) -> Int {
  let jan1 = @time.ZonedDateTime::of(year, 1, 1) catch { _ => return 52 }
  let jan1_weekday = weekday_number(jan1)
  if jan1_weekday == 4 || (jan1_weekday == 3 && is_leap_year(year)) {
    53
  } else {
    52
  }
}

///|
fn is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
/// 月内周序号（ISO 周，周一开始，含首周四的为第 1 周）。
fn week_in_month(dt : @time.ZonedDateTime) -> Int raise @error.JsonataError {
  let year = dt.year()
  let month = dt.month()
  let start_w1 = start_of_first_week(year, month)
  let current = dt.to_unix_second() * 1000L
  let week = delta_weeks(start_w1, current)
  if week > 4 {
    let (ny, nm) = next_month(year, month)
    let start_next = start_of_first_week(ny, nm)
    if current >= start_next {
      return 1
    }
  } else if week < 1 {
    let (py, pm) = prev_month(year, month)
    let start_prev = start_of_first_week(py, pm)
    return delta_weeks(start_prev, current)
  }
  week
}

///|
/// 周编号月份：`[xNn]` — 当日期属于 ISO 月首周之前/之后月时返回对应月份。
fn week_numbering_month(
  dt : @time.ZonedDateTime,
) -> Int raise @error.JsonataError {
  let year = dt.year()
  let month = dt.month()
  let start_iso = start_of_first_week(year, month)
  let current = dt.to_unix_second() * 1000L
  if current < start_iso {
    let (_, pm) = prev_month(year, month)
    pm
  } else {
    let (ny, nm) = next_month(year, month)
    let start_next = start_of_first_week(ny, nm)
    if current >= start_next {
      nm
    } else {
      month
    }
  }
}

///|
/// 月首周起始（周一开始，含月首周四）：毫秒级 UTC 时间戳。
fn start_of_first_week(
  year : Int,
  month : Int,
) -> Int64 raise @error.JsonataError {
  let dt = @time.ZonedDateTime::of(year, month, 1) catch {
    _ => raise @error.runtime_error("invalid date for start_of_first_week")
  }
  let dow = weekday_number(dt) // 1=Mon..7=Sun
  let millis_in_day : Int64 = 86_400_000L
  let jan1_millis = dt.to_unix_second() * 1000L
  if dow > 4 {
    jan1_millis + (8L - dow.to_int64()) * millis_in_day
  } else {
    jan1_millis - (dow.to_int64() - 1L) * millis_in_day
  }
}

///|
/// 周数差（end - start）÷ 7 天 + 1，float 除法以正确处理跨月边界。
fn delta_weeks(start : Int64, end : Int64) -> Int {
  let diff = (end - start).to_double()
  let millis_in_week = 604800000.0
  (diff / millis_in_week + 1.0).floor().to_int()
}

///|
fn next_month(year : Int, month : Int) -> (Int, Int) {
  if month == 12 {
    (year + 1, 1)
  } else {
    (year, month + 1)
  }
}

///|
fn prev_month(year : Int, month : Int) -> (Int, Int) {
  if month == 1 {
    (year - 1, 12)
  } else {
    (year, month - 1)
  }
}

///|
/// 从 Y,n 格式中提取年份宽度（仅当 marker 无显式位数模式时）。
fn picture_year_digits(marker : String) -> Int {
  let comma = marker.find(",")
  match comma {
    Some(pos) =>
      // 仅在 [Y,n] 无显式位数时截断
      if pos == 1 {
        let mut end = pos + 1
        while end < marker.length() &&
              marker.get_char(end) >= Some('0') &&
              marker.get_char(end) <= Some('9') {
          end += 1
        }
        let digits_str = marker[pos + 1:end].to_owned()
        try_parse_int(digits_str).unwrap_or(0)
      } else {
        0
      }
    None => 0
  }
}

///|
fn pow10(n : Int) -> Int {
  let mut r = 1
  for i = 0; i < n; i = i + 1 {
    r = r * 10
  }
  r
}

///|
fn try_parse_int(s : String) -> Int? {
  Some(parse_int_strict(s)) catch {
    _ => None
  }
}

///|
fn weekday_name(dt : @time.ZonedDateTime, style : String) -> String {
  let name = match dt.weekday() {
    @time.Weekday::Monday => "Monday"
    @time.Weekday::Tuesday => "Tuesday"
    @time.Weekday::Wednesday => "Wednesday"
    @time.Weekday::Thursday => "Thursday"
    @time.Weekday::Friday => "Friday"
    @time.Weekday::Saturday => "Saturday"
    @time.Weekday::Sunday => "Sunday"
  }
  match style {
    "upper" => name.to_upper()
    "lower" => name.to_lower()
    _ => name
  }
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

///|
fn pad3(n : Int) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

///|
fn pad4(n : Int) -> String {
  if n < 10 {
    "000\{n}"
  } else if n < 100 {
    "00\{n}"
  } else if n < 1000 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

///|
fn offset_id(offset_seconds : Int) -> String {
  if offset_seconds == 0 {
    "Z"
  } else {
    let sign = if offset_seconds < 0 { "-" } else { "+" }
    let abs = if offset_seconds < 0 { -offset_seconds } else { offset_seconds }
    "\{sign}\{pad2(abs / 3600)}:\{pad2(abs % 3600 / 60)}"
  }
}

///|
fn offset_colon(offset_seconds : Int) -> String {
  let sign = if offset_seconds < 0 { "-" } else { "+" }
  let abs = if offset_seconds < 0 { -offset_seconds } else { offset_seconds }
  "\{sign}\{pad2(abs / 3600)}:\{pad2(abs % 3600 / 60)}"
}

///|
fn offset_digits(offset_seconds : Int) -> String {
  let sign = if offset_seconds < 0 { "-" } else { "+" }
  let abs = if offset_seconds < 0 { -offset_seconds } else { offset_seconds }
  "\{sign}\{pad2(abs / 3600)}\{pad2(abs % 3600 / 60)}"
}

///|
fn offset_compact(offset_seconds : Int) -> String {
  let sign = if offset_seconds < 0 { "-" } else { "+" }
  let abs = if offset_seconds < 0 { -offset_seconds } else { offset_seconds }
  let hours = abs / 3600
  let minutes = abs % 3600 / 60
  if minutes == 0 {
    "\{sign}\{hours}"
  } else {
    "\{sign}\{hours}:\{pad2(minutes)}"
  }
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
  let lookup : Map[Char, Int] = Map([])
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
    result.write_char(Int::unsafe_to_char((n >> 16) & 0xFF))
    match c2_val {
      Some(c2) => {
        let n2 = n | (c2 << 6)
        result.write_char(Int::unsafe_to_char((n2 >> 8) & 0xFF))
        match c3_val {
          Some(c3) => {
            let n3 = n2 | c3
            result.write_char(Int::unsafe_to_char(n3 & 0xFF))
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

///|
/// URL 编码模式。
priv enum UrlMode {
  FullUrl // 对整个 URL 编码，保留 :/?#[]@!$&'()*+,;=
  Component // 对组件编码，不保留任何保留字符
}

///|
/// 百分号编码，按模式选择保留字符集。
fn percent_encode(s : String, mode : UrlMode) -> String {
  let reserved = match mode {
    UrlMode::FullUrl => ":/?#[]@!$&'()*+,;="
    UrlMode::Component => ""
  }
  let result = StringBuilder::new()
  for c in s {
    let code = c.to_int()
    if (code >= 0x41 && code <= 0x5A) || // A-Z
      (code >= 0x61 && code <= 0x7A) || // a-z
      (code >= 0x30 && code <= 0x39) || // 0-9
      c == '-' ||
      c == '_' ||
      c == '.' ||
      c == '~' ||
      reserved.contains_char(c) {
      result.write_char(c)
    } else {
      for byte in utf8_bytes(c) {
        result.write_char('%')
        result.write_string(hex_byte(byte))
      }
    }
  }
  result.to_string()
}

///|
/// 百分号解码：将 %XX 序列还原为 UTF-8 字符串，并对最终字节序列做严格 UTF-8
/// 校验。遇非法 continuation byte 或 truncated 多字节序列时抛 D3140，对齐
/// jsonata-js `$decodeUrl` 对 malformed URL 的处理（function-decodeUrl/case002）。
///
/// `fn_name` 用于错误消息，区分 `$decodeUrl` 与 `$decodeUrlComponent`。
fn percent_decode_strict(
  s : String,
  fn_name : String,
) -> String raise @error.JsonataError {
  let chars = s.to_array()
  let bytes : Array[Int] = []
  let mut i = 0
  // %XX 解码阶段：严格按 2 位十六进制解析，遇到不完整的 %XX（如 `%A` 或 `%G0`）
  // 时直接把 `%` 当字面量处理（对齐 jsonata-js `decodeURI` 的宽容行为）。
  while i < chars.length() {
    if chars[i] == '%' && i + 2 < chars.length() {
      let hi = hex_digit(chars[i + 1])
      let lo = hex_digit(chars[i + 2])
      if hi >= 0 && lo >= 0 {
        bytes.push((hi << 4) | lo)
        i += 3
        continue
      }
    }
    // 非百分号字符直接转为 UTF-8 字节再追加
    for byte in utf8_bytes(chars[i]) {
      bytes.push(byte)
    }
    i += 1
  }
  utf8_decode_strict(bytes, fn_name, s)
}

///|
/// 将 UTF-8 字节序列解码为字符串，对非法字节序列抛 D3140。
///
/// 严格校验规则（对齐 WHATWG / RFC 3629）：
/// - 多字节序列的每个 continuation byte 必须在 0x80–0xBF 范围
/// - 0xC0/0xC1 视为非法（应使用单字节 ASCII 表示）
/// - 0xE0 的次字节必须 ≥ 0xA0；0xED 的次字节必须 ≤ 0x9F（拒绝 surrogate）
/// - 0xF0 的次字节必须 ≥ 0x90；0xF4 的次字节必须 ≤ 0x8F（拒绝 > U+10FFFF）
fn utf8_decode_strict(
  bytes : Array[Int],
  fn_name : String,
  raw_input : String,
) -> String raise @error.JsonataError {
  let result = StringBuilder::new()
  let n = bytes.length()
  let mut i = 0
  let fail = fn() -> String raise @error.JsonataError {
    raise @error.runtime_error(
      "D3140: Malformed URL passed to $\{fn_name}(): \"\{raw_input}\"",
      code=Some("D3140"),
    )
  }
  while i < n {
    let b = bytes[i]
    if b < 0x80 {
      result.write_char(Int::unsafe_to_char(b))
      i += 1
    } else if b < 0xC2 {
      // 0x80-0xBF: 孤立 continuation byte；0xC0/0xC1: overlong 2-byte
      return fail()
    } else if b < 0xE0 {
      if i + 1 >= n || (bytes[i + 1] & 0xC0) != 0x80 {
        return fail()
      }
      let c = ((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F)
      result.write_char(Int::unsafe_to_char(c))
      i += 2
    } else if b < 0xF0 {
      if i + 2 >= n {
        return fail()
      }
      let b1 = bytes[i + 1]
      let b2 = bytes[i + 2]
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
        return fail()
      }
      // 0xE0 次字节必须 ≥ 0xA0（拒绝 overlong 3-byte）
      // 0xED 次字节必须 ≤ 0x9F（拒绝 surrogate U+D800–U+DFFF）
      if (b == 0xE0 && b1 < 0xA0) || (b == 0xED && b1 > 0x9F) {
        return fail()
      }
      let c = ((b & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      result.write_char(Int::unsafe_to_char(c))
      i += 3
    } else if b < 0xF5 {
      if i + 3 >= n {
        return fail()
      }
      let b1 = bytes[i + 1]
      let b2 = bytes[i + 2]
      let b3 = bytes[i + 3]
      if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        return fail()
      }
      // 0xF0 次字节必须 ≥ 0x90（拒绝 overlong 4-byte）
      // 0xF4 次字节必须 ≤ 0x8F（拒绝 > U+10FFFF）
      if (b == 0xF0 && b1 < 0x90) || (b == 0xF4 && b1 > 0x8F) {
        return fail()
      }
      let c = ((b & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      result.write_char(Int::unsafe_to_char(c))
      i += 4
    } else {
      // 0xF5-0xFF: 非法 leading byte
      return fail()
    }
  }
  result.to_string()
}

///|
/// 检测字符串中是否含 lone surrogate（U+D800–U+DFFF），若有则抛 D3140。
///
/// 对齐 jsonata-js `$encodeUrl`/`$encodeUrlComponent` 对 lone surrogate 的拒绝
/// 行为（function-encodeUrl/case002 / function-encodeUrlComponent/case002）。
/// 错误消息包含 functionName 与原值，使 audit 脚本可对这两个字段做子串匹配。
fn reject_url_surrogate(
  s : String,
  fn_name : String,
) -> Unit raise @error.JsonataError {
  for c in s {
    let code = c.to_int()
    if code >= 0xD800 && code <= 0xDFFF {
      raise @error.runtime_error(
        "D3140: Malformed URL passed to $\{fn_name}(): \"\{s}\"",
        code=Some("D3140"),
      )
    }
  }
}

///|
/// 将字符编码为 UTF-8 字节序列。
fn utf8_bytes(c : Char) -> Array[Int] {
  let code = c.to_int()
  if code < 0x80 {
    [code]
  } else if code < 0x800 {
    [0xC0 | (code >> 6), 0x80 | (code & 0x3F)]
  } else if code < 0x10000 {
    [0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F)]
  } else {
    [
      0xF0 | (code >> 18),
      0x80 | ((code >> 12) & 0x3F),
      0x80 | ((code >> 6) & 0x3F),
      0x80 | (code & 0x3F),
    ]
  }
}

///|
/// 将字节转为两位十六进制字符串（大写）。
fn hex_byte(b : Int) -> String {
  let hi = (b >> 4) & 0xF
  let lo = b & 0xF
  hex_char(hi) + hex_char(lo)
}

///|
/// 半字节转十六进制字符。
fn hex_char(n : Int) -> String {
  match n {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    15 => "F"
    _ => "0"
  }
}

///|
/// 十六进制字符转数字。
fn hex_digit(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else {
    -1
  }
}
