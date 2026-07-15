///|
test "parse_cli_config: expr only" {
  let config = parse_cli_config(["1 + 2"])
  assert_eq(config.expr, "1 + 2")
  assert_true(config.data == None)
  assert_true(config.file == None)
  assert_true(config.expr_file == None)
  assert_eq(config.no_data, false)
  assert_eq(config.max_depth, -1)
  assert_true(config.stack == None)
  assert_true(config.timeout == None)
  assert_true(config.sequence == None)
}

///|
test "parse_cli_config: expr with --data" {
  let config = parse_cli_config(["name", "--data", "{\"name\":\"Alice\"}"])
  assert_eq(config.expr, "name")
  assert_true(config.data == Some("{\"name\":\"Alice\"}"))
  assert_true(config.file == None)
  assert_eq(config.no_data, false)
}

///|
test "parse_cli_config: expr with --file" {
  let config = parse_cli_config(["name", "--file", "test.json"])
  assert_eq(config.expr, "name")
  assert_true(config.data == None)
  assert_true(config.file == Some("test.json"))
}

///|
test "parse_cli_config: --expr-file" {
  let config = parse_cli_config(["--expr-file", "expr.txt"])
  assert_eq(config.expr, "")
  assert_true(config.expr_file == Some("expr.txt"))
}

///|
test "parse_cli_config: --no-data flag" {
  let config = parse_cli_config(["name", "--no-data"])
  assert_eq(config.expr, "name")
  assert_eq(config.no_data, true)
}

///|
test "parse_cli_config: --max-depth integer" {
  let config = parse_cli_config(["name", "--max-depth", "302"])
  assert_eq(config.max_depth, 302)
}

///|
test "parse_cli_config: --stack integer (guardrails)" {
  let config = parse_cli_config(["name", "--stack", "500"])
  assert_true(config.stack == Some(500))
}

///|
test "parse_cli_config: --timeout integer (guardrails)" {
  let config = parse_cli_config(["name", "--timeout", "1000"])
  assert_true(config.timeout == Some(1000))
}

///|
test "parse_cli_config: --sequence integer (guardrails)" {
  let config = parse_cli_config(["name", "--sequence", "1000000"])
  assert_true(config.sequence == Some(1000000))
}

///|
test "parse_cli_config: hyphen-prefixed expr" {
  // JSONata 表达式可能以 `-` 开头（如负数字面量），positional 启用
  // allow_hyphen_values 后应作为整体被接受
  let config = parse_cli_config(["-1 + 2"])
  assert_eq(config.expr, "-1 + 2")
}

///|
test "parse_cli_config: options can appear before expr" {
  let config = parse_cli_config(["--data", "{}", "expr"])
  assert_eq(config.expr, "expr")
  assert_true(config.data == Some("{}"))
}

///|
test "parse_cli_config: combined flags" {
  let config = parse_cli_config([
    "$sum($.items.price)", "--file", "data.json", "--max-depth", "500",
  ])
  assert_eq(config.expr, "$sum($.items.price)")
  assert_true(config.file == Some("data.json"))
  assert_eq(config.max_depth, 500)
}

///|
test "parse_cli_config: combined guardrails" {
  let config = parse_cli_config([
    "$sum($.items.price)", "--stack", "500", "--timeout", "1000", "--sequence", "1000000",
  ])
  assert_eq(config.expr, "$sum($.items.price)")
  assert_true(config.stack == Some(500))
  assert_true(config.timeout == Some(1000))
  assert_true(config.sequence == Some(1000000))
}

///|
test "parse_cli_config: --max-depth non-integer raises" {
  try parse_cli_config(["name", "--max-depth", "abc"]) catch {
    _ => return
  } noraise {
    _ => fail("expected --max-depth to reject non-integer")
  }
}

///|
test "parse_cli_config: --stack non-integer raises" {
  try parse_cli_config(["name", "--stack", "abc"]) catch {
    _ => return
  } noraise {
    _ => fail("expected --stack to reject non-integer")
  }
}
