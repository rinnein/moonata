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
    match args[0] {
      @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
      _ => {
        let s = value_to_str(args[0])
        let millis = if args.length() > 1 {
          parse_date_picture(s, value_to_str(args[1]))
        } else {
          parse_iso_millis(s)
        }
        @value.JsonataValue::Json(Json::number(millis))
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
fn parse_date_picture(
  s : String,
  picture : String,
) -> Double raise @error.JsonataError {
  let segments = split_picture(picture)
  let comps = extract_date_components(s, segments)
  build_date_from_components(comps, picture)
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
) -> DateComponents raise @error.JsonataError {
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
            raise @error.runtime_error(
              "D3110: date/time string does not match picture format",
            )
          }
        } else {
          let mut matched = true
          for j in 0..<lit_chars.length() {
            if input_chars[pos + j] != lit_chars[j] {
              matched = false
              break
            }
          }
          if not(matched) {
            raise @error.runtime_error(
              "D3110: date/time string does not match picture format",
            )
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
        let value = chars_to_string(input_chars, pos, end_pos)
        // Parse value according to marker type
        extract_marker_value(comps, marker, value)
        pos = end_pos
      }
    }
  }
  // If we haven't consumed all input and last segment was not a marker, error
  if pos < input_chars.length() {
    raise @error.runtime_error("D3110: trailing characters in date/time string")
  }
  comps
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
      // Y0001 -> 4, Y00 -> 2, Y0000 -> 4, Y,*-4 -> variable, Y -> variable, Y1 -> variable
      // YI/Yi -> roman numeral, Yw -> word year
      let has_comma = marker.contains(",")
      let has_I = marker.contains("I")
      let has_i = marker.contains("i")
      let has_w = marker.contains("w")
      if has_comma || has_I || has_i || has_w {
        None
      } else if marker == "Y" || marker == "Y1" {
        None
      } else {
        // Count digit placeholders: Y0001 has 4 digits (0,0,0,1)
        Some(marker_placeholder_count(marker))
      }
    }
    'M' =>
      if marker.starts_with("MN") {
        None // Named month
      } else if marker.contains("i") ||
        marker.contains("A") ||
        marker.contains("a") {
        None // Roman numeral or abbreviated
        // M01 -> 2, M#1 -> variable, M -> variable
      } else if marker.contains("#") || marker == "M" {
        None
      } else {
        Some(marker_placeholder_count(marker))
      }
    'D' => {
      let has_o = marker.contains("o")
      let has_Ww = marker.contains("Ww")
      let starts_Dw = marker.starts_with("Dw")
      let has_a = marker.contains("a")
      let has_A = marker.contains("A")
      if has_o || has_Ww || starts_Dw || has_a || has_A {
        None // Ordinal, word, or abbreviated
      } else if marker.contains("#") || marker == "D" {
        None
      } else {
        Some(marker_placeholder_count(marker))
      }
    }
    'H' | 'h' =>
      if marker == "H" || marker == "h" || marker.contains("#") {
        None
      } else {
        Some(marker_placeholder_count(marker))
      }
    'm' =>
      if marker == "m" || marker.contains("#") {
        None
      } else {
        Some(marker_placeholder_count(marker))
      }
    's' =>
      if marker == "s" || marker.contains("#") {
        None
      } else {
        Some(marker_placeholder_count(marker))
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
        Some(marker_placeholder_count(marker))
      }
    'F' => None // Named or numeric weekday
    'Z' | 'z' => None // Variable timezone
    'P' => None // AM/PM
    'X' | 'x' | 'W' | 'w' => None
    _ => None
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
  marker.starts_with("Z0") ||
  marker.starts_with("z") ||
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
      if marker.contains("I") || marker.contains("i") {
        // Roman numeral year
        comps.year = Some(parse_roman_numeral(value))
      } else if marker.contains("w") {
        // Word year
        comps.year = Some(parse_word_number(value))
      } else {
        comps.year = parse_int_opt(value)
        if comps.year.is_empty() {
          raise @error.runtime_error("D3110: invalid year")
        }
      }
    'M' =>
      if marker.starts_with("MN") {
        // Named month
        let m = parse_month_name(value)
        comps.month = Some(m)
      } else if marker.contains("i") {
        // Roman numeral month
        comps.month = Some(parse_roman_numeral(value))
      } else {
        comps.month = parse_int_opt(value)
        if comps.month.is_empty() {
          raise @error.runtime_error("D3110: invalid month")
        }
      }
    'D' =>
      if marker.contains("Wwo") {
        // Word-ordinal day like "Twelfth", "Twenty-first"
        let d = parse_word_ordinal(value)
        comps.day = Some(d)
      } else if marker.starts_with("Dw") {
        // Word day like "twenty-seven", "twenty-seventh"
        let d = parse_word_number(value)
        comps.day = Some(d)
      } else if marker.contains("o") {
        // Numeric ordinal day like "27th"
        let d = parse_ordinal_day(value)
        comps.day = Some(d)
      } else {
        comps.day = parse_int_opt(value)
        if comps.day.is_empty() {
          raise @error.runtime_error("D3110: invalid day")
        }
      }
    'F' =>
      // Weekday - parse name or number
      if marker.starts_with("FN") {
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
      if comps.hour24.is_empty() {
        raise @error.runtime_error("D3110: invalid hour")
      }
    }
    'h' => {
      comps.hour12 = parse_int_opt(value)
      if comps.hour12.is_empty() {
        raise @error.runtime_error("D3110: invalid hour")
      }
    }
    'm' => {
      comps.minute = parse_int_opt(value)
      if comps.minute.is_empty() {
        raise @error.runtime_error("D3110: invalid minute")
      }
    }
    's' => {
      comps.second = parse_int_opt(value)
      if comps.second.is_empty() {
        raise @error.runtime_error("D3110: invalid second")
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
        if comps.day_of_year.is_empty() {
          raise @error.runtime_error("D3110: invalid day of year")
        }
      }
    'Z' | 'z' =>
      if value != "" {
        comps.offset = Some(parse_picture_timezone(value))
      }
    'P' => comps.am_pm = Some(parse_am_pm(value))
    'X' => raise @error.runtime_error("D3136: unsupported picture component")
    'x' => raise @error.runtime_error("D3136: unsupported picture component")
    'W' => raise @error.runtime_error("D3136: unsupported picture component")
    'w' => raise @error.runtime_error("D3136: unsupported picture component")
    'C' | 'E' => ()
    _ =>
      // Try to handle Y-variant markers that start differently
      if marker.contains(",2-2") {
        comps.year = parse_int_opt(value)
      } else {
        raise @error.runtime_error("D3136: unsupported picture component")
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
    if not(is_digit(chars[i])) {
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
/// Parse ordinal day like "1st", "21st", "2nd", "3rd", "4th"
fn parse_ordinal_day(s : String) -> Int raise @error.JsonataError {
  // Strip ordinal suffix
  let trimmed = s.trim().to_string()
  if trimmed.length() < 2 {
    raise @error.runtime_error("D3110: invalid ordinal")
  }
  let mut num_end = trimmed.length()
  // Remove trailing ordinal suffix
  let has_st = trimmed.ends_with("st")
  let has_nd = trimmed.ends_with("nd")
  let has_rd = trimmed.ends_with("rd")
  let has_th = trimmed.ends_with("th")
  if has_st || has_nd || has_rd || has_th {
    num_end -= 2
  }
  let num_part = trimmed.substring(start=0, end=num_end).to_string()
  match parse_int_opt(num_part) {
    Some(n) => n
    None => raise @error.runtime_error("D3110: invalid ordinal day")
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
    _ => raise @error.runtime_error("D3110: invalid month name")
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
    _ => raise @error.runtime_error("D3110: invalid weekday name")
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
  let lower = s.trim().to_string().to_lower()
  if lower == "pm" || lower == "p.m." || lower == "p" {
    true
  } else {
    false
  }
}

///|
/// Parse timezone from picture-extracted value
fn parse_picture_timezone(s : String) -> Int {
  let trimmed = s.trim().to_string()
  if trimmed == "" || trimmed == "Z" || trimmed == "z" {
    return 0
  }
  // Handle GMT±HH:MM or GMT±HHMM or GMT±H
  if trimmed.starts_with("GMT") {
    let rest = trimmed
      .substring(start=3, end=trimmed.length())
      .trim()
      .to_string()
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
  let upper = s.trim().to_string().to_upper()
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
      _ => raise @error.runtime_error("D3110: invalid roman numeral")
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
fn parse_word_number(s : String) -> Int raise @error.JsonataError {
  // Clean the input: remove commas, hyphens, "and"
  let lower = s.to_lower()
  let trimmed = lower.trim()
  let cleaned = trimmed.to_string()
  // Remove commas, hyphens, and standalone "and"
  let no_commas = cleaned.replace_all(old=",", new="")
  let no_hyphens = no_commas.replace_all(old="-", new=" ")
  let no_and = no_hyphens.replace_all(old=" and ", new=" ")
  let final_text = no_and.trim().to_string()
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
    let suffix = w.substring(start=len - 2, end=len).to_string()
    if suffix == "st" || suffix == "nd" || suffix == "rd" || suffix == "th" {
      let base = w.substring(start=0, end=len - 2).to_string()
      let result = ordinal_base_to_cardinal(base)
      // Only accept the stripped version if it's different from input
      // (this prevents false positives like "thousand" -> "thousa")
      if result != base {
        return result
      }
    }
  }
  w
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
    while i < chars.length() && not(is_whitespace(chars[i])) {
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
/// Build millis from extracted components
fn build_date_from_components(
  comps : DateComponents,
  picture : String,
) -> Double raise @error.JsonataError {
  let mut year = 1970
  let mut month = 1
  let mut day = 1
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut millis = 0
  let mut offset = 0

  // Apply extracted components
  match comps.year {
    Some(y) => year = y
    _ => ()
  }
  match comps.month {
    Some(m) => month = m
    _ => ()
  }
  match comps.day {
    Some(d) => day = d
    _ => ()
  }
  match comps.hour24 {
    Some(h) => hour = h
    _ => ()
  }
  match comps.hour12 {
    Some(h) => {
      hour = if h == 12 { 0 } else { h }
      match comps.am_pm {
        Some(pm) => if pm { hour = hour + 12 }
        _ => ()
      }
    }
    _ => ()
  }
  match comps.minute {
    Some(m) => minute = m
    _ => ()
  }
  match comps.second {
    Some(s) => second = s
    _ => ()
  }
  match comps.millis {
    Some(ms) => millis = ms
    _ => ()
  }
  match comps.offset {
    Some(o) => offset = o
    _ => ()
  }
  // If day_of_year is specified, convert to month/day
  match comps.day_of_year {
    Some(doy) => {
      let (m, d) = day_of_year_to_month_day(year, doy)
      month = m
      day = d
    }
    _ => ()
  }
  // If weekday is specified but not day/month, we need a reference point
  // This is complex and typically requires additional context
  // For now, if we have year, month, weekday but no day, use the date that matches

  millis_from_date_time(year, month, day, hour, minute, second, millis, offset)
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
