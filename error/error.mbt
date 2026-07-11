///|
/// JSONata 错误类型层级。
///
/// 单一 suberror，含 5 个变体。调用方用一次 `raise JsonataError` 即可传播所有错误，
/// 需要精细处理时用模式匹配区分变体。每个变体携带结构化字段，便于定位。
///
/// `code` 字段携带 JSONata 官方错误码（如 `T2001`、`S0101`），用于与官方
/// 测试集做错误码匹配。未设置时为 `None`。
pub(all) suberror JsonataError {
  SyntaxError(
    message~ : String,
    position~ : Int?,
    token~ : String?,
    code~ : String?
  )
  RuntimeError(message~ : String, code~ : String?)
  TypeError(
    message~ : String,
    expected~ : String?,
    actual~ : String?,
    code~ : String?
  )
  SignatureError(message~ : String, func~ : String?, code~ : String?)
  GuardrailError(message~ : String, limit~ : String?, code~ : String?)
} derive(Debug, Eq)

///|
/// 便捷构造语法错误。
pub fn syntax_error(
  message : String,
  position? : Int? = None,
  token? : String? = None,
  code? : String? = None,
) -> JsonataError {
  JsonataError::SyntaxError(message~, position~, token~, code~)
}

///|
/// 便捷构造运行时错误。
pub fn runtime_error(message : String, code? : String? = None) -> JsonataError {
  JsonataError::RuntimeError(message~, code~)
}

///|
/// 便捷构造类型错误。
pub fn type_error(
  message : String,
  expected? : String? = None,
  actual? : String? = None,
  code? : String? = None,
) -> JsonataError {
  JsonataError::TypeError(message~, expected~, actual~, code~)
}

///|
/// 便捷构造签名错误。
pub fn signature_error(
  message : String,
  func? : String? = None,
  code? : String? = None,
) -> JsonataError {
  JsonataError::SignatureError(message~, func~, code~)
}

///|
/// 便捷构造护栏错误。
pub fn guardrail_error(
  message : String,
  limit? : String? = None,
  code? : String? = None,
) -> JsonataError {
  JsonataError::GuardrailError(message~, limit~, code~)
}

///|
/// 提取错误码（若存在）。
pub fn JsonataError::error_code(self : JsonataError) -> String? {
  match self {
    SyntaxError(code~, ..) => code
    RuntimeError(code~, ..) => code
    TypeError(code~, ..) => code
    SignatureError(code~, ..) => code
    GuardrailError(code~, ..) => code
  }
}
