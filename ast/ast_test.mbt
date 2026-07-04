///|
test "Ast 字面量构造与相等" {
  assert_true(Ast::String("hello") == Ast::String("hello"))
  assert_true(Ast::Number(3.14) == Ast::Number(3.14))
  assert_true(Ast::Boolean(true) == Ast::Boolean(true))
  assert_true(Ast::Null == Ast::Null)
}

///|
test "Ast 字面量不等" {
  assert_true(Ast::String("a") != Ast::String("b"))
  assert_true(Ast::Number(1.0) != Ast::Number(2.0))
  assert_true(Ast::Boolean(true) != Ast::Boolean(false))
}

///|
test "Ast 路径构造与相等" {
  let path = Ast::Path([name_step("foo"), name_step("bar")])
  let path2 = Ast::Path([name_step("foo"), name_step("bar")])
  assert_true(path == path2)
  debug_inspect(
    path,
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("foo"), stage: Single, focus: None, tuple: false },
      #|    { kind: Name("bar"), stage: Single, focus: None, tuple: false },
      #|  ],
      #|)
    ),
  )
}

///|
test "Ast 路径步种类" {
  let steps = [
    name_step("a"),
    wildcard_step(),
    wildcard_step(recursive=true),
    name_step("b", recursive=true),
    Step::new(kind=StepKind::Index(0), stage=StepStage::Single),
    Step::new(kind=StepKind::Slice(Some(1), None), stage=StepStage::Single),
    Step::new(
      kind=StepKind::Filter(Ast::Boolean(true)),
      stage=StepStage::Single,
    ),
  ]
  debug_inspect(
    Ast::Path(steps),
    content=(
      #|Path(
      #|  [
      #|    { kind: Name("a"), stage: Single, focus: None, tuple: false },
      #|    { kind: Wildcard, stage: Single, focus: None, tuple: false },
      #|    { kind: Wildcard, stage: Recursive, focus: None, tuple: false },
      #|    { kind: Name("b"), stage: Recursive, focus: None, tuple: false },
      #|    { kind: Index(0), stage: Single, focus: None, tuple: false },
      #|    {
      #|      kind: Slice(Some(1), None),
      #|      stage: Single,
      #|      focus: None,
      #|      tuple: false,
      #|    },
      #|    {
      #|      kind: Filter(Boolean(true)),
      #|      stage: Single,
      #|      focus: None,
      #|      tuple: false,
      #|    },
      #|  ],
      #|)
    ),
  )
}

///|
test "Ast 表达式节点构造" {
  let bin = Ast::Binary(op="+", lhs=Ast::Number(1.0), rhs=Ast::Number(2.0))
  let un = Ast::Unary(op="-", expr=Ast::Number(1.0))
  let construct = Ast::Construct([Ast::Number(1.0), Ast::Number(2.0)])
  let group = Ast::Group([(Ast::String("k"), Ast::Number(1.0))])
  let sort = Ast::Sort(expr=Ast::Path([name_step("x")]), terms=[
    SortTerm::new(Ast::Path([name_step("y")])),
  ])
  let lambda = Ast::Lambda(
    params=["a", "b"],
    body=Ast::Path([name_step("a")]),
    signature=None,
  )
  let var_ = Ast::Var("x")
  let bind = Ast::Bind(name="x", value=Ast::Number(1.0), body=Ast::Var("x"))
  let apply = Ast::Apply(func=Ast::Var("f"), args=[Ast::Number(1.0)])
  let chain = Ast::Chain([Ast::Var("f"), Ast::Var("g")])
  let block = Ast::Block([Ast::Number(1.0), Ast::Number(2.0)])
  debug_inspect(
    bin,
    content=(
      #|Binary(op="+", lhs=Number(1), rhs=Number(2))
    ),
  )
  debug_inspect(
    un,
    content=(
      #|Unary(op="-", expr=Number(1))
    ),
  )
  debug_inspect(
    construct,
    content=(
      #|Construct([Number(1), Number(2)])
    ),
  )
  debug_inspect(
    group,
    content=(
      #|Group([(String("k"), Number(1))])
    ),
  )
  debug_inspect(
    sort,
    content=(
      #|Sort(
      #|  expr=Path([{ kind: Name("x"), stage: Single, focus: None, tuple: false }]),
      #|  terms=[
      #|    {
      #|      expr: Path([{ kind: Name("y"), stage: Single, focus: None, tuple: false }]),
      #|      descending: false,
      #|    },
      #|  ],
      #|)
    ),
  )
  debug_inspect(
    lambda,
    content=(
      #|Lambda(
      #|  params=["a", "b"],
      #|  body=Path([{ kind: Name("a"), stage: Single, focus: None, tuple: false }]),
      #|  signature=None,
      #|)
    ),
  )
  debug_inspect(
    var_,
    content=(
      #|Var("x")
    ),
  )
  debug_inspect(
    bind,
    content=(
      #|Bind(name="x", value=Number(1), body=Var("x"))
    ),
  )
  debug_inspect(
    apply,
    content=(
      #|Apply(func=Var("f"), args=[Number(1)])
    ),
  )
  debug_inspect(
    chain,
    content=(
      #|Chain([Var("f"), Var("g")])
    ),
  )
  debug_inspect(
    block,
    content=(
      #|Block([Number(1), Number(2)])
    ),
  )
}

///|
test "SortTerm 升降序标记" {
  let asc = SortTerm::new(Ast::Null)
  let desc = SortTerm::new(Ast::Null, descending=true)
  assert_eq(asc.descending, false)
  assert_eq(desc.descending, true)
}
