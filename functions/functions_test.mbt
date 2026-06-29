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
fn eval_signature_error(expr : String) -> Bool {
  try {
    let tokens = @lexer.lex(expr)
    let ast = @parser.parse(tokens)
    let ctx = @value.EvalContext::new(@value.JsonataValue::Json(Json::null()))
    @functions.register_builtins(ctx)
    ignore(@evaluator.eval(ast, ctx))
    false
  } catch {
    @error.JsonataError::SignatureError(..) => true
    _ => false
  }
}

///|
test "函数：$sum" {
  let data = @json.parse("[1,2,3,4,5]")
  assert_true(eval_fn("$sum($)", data) == Json::number(15.0))
}

///|
test "函数：$average" {
  assert_true(eval_fn("$average([1,2,3])", Json::null()) == Json::number(2.0))
  assert_true(eval_fn("$average(1)", Json::null()) == Json::number(1.0))
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
  assert_true(eval_fn("$ceil(3.7)", Json::null()) == Json::number(4.0))
  assert_true(eval_fn("$ceil(-3.7)", Json::null()) == Json::number(-3.0))
  assert_true(eval_fn("$ceil(0)", Json::null()) == Json::number(0.0))
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
  assert_true(
    eval_fn("$string(22 / 7)", Json::null()) == Json::string("3.14285714285714"),
  )
  assert_true(eval_fn("$string($string)", Json::null()) == Json::string(""))
  assert_true(
    eval_fn("$string({\"string\":\"hello\"}, true)", Json::null()) ==
    Json::string("{\n  \"string\": \"hello\"\n}"),
  )
  assert_true(
    eval_fn("$string({\"function\":$sum,\"array\":[1,$boolean]})", Json::null()) ==
    Json::string("{\"function\":\"\",\"array\":[1,\"\"]}"),
  )
  assert_true(
    eval_fn("$string()", @json.parse("[4,true]")) == Json::string("[4,true]"),
  )
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

///|
test "P9.3：$replace 字符串替换" {
  assert_true(
    eval_fn("$replace(\"hello world\", \"world\", \"moonbit\")", Json::null()) ==
    Json::string("hello moonbit"),
  )
}

///|
test "P9.3：$distinct 去重" {
  let data = @json.parse("[1,2,2,3,3,3,4]")
  let result = eval_fn("$distinct($)", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(1), Number(2), Number(3), Number(4)])
    ),
  )
}

///|
test "P9.3：$sqrt $pi $e" {
  assert_true(eval_fn("$sqrt(16)", Json::null()) == Json::number(4.0))
  let pi = eval_fn("$pi", Json::null())
  debug_inspect(
    pi,
    content=(
      #|Null
    ),
  )
  let e = eval_fn("$e", Json::null())
  debug_inspect(
    e,
    content=(
      #|Null
    ),
  )
}

///|
test "P9.3：$formatBase 进制转换" {
  assert_true(
    eval_fn("$formatBase(255, 16)", Json::null()) == Json::string("ff"),
  )
  assert_true(
    eval_fn("$formatBase(10, 2)", Json::null()) == Json::string("1010"),
  )
}

///|
test "P9.3：$single 唯一元素" {
  let data = @json.parse("[42]")
  assert_true(eval_fn("$single($)", data) == Json::number(42.0))
}

///|
test "P9.3：$partition 分区" {
  let data = @json.parse("[1,2,3,4,5]")
  let result = eval_fn("$partition($, function($x) { $x > 3 })", data)
  debug_inspect(
    result,
    content=(
      #|Array(
      #|  [
      #|    Array([Number(4), Number(5)]),
      #|    Array([Number(1), Number(2), Number(3)]),
      #|  ],
      #|)
    ),
  )
}

///|
test "P9.3：$zip 配对" {
  let data1 = @json.parse("[1,2,3]")
  let result = eval_fn("$zip($, [\"a\",\"b\",\"c\"])", data1)
  debug_inspect(
    result,
    content=(
      #|Array(
      #|  [
      #|    Array([Number(1), String("a")]),
      #|    Array([Number(2), String("b")]),
      #|    Array([Number(3), String("c")]),
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    eval_fn("$zip([1,2,3],[4,5,6],[7,8,9])", Json::null()),
    content=(
      #|Array(
      #|  [
      #|    Array([Number(1), Number(4), Number(7)]),
      #|    Array([Number(2), Number(5), Number(8)]),
      #|    Array([Number(3), Number(6), Number(9)]),
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    eval_fn("$zip([1,2,3])", Json::null()),
    content=(
      #|Array([Array([Number(1)]), Array([Number(2)]), Array([Number(3)])])
    ),
  )
  debug_inspect(
    eval_fn("$zip(1,2,3)", Json::null()),
    content=(
      #|Array([Array([Number(1), Number(2), Number(3)])])
    ),
  )
}

///|
test "P9.3：$base64encode $base64decode" {
  let encoded = eval_fn("$base64encode(\"hello\")", Json::null())
  debug_inspect(
    encoded,
    content=(
      #|String("aGVsbG8=")
    ),
  )
  let decoded = eval_fn("$base64decode($base64encode(\"hello\"))", Json::null())
  assert_true(decoded == Json::string("hello"))
}

///|
test "P9.4：$match 正则匹配" {
  let result = eval_fn("$match(\"abc123def\", \"[0-9]+\")", Json::null())
  debug_inspect(
    result,
    content=(
      #|Object({ "match": String("123"), "groups": Array([]) })
    ),
  )
}

///|
test "P9.4：$contains_regex 正则包含" {
  assert_true(
    eval_fn("$contains_regex(\"hello world\", \"world\")", Json::null()) ==
    Json::boolean(true),
  )
  assert_true(
    eval_fn("$contains_regex(\"hello\", \"[0-9]+\")", Json::null()) ==
    Json::boolean(false),
  )
}

///|
test "P9.4：$split_regex 正则分割" {
  let result = eval_fn("$split_regex(\"a1b2c3d\", \"[0-9]\")", Json::null())
  debug_inspect(
    result,
    content=(
      #|Array([String("a"), String("b"), String("c"), String("d")])
    ),
  )
}

///|
test "P9.4：$replace_regex 正则替换" {
  let result = eval_fn(
    "$replace_regex(\"hello world\", \"world\", \"moonbit\")",
    Json::null(),
  )
  assert_true(result == Json::string("hello moonbit"))
}

///|
test "P10：签名系统报告 SignatureError" {
  assert_true(eval_signature_error("$substring(1, 0)"))
}

///|
test "P10：$random 返回 0 到 1 之间的数" {
  let result = eval_fn("$random()", Json::null())
  match result {
    Json::Number(n, ..) => assert_true(n >= 0.0 && n < 1.0)
    _ => fail("$random 应返回 number")
  }
}

///|
test "P10：$formatDateTime 基础格式化" {
  let result = eval_fn("$formatDateTime(0)", Json::null())
  assert_true(result == Json::string("1970-01-01T00:00:00.000Z"))
  assert_true(
    eval_fn("$fromMillis(1)", Json::null()) ==
    Json::string("1970-01-01T00:00:00.001Z"),
  )
  assert_true(
    eval_fn("$fromMillis(1521801216617, \"[Y0001]-[M01]-[D01]\")", Json::null()) ==
    Json::string("2018-03-23"),
  )
  assert_true(
    eval_fn("$toMillis(\"1970-01-01T00:00:00.001Z\")", Json::null()) ==
    Json::number(1.0),
  )
  assert_true(
    eval_fn("$toMillis(\"2017-10-30\")", Json::null()) ==
    Json::number(1509321600000.0),
  )
}

///|
test "P11：日期 picture 支持 ISO 周和紧凑解析" {
  assert_true(
    eval_fn(
      "$fromMillis(1521801216617, \"[D#1,2]/[M1,2]/[Y0001,2]\")",
      Json::null(),
    ) ==
    Json::string("23/03/2018"),
  )
  assert_true(
    eval_fn(
      "$fromMillis($toMillis(\"2005-01-01\", \"[Y]-[M]-[D]\"), \"[X0001]-W[W01]-[F1]\")",
      Json::null(),
    ) ==
    Json::string("2004-W53-6"),
  )
  assert_true(
    eval_fn("$fromMillis(1546257600000, \"[d] days in [Y0001]\")", Json::null()) ==
    Json::string("365 days in 2018"),
  )
  assert_true(
    eval_fn("$toMillis(\"201802\", \"[Y0001][M01]\")", Json::null()) ==
    Json::number(1517443200000.0),
  )
  assert_true(
    eval_fn("$toMillis(\"20180205\", \"[Y0001][M01][D01]\")", Json::null()) ==
    Json::number(1517788800000.0),
  )
  assert_true(
    eval_fn(
      "$toMillis(\"20240101123849\", \"[Y0000][M00][D00][H00][m00][s00]\")",
      Json::null(),
    ) ==
    Json::number(1704112729000.0),
  )
}

///|
test "P11：整数 picture 支持英文序数大数与字母序号" {
  assert_true(
    eval_fn("$formatInteger(1000000000001, \"w\")", Json::null()) ==
    Json::string("one trillion and one"),
  )
  assert_true(
    eval_fn("$formatInteger(555, \"Ww\")", Json::null()) ==
    Json::string("Five Hundred and Fifty-Five"),
  )
  assert_true(
    eval_fn("$formatInteger(34, \"w;o\")", Json::null()) ==
    Json::string("thirty-fourth"),
  )
  assert_true(
    eval_fn("$formatInteger(300, \"A\")", Json::null()) == Json::string("KN"),
  )
  assert_true(
    eval_fn("$parseInteger(\"one trillion and one\", \"w\")", Json::null()) ==
    Json::number(1000000000001.0),
  )
  assert_true(
    eval_fn("$parseInteger(\"thirty-fourth\", \"w;o\")", Json::null()) ==
    Json::number(34.0),
  )
  assert_true(
    eval_fn("$parseInteger(\"KN\", \"A\")", Json::null()) == Json::number(300.0),
  )
}

///|
test "P10：标准正则函数名兼容" {
  assert_true(
    eval_fn("$contains(\"hello123\", \"[0-9]+\")", Json::null()) ==
    Json::boolean(true),
  )
  let split_result = eval_fn("$split(\"a1b\", \"[0-9]\")", Json::null())
  debug_inspect(
    split_result,
    content=(
      #|Array([String("a"), String("b")])
    ),
  )
  assert_true(
    eval_fn("$replace(\"hello 123\", \"[0-9]+\", \"x\")", Json::null()) ==
    Json::string("hello x"),
  )
}
