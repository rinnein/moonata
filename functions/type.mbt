///|
fn register_type_functions(ctx : @value.EvalContext) -> Unit {
  // $string
  register(ctx, "string", arity=0, invoke=fn(args, ctx) {
    let value = if args.length() == 0 { ctx.current() } else { args[0] }
    let pretty = args.length() > 1 && value_to_bool(args[1])
    @value.JsonataValue::Json(Json::string(jsonata_string(value, pretty)))
  })
  // $number
  register(ctx, "number", arity=1, signature=Some("j"), invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(_, ..)) => args[0]
      @value.JsonataValue::Json(Json::String(s)) =>
        match parse_number_literal(s) {
          Some(n) => @value.JsonataValue::Json(Json::number(n))
          None => @value.JsonataValue::Undefined
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
      @value.JsonataValue::Regex(_) => "function"
      @value.JsonataValue::Sequence(_) => "array"
    }
    @value.JsonataValue::Json(Json::string(type_name))
  })
}

///|
fn jsonata_string(value : @value.JsonataValue, pretty : Bool) -> String {
  match value {
    @value.JsonataValue::Json(Json::String(s)) => s
    @value.JsonataValue::Json(Json::Number(n, ..)) => jsonata_string_number(n)
    @value.JsonataValue::Json(Json::True) => "true"
    @value.JsonataValue::Json(Json::False) => "false"
    @value.JsonataValue::Json(Json::Null) => "null"
    @value.JsonataValue::Undefined => ""
    @value.JsonataValue::Func(_) => ""
    @value.JsonataValue::Regex(_) => ""
    _ => {
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
      let out : Map[String, Json] = {}
      for entry in map {
        let (key, item) = entry
        out[key] = jsonata_string_json(@value.JsonataValue::Json(item))
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
  register(ctx, "eval", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
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
  register(ctx, "assert", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
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
      format_date_picture(millis, value_to_str(args[1]), offset)
    } else {
      format_iso_time(millis)
    }
    @value.JsonataValue::Json(Json::string(result))
  })
  // $toMillis — ISO 8601 字符串转毫秒数
  register(ctx, "toMillis", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let s = value_to_str(args[0])
    let millis = if args.length() > 1 {
      parse_date_picture(s, value_to_str(args[1]))
    } else {
      parse_iso_millis(s)
    }
    @value.JsonataValue::Json(Json::number(millis))
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
      format_date_picture(millis, value_to_str(args[1]), offset)
    } else {
      format_iso_time(millis)
    }
    @value.JsonataValue::Json(Json::string(result))
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
  register(ctx, "error", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    raise @error.runtime_error(value_to_str(args[0]))
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
fn format_date_picture(
  millis : Double,
  picture : String,
  offset_seconds : Int,
) -> String raise @error.JsonataError {
  let dt = datetime_from_millis(millis, offset_seconds)
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
        if j < chars.length() {
          out.write_string(
            format_date_marker(
              dt,
              chars_to_string(chars, i + 1, j),
              offset_seconds,
            ),
          )
          i = j + 1
        } else {
          out.write_char(chars[i])
          i += 1
        }
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
fn format_date_marker(
  dt : @time.ZonedDateTime,
  marker : String,
  offset_seconds : Int,
) -> String {
  let marker = normalize_marker(marker)
  match marker {
    "Y" => dt.year().to_string()
    "Y0001" => pad4(dt.year())
    "Y9,999,*" => group_thousands(dt.year())
    "X0001" => pad4(iso_week_year(dt))
    "M" | "M#1" => dt.month().to_string()
    "M01" => pad2(dt.month())
    "M1,2" => pad2(dt.month())
    "MNn" => month_name(dt.month(), "title")
    "MN" => month_name(dt.month(), "upper")
    "MNn,3-3" =>
      month_name(dt.month(), "title").unsafe_substring(start=0, end=3)
    "D" | "D#1" => dt.day().to_string()
    "D01" => pad2(dt.day())
    "D#1,2" | "D1" => pad2(dt.day())
    "D1o" => "\{dt.day()}\{ordinal_suffix(dt.day())}"
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
    "W" => iso_week(dt).to_string()
    "W01" => pad2(iso_week(dt))
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
    _ =>
      if marker.length() > 0 && marker.get_char(0) == Some('Y') {
        if marker.contains(",2-2") {
          pad2(dt.year() % 100)
        } else {
          dt.year().to_string()
        }
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
fn parse_date_picture(
  s : String,
  picture : String,
) -> Double raise @error.JsonataError {
  match picture {
    "[Y1]" => millis_from_date(parse_int_strict(s), 1, 1)
    "[Y0001]-[M01]-[D01]" => parse_iso_millis(s)
    "[Y]-[M]-[D]" => parse_iso_millis(s)
    "[Y0001][M01]" => parse_compact_date(s, has_day=false, has_time=false)
    "[Y,*-4][M01]" => parse_compact_date(s, has_day=false, has_time=false)
    "[Y0001][M01][D01]" => parse_compact_date(s, has_day=true, has_time=false)
    "[Y0000][M00][D00][H00][m00][s00]" =>
      parse_compact_date(s, has_day=true, has_time=true)
    "[D#1]/[M#1]/[Y0001]" => parse_slash_date(s)
    _ => parse_iso_millis(s)
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
fn parse_iso_millis(s : String) -> Double raise @error.JsonataError {
  let chars = s.to_array()
  if chars.length() == 4 && all_digits(chars, 0, 4) {
    return millis_from_date(parse_digits(chars, 0, 4), 1, 1)
  }
  if chars.length() < 10 {
    return @strconv.from_str(s) catch { _ => 0.0 }
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
    _ => raise @error.runtime_error("invalid date time")
  }
  dt.to_unix_second().to_double() * 1000.0 + millis.to_double()
}

///|
fn parse_compact_date(
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
fn parse_slash_date(s : String) -> Double raise @error.JsonataError {
  let chars = s.to_array()
  let slash1 = find_char(chars, '/', 0)
  let slash2 = find_char(chars, '/', slash1 + 1)
  if slash1 < 0 || slash2 < 0 {
    return parse_iso_millis(s)
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
