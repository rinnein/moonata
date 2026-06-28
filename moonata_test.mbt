///|
test "facade：evaluate 基础" {
  let result = evaluate("1 + 2", Json::null())
  assert_true(result == Json::number(3.0))
}

///|
test "facade：evaluate 路径" {
  let data = @json.parse("{\"name\":\"Alice\",\"age\":30}")
  let result = evaluate("name", data)
  assert_true(result == Json::string("Alice"))
}

///|
test "facade：evaluate 内建函数" {
  let data = @json.parse("[1,2,3,4,5]")
  let result = evaluate("$sum($)", data)
  assert_true(result == Json::number(15.0))
}

///|
test "facade：compile + run" {
  let compiled = compile("$sum($)")
  let data1 = @json.parse("[1,2,3]")
  let data2 = @json.parse("[10,20,30]")
  assert_true(compiled.run(data1) == Json::number(6.0))
  assert_true(compiled.run(data2) == Json::number(60.0))
}

///|
test "facade：evaluate Lambda" {
  let data = @json.parse("[1,2,3]")
  let result = evaluate("$map($, function($x) { $x * 2 })", data)
  debug_inspect(
    result,
    content=(
      #|Array([Number(2), Number(4), Number(6)])
    ),
  )
}

///|
test "facade：evaluate 分组" {
  let result = evaluate("{ \"name\": \"Alice\", \"age\": 30 }", Json::null())
  debug_inspect(
    result,
    content=(
      #|Object({ "name": String("Alice"), "age": Number(30) })
    ),
  )
}

///|
test "facade：evaluate 绑定" {
  let result = evaluate("$x := 5; $x * 2", Json::null())
  assert_true(result == Json::number(10.0))
}

///|
test "facade：evaluate 字符串拼接" {
  let result = evaluate("\"Hello\" & \" World\"", Json::null())
  assert_true(result == Json::string("Hello World"))
}

///|
test "facade：evaluate 过滤" {
  let data = @json.parse(
    "[{\"name\":\"A\",\"age\":30},{\"name\":\"B\",\"age\":20}]",
  )
  let result = evaluate("$filter($, function($x) { $x.age > 25 })", data)
  debug_inspect(
    result,
    content=(
      #|Object({ "name": String("A"), "age": Number(30) })
    ),
  )
}
