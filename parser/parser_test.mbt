///|
/// 辅助：解析表达式字符串并返回 AST。
fn parse_str(s : String) -> @ast.Ast raise @error.JsonataError {
  let tokens = @lexer.lex(s)
  parse(tokens)
}

///|
test "解析：字面量" {
  debug_inspect(
    parse_str("\"hello\""),
    content=(
      #|String("hello")
    ),
  )
  debug_inspect(
    parse_str("42"),
    content=(
      #|Number(42)
    ),
  )
  debug_inspect(
    parse_str("3.14"),
    content=(
      #|Number(3.14)
    ),
  )
  debug_inspect(
    parse_str("true"),
    content=(
      #|Boolean(true)
    ),
  )
  debug_inspect(
    parse_str("false"),
    content=(
      #|Boolean(false)
    ),
  )
  debug_inspect(
    parse_str("null"),
    content=(
      #|Null
    ),
  )
}

///|
test "解析：标识符路径" {
  debug_inspect(
    parse_str("foo"),
    content=(
      #|Path([{ kind: Name("foo"), stage: Single }])
    ),
  )
  debug_inspect(
    parse_str("foo.bar"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Name("bar"), stage: Single },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo.bar.baz"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Name("bar"), stage: Single },
      #|    { kind: Name("baz"), stage: Single },
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：数组下标与切片" {
  debug_inspect(
    parse_str("foo[0]"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Index(0), stage: Single },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo[1:3]"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Slice(Some(1), Some(3)), stage: Single },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo[:3]"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Slice(None, Some(3)), stage: Single },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo[1:]"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Slice(Some(1), None), stage: Single },
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：谓词过滤" {
  debug_inspect(
    parse_str("foo[bar]"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    {
      #|      kind: Filter(Path([{ kind: Name("bar"), stage: Single }])),
      #|      stage: Single,
      #|    },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo[price > 10]"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    {
      #|      kind: Filter(
      #|        Binary(
      #|          op=">",
      #|          lhs=Path([{ kind: Name("price"), stage: Single }]),
      #|          rhs=Number(10),
      #|        ),
      #|      ),
      #|      stage: Single,
      #|    },
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：通配符与递归" {
  debug_inspect(
    parse_str("foo.*"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Wildcard, stage: Single },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo.**"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Wildcard, stage: Recursive },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo**"),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single },
      #|    { kind: Wildcard, stage: Recursive },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("**"),
    content=(
      #|Path([{ kind: Wildcard, stage: Recursive }])
    ),
  )
}

///|
test "解析：算术表达式" {
  debug_inspect(
    parse_str("1 + 2"),
    content=(
      #|Binary(op="+", lhs=Number(1), rhs=Number(2))
    ),
  )
  debug_inspect(
    parse_str("1 + 2 * 3"),
    content=(
      #|Binary(
      #|  op="+",
      #|  lhs=Number(1),
      #|  rhs=Binary(op="*", lhs=Number(2), rhs=Number(3)),
      #|)
    ),
  )
  debug_inspect(
    parse_str("(1 + 2) * 3"),
    content=(
      #|Binary(
      #|  op="*",
      #|  lhs=Binary(op="+", lhs=Number(1), rhs=Number(2)),
      #|  rhs=Number(3),
      #|)
    ),
  )
  debug_inspect(
    parse_str("10 / 2 - 1"),
    content=(
      #|Binary(
      #|  op="-",
      #|  lhs=Binary(op="/", lhs=Number(10), rhs=Number(2)),
      #|  rhs=Number(1),
      #|)
    ),
  )
}

///|
test "解析：比较与逻辑" {
  debug_inspect(
    parse_str("a = b"),
    content=(
      #|Binary(
      #|  op="=",
      #|  lhs=Path([{ kind: Name("a"), stage: Single }]),
      #|  rhs=Path([{ kind: Name("b"), stage: Single }]),
      #|)
    ),
  )
  debug_inspect(
    parse_str("a != b"),
    content=(
      #|Binary(
      #|  op="!=",
      #|  lhs=Path([{ kind: Name("a"), stage: Single }]),
      #|  rhs=Path([{ kind: Name("b"), stage: Single }]),
      #|)
    ),
  )
  debug_inspect(
    parse_str("a < b && b < c"),
    content=(
      #|Binary(
      #|  op="&&",
      #|  lhs=Binary(
      #|    op="<",
      #|    lhs=Path([{ kind: Name("a"), stage: Single }]),
      #|    rhs=Path([{ kind: Name("b"), stage: Single }]),
      #|  ),
      #|  rhs=Binary(
      #|    op="<",
      #|    lhs=Path([{ kind: Name("b"), stage: Single }]),
      #|    rhs=Path([{ kind: Name("c"), stage: Single }]),
      #|  ),
      #|)
    ),
  )
  debug_inspect(
    parse_str("a || b"),
    content=(
      #|Binary(
      #|  op="||",
      #|  lhs=Path([{ kind: Name("a"), stage: Single }]),
      #|  rhs=Path([{ kind: Name("b"), stage: Single }]),
      #|)
    ),
  )
}

///|
test "解析：字符串拼接" {
  debug_inspect(
    parse_str("\"Hello\" & name"),
    content=(
      #|Binary(
      #|  op="&",
      #|  lhs=String("Hello"),
      #|  rhs=Path([{ kind: Name("name"), stage: Single }]),
      #|)
    ),
  )
}

///|
test "解析：序列构造" {
  debug_inspect(
    parse_str("[1, 2, 3]"),
    content=(
      #|Construct([Number(1), Number(2), Number(3)])
    ),
  )
  debug_inspect(
    parse_str("[]"),
    content=(
      #|Construct([])
    ),
  )
  debug_inspect(
    parse_str("[foo, bar.baz]"),
    content=(
      #|Construct(
      #|  [
      #|    Path([{ kind: Name("foo"), stage: Single }]),
      #|    Path(
      #|      [
      #|        { kind: Name("bar"), stage: Single },
      #|        { kind: Name("baz"), stage: Single },
      #|      ],
      #|    ),
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：分组表达式" {
  debug_inspect(
    parse_str("{ \"name\": \"Alice\" }"),
    content=(
      #|Group([(String("name"), String("Alice"))])
    ),
  )
  debug_inspect(
    parse_str("{ name: foo.bar, age: 30 }"),
    content=(
      #|Group(
      #|  [
      #|    (
      #|      Path([{ kind: Name("name"), stage: Single }]),
      #|      Path(
      #|        [
      #|          { kind: Name("foo"), stage: Single },
      #|          { kind: Name("bar"), stage: Single },
      #|        ],
      #|      ),
      #|    ),
      #|    (Path([{ kind: Name("age"), stage: Single }]), Number(30)),
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：变量" {
  debug_inspect(
    parse_str("$foo"),
    content=(
      #|Var("foo")
    ),
  )
  debug_inspect(
    parse_str("$"),
    content=(
      #|Var("")
    ),
  )
  debug_inspect(
    parse_str("$$"),
    content=(
      #|Var("$$")
    ),
  )
  debug_inspect(
    parse_str("@"),
    content=(
      #|Var("@")
    ),
  )
}

///|
test "解析：条件表达式" {
  debug_inspect(
    parse_str("$x > 0 ? \"yes\" : \"no\""),
    content=(
      #|Conditional(
      #|  condition=Binary(op=">", lhs=Var("x"), rhs=Number(0)),
      #|  consequent=String("yes"),
      #|  alternate=Some(String("no")),
      #|)
    ),
  )
  debug_inspect(
    parse_str("$x ? $x"),
    content=(
      #|Conditional(condition=Var("x"), consequent=Var("x"), alternate=None)
    ),
  )
}

///|
test "解析：函数调用" {
  debug_inspect(
    parse_str("$sum([1, 2, 3])"),
    content=(
      #|Apply(
      #|  func=Var("sum"),
      #|  args=[Construct([Number(1), Number(2), Number(3)])],
      #|)
    ),
  )
  debug_inspect(
    parse_str("$map(data, function($x) { $x * 2 })"),
    content=(
      #|Apply(
      #|  func=Var("map"),
      #|  args=[
      #|    Path([{ kind: Name("data"), stage: Single }]),
      #|    Lambda(
      #|      params=["x"],
      #|      body=Binary(op="*", lhs=Var("x"), rhs=Number(2)),
      #|      signature=None,
      #|    ),
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：Lambda" {
  debug_inspect(
    parse_str("function($x) { $x }"),
    content=(
      #|Lambda(params=["x"], body=Var("x"), signature=None)
    ),
  )
  debug_inspect(
    parse_str("function($a, $b) { $a + $b }"),
    content=(
      #|Lambda(
      #|  params=["a", "b"],
      #|  body=Binary(op="+", lhs=Var("a"), rhs=Var("b")),
      #|  signature=None,
      #|)
    ),
  )
  debug_inspect(
    parse_str("λ($x)<n:n>{ $x }"),
    content=(
      #|Lambda(
      #|  params=["x"],
      #|  body=Var("x"),
      #|  signature=Some("<ident(n):ident(n)>"),
      #|)
    ),
  )
  debug_inspect(
    parse_str("[1..3].λ($x)<n:n>{ $x }()"),
    content=(
      #|Path(
      #|  [
      #|    {
      #|      kind: Eval(Construct([Binary(op="..", lhs=Number(1), rhs=Number(3))])),
      #|      stage: Single,
      #|    },
      #|    {
      #|      kind: Map(
      #|        Apply(
      #|          func=Lambda(
      #|            params=["x"],
      #|            body=Var("x"),
      #|            signature=Some("<ident(n):ident(n)>"),
      #|          ),
      #|          args=[Var("")],
      #|        ),
      #|      ),
      #|      stage: Single,
      #|    },
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：函数链" {
  debug_inspect(
    parse_str("foo ~> bar"),
    content=(
      #|Chain(
      #|  [
      #|    Path([{ kind: Name("foo"), stage: Single }]),
      #|    Path([{ kind: Name("bar"), stage: Single }]),
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo ~> bar ~> baz"),
    content=(
      #|Chain(
      #|  [
      #|    Path([{ kind: Name("foo"), stage: Single }]),
      #|    Path([{ kind: Name("bar"), stage: Single }]),
      #|    Path([{ kind: Name("baz"), stage: Single }]),
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：排序表达式" {
  debug_inspect(
    parse_str("foo^(name)"),
    content=(
      #|Sort(
      #|  expr=Path([{ kind: Name("foo"), stage: Single }]),
      #|  terms=[
      #|    {
      #|      expr: Path([{ kind: Name("name"), stage: Single }]),
      #|      descending: false,
      #|    },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    parse_str("foo^(-price, name)"),
    content=(
      #|Sort(
      #|  expr=Path([{ kind: Name("foo"), stage: Single }]),
      #|  terms=[
      #|    {
      #|      expr: Path([{ kind: Name("price"), stage: Single }]),
      #|      descending: true,
      #|    },
      #|    {
      #|      expr: Path([{ kind: Name("name"), stage: Single }]),
      #|      descending: false,
      #|    },
      #|  ],
      #|)
    ),
  )
}

///|
test "解析：绑定表达式" {
  debug_inspect(
    parse_str("$x := 5; $x * 2"),
    content=(
      #|Bind(
      #|  name="x",
      #|  value=Number(5),
      #|  body=Binary(op="*", lhs=Var("x"), rhs=Number(2)),
      #|)
    ),
  )
}

///|
test "解析：块表达式" {
  debug_inspect(
    parse_str("1; 2; 3"),
    content=(
      #|Block([Number(1), Number(2), Number(3)])
    ),
  )
}

///|
test "解析：一元运算" {
  debug_inspect(
    parse_str("-5"),
    content=(
      #|Number(-5)
    ),
  )
  debug_inspect(
    parse_str("!true"),
    content=(
      #|Unary(op="!", expr=Boolean(true))
    ),
  )
}

///|
test "解析：in 运算符" {
  debug_inspect(
    parse_str("\"hello\" in names"),
    content=(
      #|Binary(
      #|  op="in",
      #|  lhs=String("hello"),
      #|  rhs=Path([{ kind: Name("names"), stage: Single }]),
      #|)
    ),
  )
  debug_inspect(
    parse_str("in in names"),
    content=(
      #|Binary(
      #|  op="in",
      #|  lhs=Path([{ kind: Name("in"), stage: Single }]),
      #|  rhs=Path([{ kind: Name("names"), stage: Single }]),
      #|)
    ),
  )
}

///|
test "解析：语法错误" {
  let result = try {
    ignore(parse_str("1 +"))
    false
  } catch {
    _ => true
  }
  assert_true(result)
}
