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
fn eval_fn_catch(expr : String, data : Json) -> @error.JsonataError? {
  try {
    let tokens = @lexer.lex(expr)
    let ast = @parser.parse(tokens)
    let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
    @functions.register_builtins(ctx)
    ignore(@evaluator.eval(ast, ctx))
    None
  } catch {
    e => Some(e)
  }
}

///|
fn error_has_code(result : @error.JsonataError?, code : String) -> Bool {
  match result {
    Some(err) =>
      match err.error_code() {
        Some(c) => c == code
        None => false
      }
    None => false
  }
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
  assert_true(eval_fn("$count($)", data) == Json::number(3.0))
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
  assert_true(
    eval_fn("$split(\"Hello\", \"\")", Json::null()) ==
    @json.parse("[\"H\",\"e\",\"l\",\"l\",\"o\"]"),
  )
  assert_true(
    eval_fn("$split(\"a, b, c, d\", \", \", 0)", Json::null()) ==
    @json.parse("[]"),
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
  assert_true(
    eval_fn("$keys({\"foo\":{}})", Json::null()) == Json::string("foo"),
  )
  assert_true(
    eval_fn("$keys($)", @json.parse("[{\"a\":1,\"b\":2},{\"b\":3,\"c\":4}]")) ==
    @json.parse("[\"a\",\"b\",\"c\"]"),
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
test "函数：$spread" {
  assert_true(
    eval_fn("$spread(\"Hello World\")", Json::null()) ==
    Json::string("Hello World"),
  )
  assert_true(
    eval_fn("$spread([{ \"a\": 1 }, { \"b\": 2, \"c\": 3 }])", Json::null()) ==
    @json.parse("[{\"a\":1},{\"b\":2},{\"c\":3}]"),
  )
}

///|
test "函数：$sift predicate 参数" {
  assert_true(
    eval_fn(
      "$sift({'a':'hello','b':'world','hello':'again'}, function($v,$k,$o){$lookup($o,$v)})",
      Json::null(),
    ) ==
    @json.parse("{\"a\":\"hello\"}"),
  )
  assert_true(
    eval_fn("$sift({'a':1}, function($v){false})", Json::null()) == Json::null(),
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
    eval_fn("$string($)", @json.parse("[4,true]")) == Json::string("[4,true]"),
  )
  // $string() 无参时使用上下文作为首参（对齐 jsonata-js `<x-b?:s>` 的 `-` 修饰符）
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
  assert_true(eval_fn("$reverse([1])", Json::null()) == @json.parse("[1]"))
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
  assert_true(eval_fn("$join($)", data) == Json::string("abc"))
  assert_true(
    eval_fn("$join(\"hello\")", Json::null()) == Json::string("hello"),
  )
  assert_true(
    eval_fn("$join([\"hello\"])", Json::null()) == Json::string("hello"),
  )
}

///|
test "函数：$shuffle" {
  assert_true(
    eval_fn("$count($shuffle([1..10]))", Json::null()) == Json::number(10.0),
  )
  assert_true(eval_fn("$shuffle([1])", Json::null()) == @json.parse("[1]"))
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
  assert_true(eval_fn("$formatBase(100)", Json::null()) == Json::string("100"))
  assert_true(
    eval_fn("$formatBase(255, 16)", Json::null()) == Json::string("ff"),
  )
  assert_true(
    eval_fn("$formatBase(10, 2)", Json::null()) == Json::string("1010"),
  )
  assert_true(
    eval_fn("$formatBase(99.5, 2.5)", Json::null()) == Json::string("1100100"),
  )
  assert_true(
    eval_fn("$formatBase(5890840712243076)", Json::null()) ==
    Json::string("5890840712243076"),
  )
}

///|
test "P9.3：$single 唯一元素" {
  let data = @json.parse("[42]")
  assert_true(eval_fn("$single($)", data) == Json::number(42.0))
  assert_true(
    eval_fn(
      "$single([true, false, true], function($v) {$v=false})",
      Json::null(),
    ) ==
    Json::boolean(false),
  )
  assert_true(
    eval_fn(
      "$single([\"zero\", \"one\", \"two\"], function($v, $i, $a) {$i=1})",
      Json::null(),
    ) ==
    Json::string("one"),
  )
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
    eval_fn("$fromMillis(1521801216617, \"[D1] [M01] [YI]\")", Json::null()) ==
    Json::string("23 03 MMXVIII"),
  )
  assert_true(
    eval_fn("$fromMillis(1521801216617, \"[Da] [MA] [Yi]\")", Json::null()) ==
    Json::string("w C mmxviii"),
  )
  assert_true(
    eval_fn(
      "$toMillis(\"2018-10-21T13:05:00Z\").[$fromMillis(), $fromMillis($, (), \"-0500\"), $fromMillis($, (), \"0000\")]",
      Json::null(),
    ) ==
    @json.parse(
      "[\"2018-10-21T13:05:00.000Z\",\"2018-10-21T08:05:00.000-05:00\",\"2018-10-21T13:05:00.000Z\"]",
    ),
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
test "P11：$toMillis 日期 picture 解析增强（官方回归）" {
  // case011: [Y,*-4] width modifier
  assert_true(
    eval_fn("$toMillis(\"201802\", \"[Y,*-4][M01]\")", Json::null()) ==
    Json::number(1517443200000.0),
  )
  // [D1] variable-width + [MNn] named month + [Y0001]
  assert_true(
    eval_fn(
      "$toMillis(\"21 August 2017\", \"[D1] [MNn] [Y0001]\")",
      Json::null(),
    ) ==
    Json::number(1503273600000.0),
  )
  // [YI]/[Yi] roman numeral year
  assert_true(
    eval_fn("$toMillis(\"27 03 MMXVIII\", \"[D1] [M01] [YI]\")", Json::null()) ==
    Json::number(1522108800000.0),
  )
  assert_true(
    eval_fn("$toMillis(\"27 iii MMXVIII\", \"[D1] [Mi] [YI]\")", Json::null()) ==
    Json::number(1522108800000.0),
  )
  // [Da]/[MA] letter-based day/month
  assert_true(
    eval_fn("$toMillis(\"w C mmxviii\", \"[Da] [MA] [Yi]\")", Json::null()) ==
    Json::number(1521763200000.0), // w=23, C=3, mmxviii=2018 -> 2018-03-23
  )
  assert_true(
    eval_fn("$toMillis(\"ae C mmxviii\", \"[Da] [MA] [Yi]\")", Json::null()) ==
    Json::number(1522454400000.0), // ae=31, C=3 -> 2018-03-31
  )
  // [Dw]/[DW] word day + [Yw] word year
  assert_true(
    eval_fn(
      "$toMillis(\"twenty-seventh April 2008\", \"[Dw] [MNn] [Y0001]\")",
      Json::null(),
    ) ==
    Json::number(1209254400000.0),
  )
  assert_true(
    eval_fn(
      "$toMillis(\"TWENTY-SECOND August two thousand and seventeen\", \"[DW] [MNn] [Yw]\")",
      Json::null(),
    ) ==
    Json::number(1503360000000.0),
  )
  assert_true(
    eval_fn(
      "$toMillis(\"Twentieth of August, two thousand and seventeen\", \"[DW] of [MNn], [Yw]\")",
      Json::null(),
    ) ==
    Json::number(1503187200000.0),
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

///|
test "P11：$encodeUrl $decodeUrl $encodeUrlComponent $decodeUrlComponent" {
  // $encodeUrl: 对整个 URL 编码，保留 URL 保留字符
  let encoded_url = eval_fn(
    "$encodeUrl(\"https://mozilla.org/?x=шеллы\")",
    Json::null(),
  )
  assert_true(
    encoded_url ==
    Json::string("https://mozilla.org/?x=%D1%88%D0%B5%D0%BB%D0%BB%D1%8B"),
  )
  // $decodeUrl: 解码百分号编码的 URL
  let decoded_url = eval_fn(
    "$decodeUrl(\"https://mozilla.org/?x=%D1%88%D0%B5%D0%BB%D0%BB%D1%8B\")",
    Json::null(),
  )
  assert_true(decoded_url == Json::string("https://mozilla.org/?x=шеллы"))
  // $encodeUrlComponent: 对组件编码，不保留任何保留字符
  let encoded_comp = eval_fn("$encodeUrlComponent(\"?x=test\")", Json::null())
  assert_true(encoded_comp == Json::string("%3Fx%3Dtest"))
  // $decodeUrlComponent: 解码百分号编码的组件
  let decoded_comp = eval_fn(
    "$decodeUrlComponent(\"%3Fx%3Dtest\")",
    Json::null(),
  )
  assert_true(decoded_comp == Json::string("?x=test"))
}

///|
test "P12：函数数组与 reduce 组合（官方回归）" {
  // 检查数组类型
  assert_true(
    eval_fn(
      "($square := function($x){$x*$x}; [$sum, $square].$type())",
      Json::null(),
    ) ==
    @json.parse("[\"function\",\"function\"]"),
  )
  // case013: reduce + lambda 组合
  assert_true(
    eval_fn(
      "($square := function($x){$x*$x}; $chain := λ($f, $g){λ($x){$g($f($x))}}; $instructions := [$sum, $square]; $sumsq := $instructions ~> $reduce($chain); [1..5] ~> $sumsq())",
      Json::null(),
    ) ==
    Json::number(225.0),
  )
  // case014: chain 内部使用 ~>
  assert_true(
    eval_fn(
      "($square := function($x){$x*$x}; $chain := λ($f, $g){ λ($x){ $x ~> $f ~> $g }}; $instructions := [$sum, $square, $string]; $sumsq := $instructions ~> $reduce($chain); [1..5] ~> $sumsq())",
      Json::null(),
    ) ==
    Json::string("225"),
  )
}

///|
fn eval_error_code(expr : String, data : Json) -> String {
  try {
    let tokens = @lexer.lex(expr)
    let ast = @parser.parse(tokens)
    let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
    @functions.register_builtins(ctx)
    ignore(@evaluator.eval(ast, ctx))
    ""
  } catch {
    @error.JsonataError::RuntimeError(code~, ..) =>
      match code {
        Some(c) => c
        None => ""
      }
    @error.JsonataError::SyntaxError(code~, ..) =>
      match code {
        Some(c) => c
        None => ""
      }
    _ => ""
  }
}

///|
test "regex: D3012 replacement function must return string" {
  // case035: function returning boolean should throw D3012
  assert_eq(
    eval_error_code(
      "$replace(\"Bowler Hat\", /hat/i, function($match) { true })",
      Json::null(),
    ),
    "D3012",
  )
  // case036: function returning number should throw D3012
  assert_eq(
    eval_error_code(
      "$replace(\"Bowler Hat\", /hat/i, function($match) { 42 })",
      Json::null(),
    ),
    "D3012",
  )
  // D1004: capture group out of range
  assert_eq(
    eval_error_code("$replace(\"abracadabra\", /.*?/, \"$1\")", Json::null()),
    "D1004",
  )
}

///|
test "lexer: S0202 unterminated string in non-operand position" {
  // Parser-level: $replace("foo", "o, "rr") -> S0202
  assert_eq(
    eval_error_code("$replace(\"foo\", \"o, \"rr\")", Json::null()),
    "S0202",
  )
}

///|
test "transforms: T2011 update must be object" {
  // case009: update is a number, not object -> T2011
  assert_true(
    error_has_code(
      eval_fn_catch(
        "Account ~> |Order|5|",
        @json.parse("{\"Account\":{\"Order\":[{\"OrderID\":\"o1\"}]}}"),
      ),
      "T2011",
    ),
  )
  // case012: update is an array, not object -> T2011
  assert_true(
    error_has_code(
      eval_fn_catch("{} ~> |$|['one', 'two', 'three']|", Json::null()),
      "T2011",
    ),
  )
}

///|
test "transforms: T2012 delete must be string or array of strings" {
  // case010: update is {} (ok), delete is 5 (number) -> T2012
  assert_true(
    error_has_code(
      eval_fn_catch(
        "Account ~> |Order|{},5|",
        @json.parse("{\"Account\":{\"Order\":[{\"OrderID\":\"o1\"}]}}"),
      ),
      "T2012",
    ),
  )
}

///|
test "parser: S0201/S0213 number after path dot" {
  // case002: $.7a - number followed by ident -> S0201 (unexpected trailing token)
  assert_true(error_has_code(eval_fn_catch("$.7a", Json::null()), "S0201"))
  // case003: $.7 - number at end of path -> S0213 (number not allowed as path step)
  assert_true(error_has_code(eval_fn_catch("$.7", Json::null()), "S0213"))
}

///|
test "hof-reduce: D3050 callback arity < 2" {
  // case008: $reduce with function of arity 1 -> D3050
  assert_true(
    error_has_code(
      eval_fn_catch(
        "(  $seq := 1;  $reduce($seq, function($x){$x}))",
        Json::null(),
      ),
      "D3050",
    ),
  )
}

///|
test "hof-map: T0410 insufficient args" {
  // case001: $map($add) with only 1 arg -> T0410
  assert_true(
    error_has_code(
      eval_fn_catch(
        "(  $data := {    \"one\": [1,2,3,4,5],    \"two\": [5,4,3,2,1]  };  $add := function($x){$x*$x};  $map($add) )  ",
        Json::null(),
      ),
      "T0410",
    ),
  )
}

///|
test "partial-application: T1007/T1008 unknown function with placeholder" {
  // case003: substring(?, 0, ?) - known function name (suggest $) -> T1007
  assert_true(
    error_has_code(eval_fn_catch("substring(?, 0, ?)", Json::null()), "T1007"),
  )
  // case004: unknown(?) - truly unknown name -> T1008
  assert_true(
    error_has_code(eval_fn_catch("unknown(?)", Json::null()), "T1008"),
  )
}
