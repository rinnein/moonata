// JSONata 官方测试套件核心用例移植
// 选取 path/predicate/function/operator/sequence 分类用例

///|
/// 辅助：求值并断言 JSON 结果
fn assert_eval(expr : String, data : Json, expected : Json) -> Unit raise {
  let result = evaluate(expr, data)
  assert_true(result == expected)
}

///|
/// 辅助：从 JSON 字符串构造数据
fn data(s : String) -> Json {
  @json.parse(s) catch {
    _ => Json::null()
  }
}

// ============ 路径表达式 ============

///|
test "官方套件：简单路径访问" {
  let d = data("{\"name\":\"Alice\",\"age\":30}")
  assert_eval("name", d, Json::string("Alice"))
  assert_eval("age", d, Json::number(30.0))
}

///|
test "官方套件：嵌套路径" {
  let d = data("{\"user\":{\"name\":\"Bob\",\"address\":{\"city\":\"NYC\"}}}")
  assert_eval("user.name", d, Json::string("Bob"))
  assert_eval("user.address.city", d, Json::string("NYC"))
}

///|
test "官方套件：Account 样例 quoted field 与路径映射" {
  let d = data(
    "{\"Account\":{\"Account Name\":\"Firefly\",\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"0406654608\",\"Description\":{\"Colour\":\"Purple\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.75},\"Price\":34.45,\"Quantity\":2},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236,\"SKU\":\"0406634348\",\"Description\":{\"Colour\":\"Orange\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.6},\"Price\":21.67,\"Quantity\":1}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"040657863\",\"Description\":{\"Colour\":\"Purple\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.75},\"Price\":34.45,\"Quantity\":4},{\"ProductID\":345664,\"SKU\":\"0406654603\",\"Product Name\":\"Cloak\",\"Description\":{\"Colour\":\"Black\",\"Width\":30,\"Height\":20,\"Depth\":210,\"Weight\":2},\"Price\":107.99,\"Quantity\":1}]}]}}",
  )
  assert_eval("Account.'Account Name'", d, Json::string("Firefly"))
  assert_eval(
    "$sum(Account.Order.Product.(Price * Quantity))",
    d,
    Json::number(336.36),
  )
}

///|
test "官方套件：数组下标" {
  let d = data("[10,20,30,40,50]")
  assert_eval("$[0]", d, Json::number(10.0))
  assert_eval("$[4]", d, Json::number(50.0))
  assert_eval("$[-1]", d, Json::number(50.0))
}

///|
test "官方套件：数组切片" {
  let d = data("[10,20,30,40,50]")
  let result = evaluate("$[1:3]", d)
  debug_inspect(
    result,
    content=(
      #|Array([Number(20), Number(30)])
    ),
  )
}

///|
test "官方套件：通配符 .*" {
  let d = data("{\"a\":1,\"b\":2,\"c\":3}")
  let result = evaluate(".*", d)
  debug_inspect(
    result,
    content=(
      #|Array([Number(1), Number(2), Number(3)])
    ),
  )
}

///|
test "官方套件：递归降序 **" {
  let d = data("{\"a\":{\"b\":{\"c\":1}},\"x\":2}")
  let result = evaluate("$**.c", d)
  debug_inspect(
    result,
    content=(
      #|Number(1)
    ),
  )
}

// ============ 谓词过滤 ============

///|
test "官方套件：布尔谓词过滤" {
  let d = data(
    "[{\"name\":\"A\",\"val\":5},{\"name\":\"B\",\"val\":10},{\"name\":\"C\",\"val\":3}]",
  )
  let result = evaluate("$[@.val > 4]", d)
  debug_inspect(
    result,
    content=(
      #|Array(
      #|  [
      #|    Object({ "name": String("A"), "val": Number(5) }),
      #|    Object({ "name": String("B"), "val": Number(10) }),
      #|  ],
      #|)
    ),
  )
}

///|
test "官方套件：谓词过滤后字段访问" {
  let d = data("[{\"name\":\"A\",\"val\":5},{\"name\":\"B\",\"val\":10}]")
  let result = evaluate("$[@.val > 7].name", d)
  debug_inspect(
    result,
    content=(
      #|String("B")
    ),
  )
}

// ============ 运算符 ============

///|
test "官方套件：算术运算" {
  assert_eval("1 + 2", Json::null(), Json::number(3.0))
  assert_eval("10 - 3", Json::null(), Json::number(7.0))
  assert_eval("4 * 5", Json::null(), Json::number(20.0))
  assert_eval("10 / 2", Json::null(), Json::number(5.0))
}

///|
test "官方套件：比较运算" {
  assert_eval("1 < 2", Json::null(), Json::boolean(true))
  assert_eval("3 = 3", Json::null(), Json::boolean(true))
  assert_eval("3 != 4", Json::null(), Json::boolean(true))
}

///|
test "官方套件：逻辑运算" {
  assert_eval("true && false", Json::null(), Json::boolean(false))
  assert_eval("true || false", Json::null(), Json::boolean(true))
}

///|
test "官方套件：字符串拼接 &" {
  assert_eval(
    "\"Hello\" & \" \" & \"World\"",
    Json::null(),
    Json::string("Hello World"),
  )
}

// ============ 内建函数 ============

///|
test "官方套件：$sum" {
  assert_eval("$sum([1,2,3,4,5])", Json::null(), Json::number(15.0))
}

///|
test "官方套件：$map" {
  let d = data("[1,2,3]")
  let result = evaluate("$map($, function($x) { $x * 2 })", d)
  debug_inspect(
    result,
    content=(
      #|Array([Number(2), Number(4), Number(6)])
    ),
  )
}

///|
test "官方套件：$filter" {
  let d = data("[1,2,3,4,5]")
  let result = evaluate("$filter($, function($x) { $x > 2 })", d)
  debug_inspect(
    result,
    content=(
      #|Array([Number(3), Number(4), Number(5)])
    ),
  )
}

///|
test "官方套件：$reduce" {
  let d = data("[1,2,3,4]")
  let result = evaluate("$reduce($, function($a, $b) { $a + $b })", d)
  assert_true(result == Json::number(10.0))
}

///|
test "官方套件：$count" {
  assert_eval("$count([1,2,3,4,5])", Json::null(), Json::number(5.0))
}

///|
test "官方套件：$keys $values" {
  let d = data("{\"a\":1,\"b\":2}")
  let keys = evaluate("$keys($)", d)
  debug_inspect(
    keys,
    content=(
      #|Array([String("a"), String("b")])
    ),
  )
  let vals = evaluate("$values($)", d)
  debug_inspect(
    vals,
    content=(
      #|Array([Number(1), Number(2)])
    ),
  )
}

///|
test "官方套件：$merge" {
  let d = data("[{\"a\":1},{\"b\":2}]")
  let result = evaluate("$merge($)", d)
  debug_inspect(
    result,
    content=(
      #|Object({ "a": Number(1), "b": Number(2) })
    ),
  )
}

///|
test "官方套件：$type" {
  assert_eval("$type(\"hello\")", Json::null(), Json::string("string"))
  assert_eval("$type(42)", Json::null(), Json::string("number"))
  assert_eval("$type(true)", Json::null(), Json::string("boolean"))
  assert_eval("$type(null)", Json::null(), Json::string("null"))
}

///|
test "官方套件：$string $number $boolean" {
  assert_eval("$string(42)", Json::null(), Json::string("42"))
  assert_eval("$number(\"42\")", Json::null(), Json::number(42.0))
  assert_eval("$boolean(1)", Json::null(), Json::boolean(true))
}

///|
test "官方套件：$contains" {
  assert_eval(
    "$contains(\"hello world\", \"world\")",
    Json::null(),
    Json::boolean(true),
  )
}

///|
test "官方套件：$length" {
  assert_eval("$length(\"hello\")", Json::null(), Json::number(5.0))
  assert_eval("$length([1,2,3])", Json::null(), Json::number(3.0))
}

///|
test "官方套件：$uppercase $lowercase" {
  assert_eval("$uppercase(\"hello\")", Json::null(), Json::string("HELLO"))
  assert_eval("$lowercase(\"WORLD\")", Json::null(), Json::string("world"))
}

///|
test "官方套件：$sort" {
  let d = data("[3,1,4,1,5,9,2,6]")
  let result = evaluate("$sort($)", d)
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
test "官方套件：$reverse" {
  let d = data("[1,2,3]")
  let result = evaluate("$reverse($)", d)
  debug_inspect(
    result,
    content=(
      #|Array([Number(3), Number(2), Number(1)])
    ),
  )
}

///|
test "官方套件：$distinct" {
  let d = data("[1,2,2,3,3,3,4]")
  let result = evaluate("$distinct($)", d)
  debug_inspect(
    result,
    content=(
      #|Array([Number(1), Number(2), Number(3), Number(4)])
    ),
  )
}

// ============ 高级特性 ============

///|
test "官方套件：Lambda 与函数链" {
  let d = data("[1,2,3]")
  let result = evaluate("$map($, function($x) { $x * 2 }) ~> $sum", d)
  debug_inspect(
    result,
    content=(
      #|Number(12)
    ),
  )
}

///|
test "官方套件：分组表达式" {
  let result = evaluate("{ \"name\": \"Alice\", \"age\": 30 }", Json::null())
  debug_inspect(
    result,
    content=(
      #|Object({ "name": String("Alice"), "age": Number(30) })
    ),
  )
}

///|
test "官方套件：绑定表达式" {
  assert_eval("$x := 5; $x * 2", Json::null(), Json::number(10.0))
}

///|
test "官方套件：块表达式" {
  assert_eval("1; 2; 3", Json::null(), Json::number(3.0))
}

///|
test "官方套件：部分应用" {
  let result = evaluate("(function($a, $b) { $a + $b })(5)(3)", Json::null())
  assert_true(result == Json::number(8.0))
}

///|
test "官方套件：& 对象合并" {
  let d = data("{\"a\":{\"x\":1},\"b\":2}")
  let result = evaluate("$ & {\"a\":{\"y\":3},\"c\":4}", d)
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

// ============ 正则函数 ============

///|
test "官方套件：$match 正则匹配" {
  let result = evaluate("$match(\"abc123def\", \"[0-9]+\")", Json::null())
  debug_inspect(
    result,
    content=(
      #|Object({ "match": String("123"), "groups": Array([]) })
    ),
  )
}

///|
test "官方套件：$contains_regex" {
  assert_eval(
    "$contains_regex(\"hello world\", \"world\")",
    Json::null(),
    Json::boolean(true),
  )
}

///|
test "官方套件：$split_regex" {
  let result = evaluate("$split_regex(\"a1b2c3d\", \"[0-9]\")", Json::null())
  debug_inspect(
    result,
    content=(
      #|Array([String("a"), String("b"), String("c"), String("d")])
    ),
  )
}

///|
test "官方套件：$replace_regex" {
  assert_eval(
    "$replace_regex(\"hello world\", \"world\", \"moonbit\")",
    Json::null(),
    Json::string("hello moonbit"),
  )
}
