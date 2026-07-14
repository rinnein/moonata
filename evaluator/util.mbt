///|
/// 值转数字
fn to_number(v : @value.JsonataValue) -> Double raise @error.JsonataError {
  match v {
    @value.JsonataValue::Json(Json::Number(n, ..)) => n
    @value.JsonataValue::Json(Json::String(s)) =>
      @strconv.from_str(s) catch {
        _ =>
          raise @error.type_error(
            "无法转为数字: \{s}",
            expected=Some("number"),
            actual=Some("string"),
          )
      }
    @value.JsonataValue::Json(Json::True) => 1.0
    @value.JsonataValue::Json(Json::False) => 0.0
    @value.JsonataValue::Sequence(_) => to_number(v.lift_singleton())
    _ =>
      raise @error.type_error(
        "无法转为数字",
        expected=Some("number"),
        actual=None,
      )
  }
}

///|
/// 值转数字，失败时携带 JSONata 官方错误码（如 T2001/T2002/D1002）。
///
/// `side` 为 "left" 或 "right"，用于区分 T2001（左侧）与 T2002（右侧）。
/// `op` 为运算符原文（如 `"+"`、`"*"`），会嵌入错误消息，对齐 jsonata-js
/// `evaluateNumericExpression` 抛出的 `message`/`token` 字段——官方测试集
/// `errors/case026` 期望 `token: "+"`，audit 脚本以子串匹配方式校验。
/// 一元负号使用 `D1002`。
///
/// 对齐 JSONata-js `evaluateNumericExpression` + `isNumeric`：
/// - 仅接受真正的 Number 类型（不接受字符串、布尔值等可转数字的值）
/// - Infinity 抛出 D1001（Number out of range）
/// - NaN 视为非数字，抛出 T2001/T2002
/// - undefined 通过 undefined 传播处理（在调用方检查）
fn to_number_with_code(
  v : @value.JsonataValue,
  side : String,
  op? : String = "",
) -> Double raise @error.JsonataError {
  let code = if side == "left" { "T2001" } else { "T2002" }
  // 对齐 jsonata-js：消息中包含运算符原文（如 "The right side of the '+' operator..."），
  // 使 audit 脚本可对 `token` 字段做子串匹配。
  let op_repr = if op != "" { " '\{op}'" } else { "" }
  let msg = "The \{side} side of the\{op_repr} operator must evaluate to a number"
  match v {
    @value.JsonataValue::Json(Json::Number(n, ..)) =>
      if n.is_inf() {
        // D1001: Infinity 超出数字范围
        raise @error.runtime_error(
          "D1001: Number out of range: \{n}",
          code=Some("D1001"),
        )
      } else if n.is_nan() {
        // NaN 视为非数字 → T2001/T2002
        raise @error.type_error(
          msg,
          expected=Some("number"),
          actual=None,
          code=Some(code),
        )
      } else {
        n
      }
    @value.JsonataValue::Sequence(arr) if arr.length() == 1 =>
      to_number_with_code(arr[0], side, op~)
    _ =>
      raise @error.type_error(
        msg,
        expected=Some("number"),
        actual=None,
        code=Some(code),
      )
  }
}

///|
/// 值转字符串
fn to_str(v : @value.JsonataValue) -> String {
  match v {
    @value.JsonataValue::Json(Json::String(s)) => s
    @value.JsonataValue::Json(Json::Number(n, ..)) => number_to_str(n)
    @value.JsonataValue::Json(Json::True) => "true"
    @value.JsonataValue::Json(Json::False) => "false"
    @value.JsonataValue::Json(Json::Null) => "null"
    @value.JsonataValue::Undefined => ""
    @value.JsonataValue::Sequence(arr) =>
      match arr.length() {
        0 => ""
        1 => to_str(arr[0])
        _ => {
          let out : Array[Json] = []
          for item in arr {
            out.push(item.to_json())
          }
          Json::array(out).stringify()
        }
      }
    _ => v.to_json().stringify()
  }
}

///|
fn number_to_str(n : Double) -> String {
  if n == 0.0 {
    return "0"
  }
  let negative = n < 0.0
  let abs_n = if negative { -n } else { n }
  if abs_n >= 1.0e21 || abs_n < 1.0e-6 {
    return n.to_string()
  }
  if abs_n >= 9_007_199_254_740_991.0 {
    return n.to_string()
  }
  let digits_before = number_integer_digit_count(abs_n)
  let places = (15 - digits_before).max(0)
  let rounded_abs = round_decimal_places(abs_n, places)
  let body = fixed_number_string(rounded_abs, places)
  if negative {
    "-" + body
  } else {
    body
  }
}

///|
fn number_integer_digit_count(n : Double) -> Int {
  let mut digits = 1
  let mut value = n
  while value >= 10.0 {
    value = value / 10.0
    digits = digits + 1
  }
  digits
}

///|
fn round_decimal_places(n : Double, places : Int) -> Double {
  if places <= 0 {
    n.round()
  } else {
    let scale = @math.pow(10.0, places.to_double())
    (n * scale).round() / scale
  }
}

///|
fn fixed_number_string(n : Double, places : Int) -> String {
  if places <= 0 {
    return n.round().to_int64().to_string()
  }
  let int_part = n.floor()
  let scale = @math.pow(10.0, places.to_double())
  let mut frac_number = ((n - int_part) * scale).round().to_int64()
  let mut int_text = int_part.to_int64().to_string()
  let scale_int = scale.round().to_int64()
  if frac_number >= scale_int {
    int_text = (int_part + 1.0).to_int64().to_string()
    frac_number = 0
  }
  let frac = trim_number_zeroes(
    pad_number_left(frac_number.to_string(), places),
  )
  if frac.length() == 0 {
    int_text
  } else {
    int_text + "." + frac
  }
}

///|
fn pad_number_left(s : String, width : Int) -> String {
  let out = StringBuilder::new()
  for _ in 0..<(width - s.length()).max(0) {
    out.write_char('0')
  }
  out.write_string(s)
  out.to_string()
}

///|
fn trim_number_zeroes(s : String) -> String {
  let mut end = s.length()
  while end > 0 && s[end - 1] == '0' {
    end = end - 1
  }
  s[:end].to_owned()
}

///|
/// 值转布尔
fn to_bool(v : @value.JsonataValue) -> Bool {
  match v {
    @value.JsonataValue::Json(Json::True) => true
    @value.JsonataValue::Json(Json::False) => false
    @value.JsonataValue::Json(Json::Number(n, ..)) => n != 0.0
    @value.JsonataValue::Json(Json::String(s)) => s.length() > 0
    @value.JsonataValue::Json(Json::Null) => false
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let mut any = false
      for item in arr {
        if to_bool(@value.JsonataValue::Json(item)) {
          any = true
          break
        }
      }
      any
    }
    @value.JsonataValue::Json(Json::Object(map)) => map.length() > 0
    @value.JsonataValue::Object(map) => map.length() > 0
    @value.JsonataValue::Undefined => false
    @value.JsonataValue::Sequence(arr) => arr.length() > 0
    @value.JsonataValue::Func(_) => false
    @value.JsonataValue::Regex(_) => false
  }
}

///|
/// JSON 值相等比较
fn json_equal(a : Json, b : Json) -> Bool {
  a == b
}

///|
fn is_string_value(v : @value.JsonataValue) -> Bool {
  match v {
    @value.JsonataValue::Json(Json::String(_)) => true
    _ => false
  }
}

///|
fn not(b : Bool) -> Bool {
  !b
}
