///|
test "JsonataError 各变体可构造与展示" {
  let e1 = JsonataError::SyntaxError(
    message="unexpected token",
    position=Some(3),
    token=Some("foo"),
    code=None,
  )
  let e2 = JsonataError::RuntimeError(message="div by zero", code=None)
  let e3 = JsonataError::TypeError(
    message="not a number",
    expected=Some("number"),
    actual=Some("string"),
    code=None,
  )
  let e4 = JsonataError::SignatureError(
    message="arity mismatch",
    func=Some("$sum"),
    code=None,
  )
  let e5 = JsonataError::GuardrailError(
    message="depth exceeded",
    limit=Some("max_depth=1000"),
    code=None,
  )
  debug_inspect(
    e1,
    content=(
      #|SyntaxError(
      #|  message="unexpected token",
      #|  position=Some(3),
      #|  token=Some("foo"),
      #|  code=None,
      #|)
    ),
  )
  debug_inspect(
    e2,
    content=(
      #|RuntimeError(message="div by zero", code=None)
    ),
  )
  debug_inspect(
    e3,
    content=(
      #|TypeError(
      #|  message="not a number",
      #|  expected=Some("number"),
      #|  actual=Some("string"),
      #|  code=None,
      #|)
    ),
  )
  debug_inspect(
    e4,
    content=(
      #|SignatureError(message="arity mismatch", func=Some("$sum"), code=None)
    ),
  )
  debug_inspect(
    e5,
    content=(
      #|GuardrailError(
      #|  message="depth exceeded",
      #|  limit=Some("max_depth=1000"),
      #|  code=None,
      #|)
    ),
  )
}

///|
test "JsonataError 可抛出与捕获" {
  let boom = fn() -> Unit raise JsonataError {
    raise JsonataError::RuntimeError(message="boom", code=None)
  }
  let caught = try {
    boom()
    None
  } catch {
    JsonataError::RuntimeError(message=m, ..) => Some(m)
    _ => None
  }
  match caught {
    Some(m) => assert_eq(m, "boom")
    None => fail("应抛出错误")
  }
}

///|
test "便捷构造函数等价于直接构造" {
  let a = syntax_error("bad", position=Some(1), token=Some("x"))
  let b = JsonataError::SyntaxError(
    message="bad",
    position=Some(1),
    token=Some("x"),
    code=None,
  )
  assert_true(a == b)
}

///|
test "JsonataError 可携带官方错误码" {
  let e1 = syntax_error("unterminated string", code=Some("S0101"))
  let e2 = type_error(
    "not a number",
    expected=Some("number"),
    actual=Some("string"),
    code=Some("T2001"),
  )
  let e3 = runtime_error("non-function", code=Some("T1006"))
  assert_true(e1.error_code() == Some("S0101"))
  assert_true(e2.error_code() == Some("T2001"))
  assert_true(e3.error_code() == Some("T1006"))
  // 不带 code 的错误返回 None
  let e4 = runtime_error("no code")
  assert_true(e4.error_code() == None)
}
