///|
fn eval_fn(expr : String, data : Json) -> Json {
  let result = try {
    let tokens = @lexer.lex(expr)
    let ast = @parser.parse(tokens)
    let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
    @functions.register_builtins(ctx)
    let r = @evaluator.eval(ast, ctx)
    r.to_json()
  } catch {
    _ => Json::null()
  }
  result
}

///|
test "函数：$sum" {
  let data = @json.parse("[1,2,3,4,5]")
  assert_true(eval_fn("$sum($)", data) == Json::number(15.0))
}

///|
test "函数：$max $min" {
  let data = @json.parse("[3,1,4,1,5,9,2,6]")
  assert_true(eval_fn("$max($)", data) == Json::number(9.0))
  assert_true(eval_fn("$min($)", data) == Json::number(1.0))
}

///|
test "函数：$length" {
  assert_true(eval_fn("$length(\"hello\")", Json::null()) == Json::number(5.0))
  let data = @json.parse("[1,2,3]")
  assert_true(eval_fn("$length($)", data) == Json::number(3.0))
}

///|
test "函数：$substring" {
  assert_true(
    eval_fn("$substring(\"hello world\", 0, 5)", Json::null()) ==
    Json::string("hello"),
  )
}

///|
test "函数：$uppercase $lowercase" {
  assert_true(
    eval_fn("$uppercase(\"hello\")", Json::null()) == Json::string("HELLO"),
  )
  assert_true(
    eval_fn("$lowercase(\"WORLD\")", Json::null()) == Json::string("world"),
  )
}

///|
test "函数：$concat" {
  let result = eval_fn("$concat([\"a\", \"b\", \"c\"])", Json::null())
  assert_true(result == Json::string("abc"))
}

///|
test "函数：$contains" {
  assert_true(
    eval_fn("$contains(\"hello world\", \"world\")", Json::null()) ==
    Json::boolean(true),
  )
  assert_true(
    eval_fn("$contains(\"hello\", \"xyz\")", Json::null()) ==
    Json::boolean(false),
  )
}

///|
test "函数：$split" {
  let result = eval_fn("$split(\"a,b,c\", \",\")", Json::null())
  debug_inspect(
    result,
    content=(
      #|Array([String("a"), String("b"), String("c")])
    ),
  )
}

///|
test "函数：$abs $floor $ceiling $round" {
  assert_true(eval_fn("$abs(-5)", Json::null()) == Json::number(5.0))
  assert_true(eval_fn("$floor(3.7)", Json::null()) == Json::number(3.0))
  assert_true(eval_fn("$ceiling(3.2)", Json::null()) == Json::number(4.0))
  assert_true(eval_fn("$round(3.5)", Json::null()) == Json::number(4.0))
}

///|
test "函数：$map" {
  let data = @json.parse("[1,2,3]")
  let result = eval_fn("$map($, function($x) { $x * 2 })", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(2), Number(4), Number(6)])
    ),
  )
}

///|
test "函数：$filter" {
  let data = @json.parse("[1,2,3,4,5]")
  let result = eval_fn("$filter($, function($x) { $x > 2 })", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(3), Number(4), Number(5)])
    ),
  )
}

///|
test "函数：$count" {
  let data = @json.parse("[1,2,3,4,5]")
  assert_true(eval_fn("$count($)", data) == Json::number(5.0))
}

///|
test "函数：$keys $values" {
  let data = @json.parse("{\"a\":1,\"b\":2}")
  let keys = eval_fn("$keys($)", data)
  debug_inspect(
    keys,
    content=(
      #|Array([String("a"), String("b")])
    ),
  )
  let vals = eval_fn("$values($)", data)
  debug_inspect(
    vals,
    content=(
      #|Array([Number(1), Number(2)])
    ),
  )
}

///|
test "函数：$type" {
  assert_true(
    eval_fn("$type(\"hello\")", Json::null()) == Json::string("string"),
  )
  assert_true(eval_fn("$type(42)", Json::null()) == Json::string("number"))
  assert_true(eval_fn("$type(true)", Json::null()) == Json::string("boolean"))
  assert_true(eval_fn("$type(null)", Json::null()) == Json::string("null"))
}

///|
test "函数：$string $number $boolean" {
  assert_true(eval_fn("$string(42)", Json::null()) == Json::string("42"))
  assert_true(eval_fn("$number(\"42\")", Json::null()) == Json::number(42.0))
  assert_true(eval_fn("$boolean(1)", Json::null()) == Json::boolean(true))
}

///|
test "函数：$exists" {
  assert_true(eval_fn("$exists(1)", Json::null()) == Json::boolean(true))
  assert_true(eval_fn("$exists(missing)", Json::null()) == Json::boolean(false))
}

///|
test "函数：$reverse" {
  let data = @json.parse("[1,2,3]")
  let result = eval_fn("$reverse($)", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(3), Number(2), Number(1)])
    ),
  )
}

///|
test "函数：$sort" {
  let data = @json.parse("[3,1,4,1,5,9,2,6]")
  let result = eval_fn("$sort($)", data)
  debug_inspect(
    result,
    content=(
      #|Array(
      #|  [
      #|    Number(1),
      #|    Number(1),
      #|    Number(2),
      #|    Number(3),
      #|    Number(4),
      #|    Number(5),
      #|    Number(6),
      #|    Number(9),
      #|  ],
      #|)
    ),
  )
}

///|
test "函数：$join" {
  let data = @json.parse("[\"a\",\"b\",\"c\"]")
  assert_true(eval_fn("$join($, \",\")", data) == Json::string("a,b,c"))
}

///|
test "函数：$append" {
  let data = @json.parse("[1,2]")
  let result = eval_fn("$append($, [3,4])", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(1), Number(2), Number(3), Number(4)])
    ),
  )
}

///|
test "函数：$merge" {
  let data = @json.parse("[{\"a\":1},{\"b\":2}]")
  let result = eval_fn("$merge($)", data)
  debug_inspect(
    result,
    content=(
      #|Object({ "a": Number(1), "b": Number(2) })
    ),
  )
}
