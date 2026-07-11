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
  assert_eval(
    "Account.Order.[Product.Price]",
    d,
    data("[[34.45,21.67],[34.45,107.99]]"),
  )
  assert_eval(
    "Account.Order.Product.(%.OrderID)",
    d,
    data("[\"order103\",\"order103\",\"order104\",\"order104\"]"),
  )
  assert_eval(
    "Account.Order.Product[%.OrderID=\"order104\"].SKU",
    d,
    data("[\"040657863\",\"0406654603\"]"),
  )
  assert_eval(
    "Account.Order.Product.Description.{ \"Item\": Colour & \" \" & %.`Product Name`, \"Discounted\": (%.%.OrderID = \"order103\") ? %.Price / 2 : %.Price }",
    d,
    data(
      "[{\"Item\":\"Purple Bowler Hat\",\"Discounted\":17.225},{\"Item\":\"Orange Trilby hat\",\"Discounted\":10.835},{\"Item\":\"Purple Bowler Hat\",\"Discounted\":34.45},{\"Item\":\"Black Cloak\",\"Discounted\":107.99}]",
    ),
  )
}

///|
test "官方套件：数组构造保留嵌套数组并支持路径映射数组" {
  assert_eval("[1, 2, [3, 4]]", Json::null(), data("[1,2,[3,4]]"))
  let d = data(
    "[{\"epochSeconds\":1578381600,\"value\":3},{\"epochSeconds\":1578381700,\"value\":5}]",
  )
  assert_eval(
    "$.[value,epochSeconds][]",
    d,
    data("[[3,1578381600],[5,1578381700]]"),
  )
  let single = data("[{\"epochSeconds\":1578381600,\"value\":3}]")
  assert_eval("$.[value,epochSeconds][]", single, data("[[3,1578381600]]"))
  let quoted = data(
    "{\"Address\":{\"City\":\"Winchester\"},\"Other\":{\"Alternative.Address\":{\"City\":\"London\"}}}",
  )
  assert_eval(
    "[Address, Other.`Alternative.Address`].City",
    quoted,
    data("[\"Winchester\",\"London\"]"),
  )
  assert_eval(
    "[0,1,2,3,4,5,6,7,8,9][$ % 2 = 0]",
    Json::null(),
    data("[0,2,4,6,8]"),
  )
  assert_eval("\"Red\"[true]", Json::null(), Json::string("Red"))
  assert_eval(
    "[\"Red\"[$$=\"Bus\"], \"White\"[$$=\"Police Car\"]][0]",
    Json::string("Bus"),
    Json::string("Red"),
  )
  assert_eval(
    "[\"Red\"[$$=\"Bus\"], \"White\"[$$=\"Police Car\"]][0]",
    Json::string("Police Car"),
    Json::string("White"),
  )
  assert_eval("[1, 2, 3].$", Json::null(), data("[1,2,3]"))
  assert_eval(
    "and=1 and or=2",
    data("{\"and\":1,\"or\":2}"),
    Json::boolean(true),
  )
  assert_eval("(1; 2; 3;)", Json::null(), Json::number(3.0))
  assert_eval(
    "($a:=1; $b:=2; $c:=($a:=4; $a+$b); $a+$c)",
    Json::null(),
    Json::number(7.0),
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
test "官方套件：多索引数组选择器" {
  assert_eval("[1..10][[1..3,8,-1]]", Json::null(), data("[2,3,4,9,10]"))
  assert_eval("[1..10][[1..3,8,5]]", Json::null(), data("[2,3,4,6,9]"))
  assert_eval(
    "[1..10][[1..3,8,false]]",
    Json::null(),
    data("[1,2,3,4,5,6,7,8,9,10]"),
  )
}

///|
test "官方套件：简单数组选择器逐项索引" {
  assert_eval(
    "nest0.nest1[0]",
    data(
      "{\"nest0\":[{\"nest1\":[1,2]},{\"nest1\":[3,4]},{\"nest1\":[5]},{\"nest1\":[6]}]}",
    ),
    data("[1,3,5,6]"),
  )
  assert_eval(
    "foo.blah.baz.fud[0]",
    data(
      "{\"foo\":{\"blah\":[{\"baz\":{\"fud\":\"hello\"}},{\"baz\":{\"fud\":\"world\"}}]}}",
    ),
    data("[\"hello\",\"world\"]"),
  )
  assert_eval(
    "foo.blah.baz.fud[-1]",
    data(
      "{\"foo\":{\"blah\":[{\"baz\":{\"fud\":\"hello\"}},{\"baz\":{\"fud\":\"world\"}}]}}",
    ),
    data("[\"hello\",\"world\"]"),
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
  assert_eval("\"hello\" < \"world\"", Json::null(), Json::boolean(true))
  assert_eval("null = nothing", data("{}"), Json::boolean(false))
  assert_eval("nothing = nothing", data("{}"), Json::boolean(false))
  assert_eval("1 in [1,2]", Json::null(), Json::boolean(true))
  assert_eval("3 in [1,2]", Json::null(), Json::boolean(false))
  assert_eval(
    "\"world\" in [\"hello\", \"world\"]",
    Json::null(),
    Json::boolean(true),
  )
}

///|
test "官方套件：逻辑运算" {
  assert_eval("true && false", Json::null(), Json::boolean(false))
  assert_eval("true || false", Json::null(), Json::boolean(true))
}

///|
test "官方套件：fallback 运算 ?? 与 ?:" {
  let d = data("{\"foo\":{\"bar\":42},\"empty\":[],\"zero\":[0]}")
  assert_eval("foo.bar ?? 98", d, Json::number(42.0))
  assert_eval("foo.missing ?? 98", d, Json::number(98.0))
  assert_eval("null ?? 42", Json::null(), Json::null())
  assert_eval("false ?? 42", Json::null(), Json::boolean(false))
  assert_eval("false ?: 42", Json::null(), Json::number(42.0))
  assert_eval("0 ?: 42", Json::null(), Json::number(42.0))
  assert_eval("\"\" ?: 42", Json::null(), Json::number(42.0))
  assert_eval("[] ?: 42", Json::null(), Json::number(42.0))
  assert_eval("[0] ?: 42", Json::null(), Json::number(42.0))
  assert_eval("[1] ?: 42", Json::null(), data("[1]"))
  assert_eval("{} ?: 42", Json::null(), Json::number(42.0))
  assert_eval("{\"a\":1} ?: 42", Json::null(), data("{\"a\":1}"))
}

///|
test "官方套件：条件表达式" {
  assert_eval("true ? \"yes\" : \"no\"", Json::null(), Json::string("yes"))
  assert_eval("false ? \"yes\" : \"no\"", Json::null(), Json::string("no"))
  let d = data(
    "{\"Account\":{\"Order\":[{\"Product\":[{\"Price\":34.45},{\"Price\":21.67}]},{\"Product\":[{\"Price\":34.45},{\"Price\":107.99}]}]}}",
  )
  assert_eval(
    "Account.Order.Product.(Price < 30 ? \"Cheap\")",
    d,
    Json::string("Cheap"),
  )
}

///|
test "官方套件：字符串拼接 &" {
  assert_eval(
    "\"Hello\" & \" \" & \"World\"",
    Json::null(),
    Json::string("Hello World"),
  )
  let d0 = data(
    "{\"foo\":{\"blah\":[{\"baz\":{\"fud\":\"hello\"}},{\"baz\":{\"fud\":\"world\"}}]}}",
  )
  assert_eval("foo.(blah[0].baz.fud & none)", d0, Json::string("hello"))
  assert_eval("foo.(none.here & blah[1].baz.fud)", d0, Json::string("world"))
  let d5 = data(
    "{\"Account\":{\"Order\":[{\"Product\":[{\"Price\":34.45},{\"Price\":21.67}]},{\"Product\":[{\"Price\":34.45},{\"Price\":107.99}]}]}}",
  )
  assert_eval(
    "\"Prices: \" & Account.Order.Product.Price",
    d5,
    Json::string("Prices: [34.45,21.67,34.45,107.99]"),
  )
}

// ============ 内建函数 ============

///|
test "官方套件：$sum" {
  assert_eval("$sum([1,2,3,4,5])", Json::null(), Json::number(15.0))
}

///|
test "官方套件：$average" {
  assert_eval("$average([1,2,3])", Json::null(), Json::number(2.0))
  assert_eval("$average(1)", Json::null(), Json::number(1.0))
  let d = data(
    "{\"Account\":{\"Order\":[{\"Product\":[{\"Price\":34.45,\"Quantity\":2},{\"Price\":21.67,\"Quantity\":1}]},{\"Product\":[{\"Price\":34.45,\"Quantity\":4},{\"Price\":107.99,\"Quantity\":1}]}]}}",
  )
  assert_eval(
    "$average(Account.Order.Product.(Price * Quantity))",
    d,
    Json::number(84.09),
  )
}

///|
test "官方套件：$round 使用 half-even 与 precision" {
  assert_eval("$round(2.5)", Json::null(), Json::number(2.0))
  assert_eval("$round(3.5)", Json::null(), Json::number(4.0))
  assert_eval("$round(0.5)", Json::null(), Json::number(0.0))
  assert_eval("$round(-7.5)", Json::null(), Json::number(-8.0))
  assert_eval("$round(-8.5)", Json::null(), Json::number(-8.0))
  assert_eval("$round(4.49, 1)", Json::null(), Json::number(4.5))
  assert_eval("$round(4.525, 2)", Json::null(), Json::number(4.52))
  assert_eval("$round(12345, -2)", Json::null(), Json::number(12300.0))
}

///|
test "官方套件：$ceil" {
  assert_eval("$ceil(3.7)", Json::null(), Json::number(4.0))
  assert_eval("$ceil(-3.7)", Json::null(), Json::number(-3.0))
  assert_eval("$ceil(0)", Json::null(), Json::number(0.0))
}

///|
test "官方套件：$formatBase" {
  assert_eval("$formatBase(100)", Json::null(), Json::string("100"))
  assert_eval("$formatBase(100, 2)", Json::null(), Json::string("1100100"))
  assert_eval("$formatBase(99.5, 2.5)", Json::null(), Json::string("1100100"))
}

///|
test "官方套件：$formatNumber 基础格式" {
  assert_eval(
    "$formatNumber(12345.6, \"#,###.00\")",
    Json::null(),
    Json::string("12,345.60"),
  )
  assert_eval(
    "$formatNumber(123.9, \"9999\")",
    Json::null(),
    Json::string("0124"),
  )
  assert_eval("$formatNumber(0.14, \"01%\")", Json::null(), Json::string("14%"))
  assert_eval(
    "$formatNumber(0.4857, \"###.###‰\")",
    Json::null(),
    Json::string("485.7‰"),
  )
  assert_eval("$formatNumber(-6, \"000\")", Json::null(), Json::string("-006"))
  assert_eval(
    "$formatNumber(123412345678.9, \"9,9,99.99\")",
    Json::null(),
    Json::string("123412345,6,78.90"),
  )
  assert_eval(
    "$formatNumber(1234.5678, \"①①.①①①e①\", {\"zero-digit\": \"⑟\"})",
    Json::null(),
    Json::string("①②.③④⑥e②"),
  )
  assert_eval(
    "$formatNumber(2392.14*(-36.58), \"000,000.000###;###,###.000###\")",
    Json::null(),
    Json::string("87,504.4812"),
  )
  assert_eval(
    "$formatNumber(2, 'AAA.AAA', {'zero-digit': 'A'})",
    Json::null(),
    Json::string("AAC.AAA"),
  )
  assert_eval(
    "$formatNumber(0.1, 'AeAAA', {'zero-digit': 'A'})",
    Json::null(),
    Json::string("Be-AAB"),
  )
}

///|
test "官方套件：不规则整数分组不重复最左组" {
  assert_eval(
    "$formatInteger(1234567890, \"#:###,##0\")",
    Json::null(),
    Json::string("1234:567,890"),
  )
  assert_eval(
    "$formatInteger(1234567890, \"##,##,##0\")",
    Json::null(),
    Json::string("12345,67,890"),
  )
}

///|
test "官方套件：$pad 支持左右填充与循环截断" {
  assert_eval("$pad(\"foo\", 5)", Json::null(), Json::string("foo  "))
  assert_eval("$pad(\"foo\", -5)", Json::null(), Json::string("  foo"))
  assert_eval("$pad(\"foo\", -5, \"#\")", Json::null(), Json::string("##foo"))
  assert_eval("$pad(\"foo\", 5, \"\")", Json::null(), Json::string("foo  "))
  assert_eval(
    "$pad(\"foo\", 8, \"-+\")",
    Json::null(),
    Json::string("foo-+-+-"),
  )
  assert_eval(
    "$pad('a𝄞💩', 7)",
    Json::null(),
    Json::string("a𝄞💩    "),
  )
  assert_eval(
    "$pad('a𝄞💩', 7, '💩')",
    Json::null(),
    Json::string("a𝄞💩💩💩💩💩"),
  )
}

///|
test "官方套件：Unicode 字符串字面量按字符处理" {
  assert_eval(
    "$substring('𝄞💩', 0, 2)",
    Json::null(),
    Json::string("𝄞💩"),
  )
  assert_eval(
    "$substring('𝄞💩', 0, 1)",
    Json::null(),
    Json::string("𝄞"),
  )
  assert_eval(
    "$substring('𝄞💩', 1, 1)",
    Json::null(),
    Json::string("💩"),
  )
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
  assert_eval("$keys({\"foo\":{}})", Json::null(), Json::string("foo"))
  assert_eval(
    "$keys($)",
    data(
      "[{\"Product Name\":\"Cloak\",\"ProductID\":345664,\"SKU\":\"0406654603\",\"Description\":{},\"Price\":107.99,\"Quantity\":1},{\"Product Name\":\"Hat\",\"ProductID\":858383,\"SKU\":\"040657863\",\"Description\":{},\"Price\":34.45,\"Quantity\":4}]",
    ),
    data(
      "[\"Product Name\",\"ProductID\",\"SKU\",\"Description\",\"Price\",\"Quantity\"]",
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
test "官方套件：$sift predicate 参数与空对象省略" {
  assert_eval(
    "$sift({'a':'hello','b':'world','hello':'again'}, function($v,$k,$o){$lookup($o,$v)})",
    Json::null(),
    data("{\"a\":\"hello\"}"),
  )
  assert_eval(
    "$.$sift(function($v){$v.Postcode})",
    data(
      "[{\"a\":{\"Postcode\":\"x\"}},{\"b\":1},{\"c\":{\"Postcode\":\"y\"}}]",
    ),
    data("[{\"a\":{\"Postcode\":\"x\"}},{\"c\":{\"Postcode\":\"y\"}}]"),
  )
}

///|
test "官方套件：$spread 非对象与对象序列" {
  assert_eval(
    "$spread(\"Hello World\")",
    Json::null(),
    Json::string("Hello World"),
  )
  assert_eval(
    "$spread((Product.Description))",
    data(
      "{\"Product\":[{\"Description\":{\"Colour\":\"Purple\",\"Width\":300}},{\"Description\":{\"Height\":200}}]}",
    ),
    data("[{\"Colour\":\"Purple\"},{\"Width\":300},{\"Height\":200}]"),
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
  assert_eval("$number(\"0x12\")", Json::null(), Json::number(18.0))
  assert_eval("$number(\"0B101\")", Json::null(), Json::number(5.0))
  assert_eval("$number(\"0O12\")", Json::null(), Json::number(10.0))
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
  assert_eval("$count([1,2,3])", Json::null(), Json::number(3.0))
}

///|
test "官方套件：$join" {
  assert_eval("$join(\"hello\")", Json::null(), Json::string("hello"))
  assert_eval("$join([\"hello\"])", Json::null(), Json::string("hello"))
  assert_eval(
    "$join([\"hello\", \"world\"])",
    Json::null(),
    Json::string("helloworld"),
  )
}

///|
test "官方套件：$shuffle" {
  assert_eval("$count($shuffle([1..10]))", Json::null(), Json::number(10.0))
  assert_eval(
    "$sort($shuffle([1..10]))",
    Json::null(),
    data("[1,2,3,4,5,6,7,8,9,10]"),
  )
  assert_eval("$shuffle([1])", Json::null(), data("[1]"))
}

///|
test "官方套件：$single predicate" {
  assert_eval(
    "$single([true, false, true], function($v) {$v=false})",
    Json::null(),
    Json::boolean(false),
  )
  assert_eval(
    "$single([\"zero\", \"one\", \"two\"], function($v, $i, $a) {$i=1})",
    Json::null(),
    Json::string("one"),
  )
}

///|
test "官方套件：$uppercase $lowercase" {
  assert_eval("$uppercase(\"hello\")", Json::null(), Json::string("HELLO"))
  assert_eval("$lowercase(\"WORLD\")", Json::null(), Json::string("world"))
}

///|
test "官方套件：$split 空分隔符与限制" {
  assert_eval(
    "$split(\"Hello\", \"\")",
    Json::null(),
    data("[\"H\",\"e\",\"l\",\"l\",\"o\"]"),
  )
  assert_eval(
    "$sum($split(\"12345\", \"\").$number($))",
    Json::null(),
    Json::number(15.0),
  )
  assert_eval("$split(\"a, b, c, d\", \", \", 0)", Json::null(), data("[]"))
}

///|
test "官方套件：零参函数调用使用当前上下文" {
  assert_eval("$number()", Json::number(5.0), Json::number(5.0))
}

///|
test "官方套件：路径函数调用使用当前上下文" {
  assert_eval(
    "Account.Order.Product.\"Product Name\".$uppercase().$substringBefore(\" \")",
    data(
      "{\"Account\":{\"Order\":[{\"Product\":[{\"Product Name\":\"Bowler Hat\"},{\"Product Name\":\"Trilby hat\"}]},{\"Product\":[{\"Product Name\":\"Bowler Hat\"},{\"Product Name\":\"Cloak\"}]}]}}",
    ),
    data("[\"BOWLER\",\"TRILBY\",\"BOWLER\",\"CLOAK\"]"),
  )
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
  assert_eval("$reverse([1])", Json::null(), data("[1]"))
  assert_eval("[[$], [$reverse($)], [$]]", d, data("[[1,2,3],[3,2,1],[1,2,3]]"))
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

///|
test "官方套件：$zip" {
  let result = evaluate("$zip([1,2,3],[4,5,6],[7,8,9])", Json::null())
  debug_inspect(
    result,
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
  // 官方 variables group 回归测试
  assert_eval("$a := 5", Json::null(), Json::number(5.0))
  assert_eval("$a := $b := 5", Json::null(), Json::number(5.0))
  assert_eval("($a := $b := 5; $a)", Json::null(), Json::number(5.0))
  assert_eval("($a := $b := 5; $b)", Json::null(), Json::number(5.0))
  assert_eval(
    "( $foo := \"defined\"; ( $foo := nothing ); $foo )",
    Json::null(),
    Json::string("defined"),
  )
}

///|
test "官方套件：块表达式" {
  assert_eval("1; 2; 3", Json::null(), Json::number(3.0))
}

///|
test "官方套件：部分应用" {
  let result = evaluate("(function($a, $b) { $a + $b })(5, ?)(3)", Json::null())
  assert_true(result == Json::number(8.0))
}

///|
test "官方套件：签名 Lambda 语法与范围映射" {
  assert_eval(
    "λ($arg)<b:b>{$not($arg)}(true)",
    Json::null(),
    Json::boolean(false),
  )
  assert_eval("[1..5]", Json::null(), data("[1,2,3,4,5]"))
  assert_eval(
    "[1..5].function($x,$y)<n-n:n>{$x+$y}(6)",
    Json::null(),
    data("[7,8,9,10,11]"),
  )
  assert_eval(
    "λ($arr, $sep)<a<s>s?:s>{$join($arr, $sep)}([\"a\", \"b\"], \"-\")",
    Json::null(),
    Json::string("a-b"),
  )
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

///|
test "官方套件：正则字面量基础支持" {
  assert_eval(
    "$split(\"ababbxabbcc\", /b+/)",
    Json::null(),
    data("[\"a\",\"a\",\"xa\",\"cc\"]"),
  )
  assert_eval(
    "$contains(\"ababbxabbcc\", /ab+/)",
    Json::null(),
    Json::boolean(true),
  )
  assert_eval(
    "$contains(\"ababbxabbcc\", /ax+/)",
    Json::null(),
    Json::boolean(false),
  )
  assert_eval(
    "$contains(\"Bowler Hat\", /hat/i)",
    Json::null(),
    Json::boolean(true),
  )
  assert_eval(
    "$replace(\"ababbxabbcc\", /b+/, \"yy\")",
    Json::null(),
    Json::string("ayyayyxayycc"),
  )
  assert_eval(
    "$replace(\"ababbxabbcc\", /b+/, \"yy\", 2)",
    Json::null(),
    Json::string("ayyayyxabbcc"),
  )
  assert_eval(
    "$replace(\"John Smith\", /(\\w+)\\s(\\w+)/, \"$2, $1\")",
    Json::null(),
    Json::string("Smith, John"),
  )
  assert_eval(
    "$replace(\"Bowler Hat\", /hat/i, function($match) { \"foo\" })",
    Json::null(),
    Json::string("Bowler foo"),
  )
  assert_eval(
    "$replace(\"Bowler Hat\", /(h)(at)/i, function($match) { $uppercase($match.match) })",
    Json::null(),
    Json::string("Bowler HAT"),
  )
  assert_eval(
    "$map([\"Felicia Saunders\", \"Jimmy Schultz\"], $match(?, /^(\\w*\\s\\w*)/)).match",
    Json::null(),
    data("[\"Felicia Saunders\",\"Jimmy Schultz\"]"),
  )
}

///|
test "官方套件：问号占位偏函数" {
  assert_eval(
    "($domain := $substringAfter(?, \"@\") ~> $substringBefore(?, \".\"); $domain(\"john@example.com\"))",
    Json::null(),
    Json::string("example"),
  )
  assert_eval(
    "($add_suffix := $replace(?, /$/, \"!\"); $add_suffix(\"hello\"))",
    Json::null(),
    Json::string("hello!"),
  )
}

///|
test "官方套件：函数链部分应用参数顺序" {
  assert_eval(
    "\"john@example.com\" ~> $substringAfter(\"@\") ~> $substringBefore(\".\")",
    Json::null(),
    Json::string("example"),
  )
  assert_eval(
    "Account.Order.OrderID ~> $join(\", \")",
    data(
      "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\"},{\"OrderID\":\"order104\"}]}}",
    ),
    Json::string("order103, order104"),
  )
  assert_eval(
    "Account.Order.OrderID ~> $join()",
    data(
      "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\"},{\"OrderID\":\"order104\"}]}}",
    ),
    Json::string("order103order104"),
  )
  assert_eval(
    "( $uppertrim := $trim ~> $uppercase; $uppertrim(\"   Hello    World   \") )",
    Json::null(),
    Json::string("HELLO WORLD"),
  )
  assert_eval(
    "$decodeUrl(\"https://mozilla.org/?x=%D1%88%D0%B5%D0%BB%D0%BB%D1%8B\")",
    Json::null(),
    Json::string("https://mozilla.org/?x=шеллы"),
  )
  assert_eval(
    "$encodeUrl(\"https://mozilla.org/?x=шеллы\")",
    Json::null(),
    Json::string("https://mozilla.org/?x=%D1%88%D0%B5%D0%BB%D0%BB%D1%8B"),
  )
  assert_eval(
    "$decodeUrlComponent(\"%3Fx%3Dtest\")",
    Json::null(),
    Json::string("?x=test"),
  )
  assert_eval(
    "$encodeUrlComponent(\"?x=test\")",
    Json::null(),
    Json::string("%3Fx%3Dtest"),
  )
}

// ============ lambdas 递归可见性 ============

///|
test "官方套件：lambdas 递归 lambda 可见性" {
  // $range 递归调用：省略步长参数时传入 undefined，$step?$step:1 返回 1
  assert_eval(
    "(  $range := function($start, $end, $step) { (    $step:=($step?$step:1);    $start+$step > $end ? $start : $append($start, $range($start+$step, $end, $step))   )};  $range(0,15))        ",
    Json::null(),
    data("[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]"),
  )
}

// ============ flattening `[]` 语义 ============

///|
test "官方套件：flattening [] 保持数组" {
  let d = data(
    "{\"Phone\":[{\"type\":\"home\",\"number\":\"0203 544 1234\"},{\"type\":\"office\",\"number\":\"01962 001234\"},{\"type\":\"office\",\"number\":\"01962 001235\"},{\"type\":\"mobile\",\"number\":\"077 7700 1234\"}]}",
  )
  // Phone[type="mobile"][].number — [] 后 .number 应保持数组
  assert_eval("Phone[type=\"mobile\"][].number", d, data("[\"077 7700 1234\"]"))
  // Phone[][type="mobile"].number — [] 前 filter 再 .number 应保持数组
  assert_eval("Phone[][type=\"mobile\"].number", d, data("[\"077 7700 1234\"]"))
  // $[][type='command'] — 根路径 [] 后 filter 保持数组
  assert_eval(
    "$[][type=\"command\"]",
    data("[{\"type\":\"command\"},{\"type\":\"commands\"}]"),
    data("[{\"type\":\"command\"}]"),
  )
  // Phone{type: number[]} — 分组内 [] 合并展平
  assert_eval(
    "Phone{type: number[]}",
    d,
    data(
      "{\"home\":[\"0203 544 1234\"],\"office\":[\"01962 001234\",\"01962 001235\"],\"mobile\":[\"077 7700 1234\"]}",
    ),
  )
}

///|
test "官方套件：object-constructor 分组聚合 per-group 求值" {
  let d = data(
    "{\"Phone\":[{\"type\":\"home\",\"number\":\"0203 544 1234\"},{\"type\":\"office\",\"number\":\"01962 001234\"},{\"type\":\"office\",\"number\":\"01962 001235\"},{\"type\":\"mobile\",\"number\":\"077 7700 1234\"}]}",
  )
  // $join 应在每组上求值，而不是 per-item
  assert_eval(
    "Phone{type: $join(number, \", \"), \"phone\":number}",
    d,
    data(
      "{\"home\":\"0203 544 1234\",\"mobile\":\"077 7700 1234\",\"office\":\"01962 001234, 01962 001235\",\"phone\":[\"0203 544 1234\",\"01962 001234\",\"01962 001235\",\"077 7700 1234\"]}",
    ),
  )
}

// ============ predicates 谓词过滤后索引 ============

///|
test "官方套件：谓词过滤后 [0] 保持逐元素语义" {
  let d = data(
    "{\"Account\":{\"Order\":[{\"Product\":[{\"Product Name\":\"Bowler Hat\",\"Description\":{\"Colour\":\"Purple\"},\"Price\":34.45},{\"Product Name\":\"Trilby hat\",\"Description\":{\"Colour\":\"Orange\"},\"Price\":21.67}]},{\"Product\":[{\"Product Name\":\"Bowler Hat\",\"Description\":{\"Colour\":\"Purple\"},\"Price\":34.45},{\"Product Name\":\"Cloak\",\"Description\":{\"Colour\":\"Black\"},\"Price\":107.99}]}]}}",
  )
  // Product[$filter][0].Price 应返回每个 Order 中过滤后的第一个 Product 的 Price
  assert_eval(
    "Account.Order.Product[$lowercase(Description.Colour) = \"purple\"][0].Price",
    d,
    data("[34.45,34.45]"),
  )
}

///|
test "官方套件：tuple stream 位置绑定随过滤和排序传播" {
  let nums = data("[3,1,4,1,5,9]")
  assert_eval("$#$pos[$pos<3]", nums, data("[3,1,4]"))
  assert_eval("$#$pos[$pos<3]^($)", nums, data("[1,3,4]"))
  assert_eval("$#$pos[$pos<3]^(>$)", nums, data("[4,3,1]"))
  assert_eval("$#$pos[$pos<3]^($)[-1]", nums, Json::number(4.0))
}

///|
test "官方套件：tuple stream 位置绑定随路径展平和排序传播" {
  let d = data(
    "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383},{\"Product Name\":\"Cloak\",\"ProductID\":345664}]}]}}",
  )
  assert_eval(
    "Account.Order#$o.Product^(ProductID).{ 'Product': `Product Name`, 'Order Index': $o }",
    d,
    data(
      "[{\"Order Index\":1,\"Product\":\"Cloak\"},{\"Order Index\":0,\"Product\":\"Trilby hat\"},{\"Order Index\":0,\"Product\":\"Bowler Hat\"},{\"Order Index\":1,\"Product\":\"Bowler Hat\"}]",
    ),
  )
}

///|
test "官方套件：transforms per-item update 求值" {
  let d = data(
    "{\"Account\":{\"Account Name\":\"Firefly\",\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"0406654608\",\"Description\":{\"Colour\":\"Purple\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.75},\"Price\":34.45,\"Quantity\":2},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236,\"SKU\":\"046634348\",\"Description\":{\"Colour\":\"Orange\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.6},\"Price\":21.67,\"Quantity\":1}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"040657863\",\"Description\":{\"Colour\":\"Purple\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.75},\"Price\":34.45,\"Quantity\":4}]}]}}",
  )
  // 每个匹配的 Product 都按自身上下文求值 update，添加 Total 字段
  assert_eval(
    "$ ~> |Account.Order.Product|{\"Total\":Price*Quantity}|",
    d,
    data(
      "{\"Account\":{\"Account Name\":\"Firefly\",\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"0406654608\",\"Description\":{\"Colour\":\"Purple\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.75},\"Price\":34.45,\"Quantity\":2,\"Total\":68.9},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236,\"SKU\":\"046634348\",\"Description\":{\"Colour\":\"Orange\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.6},\"Price\":21.67,\"Quantity\":1,\"Total\":21.67}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"040657863\",\"Description\":{\"Colour\":\"Purple\",\"Width\":300,\"Height\":200,\"Depth\":210,\"Weight\":0.75},\"Price\":34.45,\"Quantity\":4,\"Total\":137.8}]}]}}",
    ),
  )
}

///|
test "官方套件：transforms per-item update + delete" {
  let d = data(
    "{\"items\":[{\"name\":\"A\",\"price\":10,\"temp\":\"x\"},{\"name\":\"B\",\"price\":20,\"temp\":\"y\"}]}",
  )
  // update 添加 total，delete 移除 temp
  assert_eval(
    "$ ~> |items|{\"total\":price*2},[\"temp\"]|",
    d,
    data(
      "{\"items\":[{\"name\":\"A\",\"price\":10,\"total\":20},{\"name\":\"B\",\"price\":20,\"total\":40}]}",
    ),
  )
}

///|
test "官方套件：transforms 递归下降 + 过滤匹配" {
  let d = data("{\"hi\":\"world\",\"bye\":null}")
  // `** ['hi']` 匹配所有值（字符串字面量 'hi' 在过滤上下文中恒为 truthy），
  // 但只有 Object 类型匹配项能被 update/delete 修改
  assert_eval(
    "$ ~> | ** ['hi'] | {'hello': hi}, ['hi'] |",
    d,
    data("{\"hello\":\"world\",\"bye\":null}"),
  )
}

///|
test "官方套件：transforms 中间数组展平" {
  let d = data(
    "{\"orders\":[{\"id\":\"o1\",\"items\":[{\"name\":\"A\",\"price\":10},{\"name\":\"B\",\"price\":20}]},{\"id\":\"o2\",\"items\":[{\"name\":\"C\",\"price\":30}]}]}",
  )
  // 路径 orders.items 经过 Array 中间步时自动展平，对每个 item 应用 update
  assert_eval(
    "$ ~> |orders.items|{\"price_with_tax\":price*1.1}|",
    d,
    data(
      "{\"orders\":[{\"id\":\"o1\",\"items\":[{\"name\":\"A\",\"price\":10,\"price_with_tax\":11},{\"name\":\"B\",\"price\":20,\"price_with_tax\":22}]},{\"id\":\"o2\",\"items\":[{\"name\":\"C\",\"price\":30,\"price_with_tax\":33}]}]}",
    ),
  )
}

///|
test "官方套件：parent-operator map 步数组构造展平" {
  let d = data(
    "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383},{\"Product Name\":\"Cloak\",\"ProductID\":345664}]}]}}",
  )
  // .[expr] with parent operator (%) should flatten (tuple stream mode)
  assert_eval(
    "Account.Order.Product.[`Product Name`, %.OrderID]",
    d,
    data(
      "[\"Bowler Hat\",\"order103\",\"Trilby hat\",\"order103\",\"Bowler Hat\",\"order104\",\"Cloak\",\"order104\"]",
    ),
  )
  // .[expr] with single parent field should also flatten
  assert_eval(
    "Account.Order.Product.[%.OrderID]",
    d,
    data("[\"order103\",\"order103\",\"order104\",\"order104\"]"),
  )
}

///|
test "官方套件：transforms 路径含 Eval 步 (parenthesized expression)" {
  let d = data(
    "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"Description\":{\"Colour\":\"Purple\"}},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236,\"Description\":{\"Colour\":\"Orange\"}}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"Description\":{\"Colour\":\"Purple\"}}]}]}}",
  )
  // (Account.Order.Product)[0] uses Eval step from parenthesized expression
  // Transform should apply to the first Product
  assert_eval(
    "$ ~> |(Account.Order.Product)[0]|{\"Description\":\"blah\"}|",
    d,
    data(
      "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"Description\":\"blah\"},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236,\"Description\":{\"Colour\":\"Orange\"}}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"Description\":{\"Colour\":\"Purple\"}}]}]}}",
    ),
  )
}

///|
test "官方套件：joins tuple stream group 聚合 reduce" {
  let d = data(
    "{\"Employee\":[{\"SSN\":\"496913021\",\"FirstName\":\"Fred\",\"Surname\":\"Smith\"},{\"SSN\":\"496737199\",\"FirstName\":\"Darren\",\"Surname\":\"Cruse\"},{\"SSN\":\"496306525\",\"FirstName\":\"Hugh\",\"Surname\":\"Jones\"}],\"Contact\":[{\"ssn\":\"496913021\",\"Phone\":[{\"type\":\"home\",\"number\":\"0203 544 1234\"},{\"type\":\"office\",\"number\":\"01962 001234\"},{\"type\":\"mobile\",\"number\":\"077 7700 1234\"}]},{\"ssn\":\"496737199\",\"Phone\":[{\"type\":\"home\",\"number\":\"3146458343\"},{\"type\":\"mobile\",\"number\":\"315 782 9279\"}]},{\"ssn\":\"496306525\",\"Phone\":[{\"type\":\"home\",\"number\":\"0280 564 6543\"}]},{\"ssn\":\"496306525\",\"Phone\":[{\"type\":\"office\",\"number\":\"0280 864 8643\"}]},{\"ssn\":\"496306525\",\"Phone\":[{\"type\":\"mobile\",\"number\":\"07735 853535\"}]}]}",
  )
  // Hugh Jones has 3 separate Contact entries; group should reduce all 3
  assert_eval(
    "Employee@$e.Contact@$c[$c.ssn = $e.SSN]{ $e.(FirstName & \" \" & Surname): $join($c.Phone.number, \", \") }",
    d,
    data(
      "{\"Fred Smith\":\"0203 544 1234, 01962 001234, 077 7700 1234\",\"Darren Cruse\":\"3146458343, 315 782 9279\",\"Hugh Jones\":\"0280 564 6543, 0280 864 8643, 07735 853535\"}",
    ),
  )
  // Phone[type='mobile'] filter on reduced @ (3 Contacts for Hugh)
  assert_eval(
    "Employee@$e.(Contact)[ssn = $e.SSN]{ $e.FirstName: Phone[type=\"mobile\"].number }",
    d,
    data(
      "{\"Fred\":\"077 7700 1234\",\"Darren\":\"315 782 9279\",\"Hugh\":\"07735 853535\"}",
    ),
  )
}

///|
test "官方套件：sort 后 focus 绑定变量传播" {
  let d = data(
    "{\"Employee\":[{\"SSN\":\"496913021\",\"FirstName\":\"Fred\",\"Surname\":\"Smith\"},{\"SSN\":\"496737199\",\"FirstName\":\"Darren\",\"Surname\":\"Cruse\"},{\"SSN\":\"496306525\",\"FirstName\":\"Hugh\",\"Surname\":\"Jones\"}]}",
  )
  // After sort ^($e.Surname), $e should still be accessible
  assert_eval(
    "Employee@$e^($e.Surname).$e.Surname",
    d,
    data("[\"Cruse\",\"Jones\",\"Smith\"]"),
  )
}

///|
test "官方套件：arrayify 在 Sort 内嵌路径中保持数组包装" {
  let nums = data("[3,1,4,1,5,9]")
  // [] in the middle of path (inside Sort's expr) should force array wrapping
  assert_eval("$#$pos[][$pos<3]^($)[-1]", nums, data("[4]"))
  // Without []: returns scalar
  assert_eval("$#$pos[$pos<3]^($)[-1]", nums, Json::number(4.0))
}

///|
test "官方套件：parenthesized 路径保留祖先链供父级过滤" {
  let d = data(
    "{\"Account\":{\"Order\":[{\"OrderID\":\"order103\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"0406654608\"},{\"Product Name\":\"Trilby hat\",\"ProductID\":858236,\"SKU\":\"0406634348\"}]},{\"OrderID\":\"order104\",\"Product\":[{\"Product Name\":\"Bowler Hat\",\"ProductID\":858383,\"SKU\":\"040657863\"},{\"ProductID\":345664,\"SKU\":\"0406654603\",\"Product Name\":\"Cloak\"}]}]}}",
  )
  // (expr)[%.field] should access parent of each item in the parenthesized result
  assert_eval(
    "(Account.Order.Product)[%.OrderID='order104'].SKU",
    d,
    data("[\"040657863\",\"0406654603\"]"),
  )
  // (expr).%.field should access parent field for each item
  assert_eval(
    "(Account.Order.Product).%.OrderID",
    d,
    data("[\"order103\",\"order103\",\"order104\",\"order104\"]"),
  )
}

///|
test "官方套件：dual-focus $keys(%) 父级键列表在 tuple stream + map 内解析" {
  // After multiple focus steps, % inside a construct should resolve to the
  // parent object (not the key name), so $keys(%) returns the object's keys.
  // Fixes parent-operator cases 24/26: $keys(%) and $keys(%.%) in multi-focus
  // paths now use step_frame ancestors for correct parent resolution.
  let d = data(
    "{\"library\":{\"books\":[{\"isbn\":\"978-0\"},{\"isbn\":\"978-1\"}],\"loans\":[{\"isbn\":\"978-0\"},{\"isbn\":\"978-1\"}],\"customers\":[{\"id\":\"c1\"},{\"id\":\"c2\"}]}}",
  )
  // library.loans@$L.books@$B[$L.isbn=$B.isbn]: two focus steps + join filter
  // $keys(%) should return keys of the library object
  assert_eval(
    "library.loans@$L.books@$B[$L.isbn=$B.isbn].{ \"parent\": $keys(%) }",
    d,
    data(
      "[{\"parent\":[\"books\",\"loans\",\"customers\"]},{\"parent\":[\"books\",\"loans\",\"customers\"]}]",
    ),
  )
}

///|
test "官方套件：dual-focus tuple stream 路径从 focus 步输入继续" {
  // After @$var, subsequent path steps evaluate from the input to the focus
  // step (not the focused item, not the original root).  This matches
  // JSONata-js tuple stream semantics where @ stays unchanged.
  let d = data(
    "{\"lib\":{\"books\":[{\"isbn\":\"978-0\",\"title\":\"SICP\"},{\"isbn\":\"978-1\",\"title\":\"Compilers\"}],\"loans\":[{\"isbn\":\"978-0\"},{\"isbn\":\"978-1\"}]}}",
  )
  // lib.loans@$L.books@$B[$L.isbn=$B.isbn]: dual focus + join filter
  // Each loan produces books, filtered by isbn match → 1 match per loan
  assert_eval(
    "lib.loans@$L.books@$B[$L.isbn=$B.isbn].{ \"title\": $B.title }",
    d,
    data("[{\"title\":\"SICP\"},{\"title\":\"Compilers\"}]"),
  )
}
