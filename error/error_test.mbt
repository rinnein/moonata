///|
test "JsonataError 各变体可构造与展示" {
  let e1 = JsonataError::SyntaxError(
    message="unexpected token",
    position=Some(3),
    token=Some("foo"),
  )
  let e2 = JsonataError::RuntimeError(message="div by zero")
  let e3 = JsonataError::TypeError(
    message="not a number",
    expected=Some("number"),
    actual=Some("string"),
  )
  let e4 = JsonataError::SignatureError(
    message="arity mismatch",
    func=Some("$sum"),
  )
  let e5 = JsonataError::GuardrailError(
    message="depth exceeded",
    limit=Some("max_depth=1000"),
  )
  debug_inspect(
    e1,
    content=(
      #|SyntaxError(
      #|  message="unexpected token",
      #|  position=Some(3),
      #|  token=Some("foo"),
      #|)
    ),
  )
  debug_inspect(
    e2,
    content=(
      #|RuntimeError(message="div by zero")
    ),
  )
  debug_inspect(
    e3,
    content=(
      #|TypeError(
      #|  message="not a number",
      #|  expected=Some("number"),
      #|  actual=Some("string"),
      #|)
    ),
  )
  debug_inspect(
    e4,
    content=(
      #|SignatureError(message="arity mismatch", func=Some("$sum"))
    ),
  )
  debug_inspect(
    e5,
    content=(
      #|GuardrailError(message="depth exceeded", limit=Some("max_depth=1000"))
    ),
  )
}

///|
test "JsonataError 可抛出与捕获" {
  let boom = fn() -> Unit raise JsonataError {
    raise JsonataError::RuntimeError(message="boom")
  }
  let caught = try {
    boom()
    None
  } catch {
    JsonataError::RuntimeError(message=m) => Some(m)
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
  )
  assert_true(a == b)
}
