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

///|
/// 提取错误消息（未经 Debug 转义）。
///
/// 用于 CLI 输出与官方测试集审计：jsonata-js test runner 通过
/// `deep.contain(testcase.error)` 校验 `message` 字段，audit 脚本以子串
/// 匹配方式实现等价语义。Debug 派生的 `to_repr` 会把消息中的 `"` 转义为
/// `\"`，导致带引号的消息（如 D3140 `Malformed URL passed to $decodeUrl():
/// "%E0%A4%A"`）无法被子串匹配命中。本方法返回原始 message 文本。
pub fn JsonataError::error_message(self : JsonataError) -> String {
  match self {
    SyntaxError(message~, ..) => message
    RuntimeError(message~, ..) => message
    TypeError(message~, ..) => message
    SignatureError(message~, ..) => message
    GuardrailError(message~, ..) => message
  }
}
