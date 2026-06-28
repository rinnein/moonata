///|
/// JSONata 错误类型层级。
///
/// 单一 suberror，含 5 个变体。调用方用一次 `raise JsonataError` 即可传播所有错误，
/// 需要精细处理时用模式匹配区分变体。每个变体携带结构化字段，便于定位。
pub(all) suberror JsonataError {
  SyntaxError(message~ : String, position~ : Int?, token~ : String?)
  RuntimeError(message~ : String)
  TypeError(message~ : String, expected~ : String?, actual~ : String?)
  SignatureError(message~ : String, func~ : String?)
  GuardrailError(message~ : String, limit~ : String?)
} derive(Debug, Eq)

///|
/// 便捷构造语法错误。
pub fn syntax_error(
  message : String,
  position? : Int? = None,
  token? : String? = None,
) -> JsonataError {
  JsonataError::SyntaxError(message~, position~, token~)
}

///|
/// 便捷构造运行时错误。
pub fn runtime_error(message : String) -> JsonataError {
  JsonataError::RuntimeError(message~)
}

///|
/// 便捷构造类型错误。
pub fn type_error(
  message : String,
  expected? : String? = None,
  actual? : String? = None,
) -> JsonataError {
  JsonataError::TypeError(message~, expected~, actual~)
}

///|
/// 便捷构造签名错误。
pub fn signature_error(
  message : String,
  func? : String? = None,
) -> JsonataError {
  JsonataError::SignatureError(message~, func~)
}

///|
/// 便捷构造护栏错误。
pub fn guardrail_error(
  message : String,
  limit? : String? = None,
) -> JsonataError {
  JsonataError::GuardrailError(message~, limit~)
}
