///|
/// 辅助：从 JSON 字符串构造数据
fn make_data(s : String) -> Json {
  @json.parse(s) catch {
    _ => Json::null()
  }
}

///|
/// 辅助：求值表达式并返回 JSON 结果
fn eval_to_json(expr : String, data : Json) -> Json {
  let result = try {
    let tokens = @lexer.lex(expr)
    let ast = @parser.parse(tokens)
    let ctx = @value.EvalContext::new(@value.JsonataValue::Json(data))
    let r = eval(ast, ctx)
    r.to_json()
  } catch {
    _ => Json::null()
  }
  result
}

///|
test "求值：字面量" {
  assert_true(eval_to_json("\"hello\"", Json::null()) == Json::string("hello"))
  assert_true(eval_to_json("42", Json::null()) == Json::number(42.0))
  assert_true(eval_to_json("true", Json::null()) == Json::boolean(true))
  assert_true(eval_to_json("false", Json::null()) == Json::boolean(false))
  assert_true(eval_to_json("null", Json::null()) == Json::null())
}

///|
test "求值：路径访问" {
  let data = make_data("{\"name\":\"Alice\",\"age\":30}")
  assert_true(eval_to_json("name", data) == Json::string("Alice"))
  assert_true(eval_to_json("age", data) == Json::number(30.0))
}

///|
test "求值：嵌套路径" {
  let data = make_data("{\"user\":{\"name\":\"Bob\"}}")
  assert_true(eval_to_json("user.name", data) == Json::string("Bob"))
}

///|
test "求值：数组下标" {
  let data = make_data("[1,2,3]")
  assert_true(eval_to_json("$[0]", data) == Json::number(1.0))
  assert_true(eval_to_json("$[1]", data) == Json::number(2.0))
}

///|
test "求值：数组切片" {
  let data = make_data("[1,2,3,4,5]")
  let result = eval_to_json("[1:3]", data)
  debug_inspect(
    result,
    content=(
      #|Null
    ),
  )
}

///|
test "求值：算术运算" {
  assert_true(eval_to_json("1 + 2", Json::null()) == Json::number(3.0))
  assert_true(eval_to_json("10 - 3", Json::null()) == Json::number(7.0))
  assert_true(eval_to_json("4 * 5", Json::null()) == Json::number(20.0))
  assert_true(eval_to_json("10 / 2", Json::null()) == Json::number(5.0))
}

///|
test "求值：比较运算" {
  assert_true(eval_to_json("1 < 2", Json::null()) == Json::boolean(true))
  assert_true(eval_to_json("2 < 1", Json::null()) == Json::boolean(false))
  assert_true(eval_to_json("3 = 3", Json::null()) == Json::boolean(true))
  assert_true(eval_to_json("3 != 4", Json::null()) == Json::boolean(true))
}

///|
test "求值：逻辑运算" {
  assert_true(
    eval_to_json("true && false", Json::null()) == Json::boolean(false),
  )
  assert_true(
    eval_to_json("true || false", Json::null()) == Json::boolean(true),
  )
  assert_true(eval_to_json("!true", Json::null()) == Json::boolean(false))
}

///|
test "求值：字符串拼接" {
  assert_true(
    eval_to_json("\"Hello\" & \" World\"", Json::null()) ==
    Json::string("Hello World"),
  )
}

///|
test "求值：序列构造" {
  let result = eval_to_json("[1, 2, 3]", Json::null())
  debug_inspect(
    result,
    content=(
      #|Array([Number(1), Number(2), Number(3)])
    ),
  )
}

///|
test "求值：变量与绑定" {
  let result = eval_to_json("$x := 5; $x * 2", Json::null())
  assert_true(result == Json::number(10.0))
}

///|
test "求值：Undefined 传播" {
  let data = make_data("{\"a\":1}")
  let result = eval_to_json("missing", data)
  assert_true(result == Json::null())
}

///|
test "求值：通配符" {
  let data = make_data("{\"a\":1,\"b\":2}")
  let result = eval_to_json(".*", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(1), Number(2)])
    ),
  )
}

///|
test "求值：分组表达式" {
  let result = eval_to_json(
    "{ \"name\": \"Alice\", \"age\": 30 }",
    Json::null(),
  )
  debug_inspect(
    result,
    content=(
      #|Object({ "name": String("Alice"), "age": Number(30) })
    ),
  )
}

///|
test "求值：块表达式" {
  assert_true(eval_to_json("1; 2; 3", Json::null()) == Json::number(3.0))
}

///|
test "P9.1：谓词过滤绑定 @ 当前项" {
  let data = make_data(
    "[{\"name\":\"A\",\"age\":30},{\"name\":\"B\",\"age\":20}]",
  )
  // 谓词中 @ 应指向当前项，@.age 访问当前项的 age 字段
  let result = eval_to_json("$[@.age > 25]", data)
  debug_inspect(
    result,
    content=(
      #|Object({ "name": String("A"), "age": Number(30) })
    ),
  )
}

///|
test "P9.1：谓词过滤字段访问（无 @ 前缀也应工作）" {
  let data = make_data("[1,2,3,4,5]")
  // 位置过滤：返回索引 2 的元素
  let result = eval_to_json("$[# = 2]", data)
  debug_inspect(
    result,
    content=(
      #|Number(3)
    ),
  )
}

///|
test "P9.1：@ 在分组表达式求值中" {
  let data = make_data(
    "[{\"name\":\"A\",\"val\":1},{\"name\":\"B\",\"val\":2}]",
  )
  // 谓词中用 @ 引用当前项
  let result = eval_to_json("$[@.name = \"A\"].val", data)
  assert_true(result == Json::number(1.0))
}

///|
test "P9.2：& 对象深度合并" {
  let data = make_data("{\"a\":{\"x\":1},\"b\":2}")
  // {"a":{"x":1},"b":2} & {"a":{"y":3},"c":4} => {"a":{"x":1,"y":3},"b":2,"c":4}
  let result = eval_to_json("$ & {\"a\":{\"y\":3},\"c\":4}", data)
  debug_inspect(
    result,
    content=(
      #|Object(
      #|  {
      #|    "a": Object({ "x": Number(1), "y": Number(3) }),
      #|    "b": Number(2),
      #|    "c": Number(4),
      #|  },
      #|)
    ),
  )
}

///|
test "P9.2：& 字符串拼接仍正常" {
  assert_true(
    eval_to_json("\"Hello\" & \" World\"", Json::null()) ==
    Json::string("Hello World"),
  )
}

///|
test "P9.2：部分应用" {
  // function($a, $b) { $a + $b } 部分应用为 function($b) { 5 + $b }
  let result = eval_to_json(
    "(function($a, $b) { $a + $b })(5)(3)",
    Json::null(),
  )
  assert_true(result == Json::number(8.0))
}
