///|
/// JSONata 运行时值：四态 enum。
///
/// - `Json`：单个 JSON 值（包装 prelude 的 `Json`）。
/// - `Sequence`：平坦序列，元素恒为 `Json`（已展平）。
/// - `Func`：函数值（内建函数与 Lambda 统一为一等公民）。
/// - `Undefined`：JSONata 语义一等值，参与传播，不等同于 `null`。
pub(all) enum JsonataValue {
  Json(Json)
  Sequence(Array[JsonataValue])
  Func(JsonataFunc)
  Undefined
} derive(Debug)

///|
/// 函数值：持有元数与闭包。
///
/// 内建函数与用户 Lambda 统一为 `JsonataFunc`，闭包接收参数数组与上下文。
pub struct JsonataFunc {
  arity : Int
  invoke : (Array[JsonataValue], EvalContext) -> JsonataValue raise @error.JsonataError
}

///|
/// 为 `JsonataFunc` 手动实现 Debug（闭包不可打印，仅显示元数）。
pub impl Debug for JsonataFunc with fn to_repr(self) {
  Repr::string("#<func arity=\{self.arity}>")
}

///|
/// 构造函数值。
pub fn JsonataFunc::new(
  arity~ : Int,
  invoke~ : (Array[JsonataValue], EvalContext) -> JsonataValue raise @error.JsonataError,
) -> JsonataFunc {
  { arity, invoke }
}

///|
/// 从 JSON 值构造 JsonataValue（单例）。
pub fn JsonataValue::from_json(json : Json) -> JsonataValue {
  Json(json)
}

///|
/// 将 JsonataValue 转换为 JSON 值。
///
/// - `Undefined` → `Null`（JSONata 语义：undefined 序列化为 null）
/// - `Sequence` → 长度 0 转 null；长度 1 提升为单例；否则转数组
/// - `Func` → `Null`
pub fn JsonataValue::to_json(self : JsonataValue) -> Json {
  match self {
    Json(j) => j
    Undefined => Json::null()
    Func(_) => Json::null()
    Sequence(arr) =>
      match arr.length() {
        0 => Json::null()
        1 => arr[0].to_json()
        _ => {
          let out = arr.map(fn(v) { v.to_json() })
          Json::array(out)
        }
      }
  }
}

///|
/// 是否为 undefined。
pub fn JsonataValue::is_undefined(self : JsonataValue) -> Bool {
  self is Undefined
}

///|
/// 是否为序列（长度 > 1）。
pub fn JsonataValue::is_sequence(self : JsonataValue) -> Bool {
  self is Sequence(_)
}

///|
/// 将值规范为序列数组视图。
///
/// - `Sequence` → 自身数组
/// - `Json(Array(...))` → 解包为元素数组
/// - `Undefined` → 空数组
/// - 其他 → 单元素数组
pub fn JsonataValue::to_array(self : JsonataValue) -> Array[JsonataValue] {
  match self {
    Sequence(arr) => arr
    Json(Json::Array(arr)) => {
      let result : Array[JsonataValue] = []
      for item in arr {
        result.push(Json(item))
      }
      result
    }
    Undefined => []
    _ => [self]
  }
}

///|
/// 将序列提升为单例（标量上下文）。
///
/// 长度为 1 的序列提升为其唯一元素；其他原样返回。
pub fn JsonataValue::lift_singleton(self : JsonataValue) -> JsonataValue {
  match self {
    Sequence(arr) if arr.length() == 1 => arr[0]
    _ => self
  }
}

///|
/// 展平序列：递归展平嵌套序列并过滤 Undefined。
pub fn flatten_sequence(items : Array[JsonataValue]) -> Array[JsonataValue] {
  let out : Array[JsonataValue] = []
  for item in items {
    match item {
      Sequence(inner) =>
        for sub in flatten_sequence(inner) {
          out.push(sub)
        }
      Undefined => continue
      _ => out.push(item)
    }
  }
  out
}

///|
/// 构造序列：展平嵌套序列并过滤 Undefined。
///
/// 结果长度为 0 → `Undefined`；长度为 1 → 单例；否则 → `Sequence`。
pub fn JsonataValue::sequence(items : Array[JsonataValue]) -> JsonataValue {
  let flat = flatten_sequence(items)
  match flat.length() {
    0 => Undefined
    1 => flat[0]
    _ => Sequence(flat)
  }
}

///|
/// 比较两个 JsonataValue 是否结构相等（用于测试）。
///
/// 函数值按元数比较；序列按元素递归比较。
pub fn JsonataValue::equal(self : JsonataValue, other : JsonataValue) -> Bool {
  match (self, other) {
    (Undefined, Undefined) => true
    (Func(a), Func(b)) => a.arity == b.arity
    (Json(a), Json(b)) => a == b
    (Sequence(a), Sequence(b)) =>
      if a.length() != b.length() {
        false
      } else {
        let mut all = true
        for i in 0..<a.length() {
          if !a[i].equal(b[i]) {
            all = false
            break
          }
        }
        all
      }
    _ => false
  }
}
