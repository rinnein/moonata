///|
/// 值转数字
fn to_number(v : @value.JsonataValue) -> Double raise @error.JsonataError {
  match v {
    @value.JsonataValue::Json(Json::Number(n)) => n
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
    _ =>
      raise @error.type_error(
        "无法转为数字",
        expected=Some("number"),
        actual=None,
      )
  }
}

///|
/// 值转字符串
fn to_str(v : @value.JsonataValue) -> String {
  match v {
    @value.JsonataValue::Json(Json::String(s)) => s
    @value.JsonataValue::Json(Json::Number(n)) => n.to_string()
    @value.JsonataValue::Json(Json::True) => "true"
    @value.JsonataValue::Json(Json::False) => "false"
    @value.JsonataValue::Json(Json::Null) => "null"
    @value.JsonataValue::Undefined => ""
    _ => v.to_json().stringify()
  }
}

///|
/// 值转布尔
fn to_bool(v : @value.JsonataValue) -> Bool {
  match v {
    @value.JsonataValue::Json(Json::True) => true
    @value.JsonataValue::Json(Json::False) => false
    @value.JsonataValue::Json(Json::Number(n)) => n != 0.0
    @value.JsonataValue::Json(Json::String(s)) => s.length() > 0
    @value.JsonataValue::Json(Json::Null) => false
    @value.JsonataValue::Undefined => false
    @value.JsonataValue::Sequence(arr) => arr.length() > 0
    _ => true
  }
}

///|
/// JSON 值相等比较
fn json_equal(a : Json, b : Json) -> Bool {
  a == b
}

///|
fn not(b : Bool) -> Bool {
  !b
}
