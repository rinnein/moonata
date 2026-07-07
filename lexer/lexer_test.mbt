///|
/// 辅助：词法分析并返回 token 种类数组（错误时返回空）。
fn tok_kind(s : String) -> Array[TokenKind] {
  let result : Array[TokenKind] = []
  try {
    for t in lex(s) {
      result.push(t.kind)
    }
  } catch {
    _ => ()
  }
  result
}

///|
test "词法：字面量" {
  debug_inspect(
    tok_kind("\"hello\""),
    content=(
      #|[String("hello")]
    ),
  )
  debug_inspect(
    tok_kind("'single'"),
    content=(
      #|[String("single")]
    ),
  )
  debug_inspect(
    tok_kind("`quoted name`"),
    content=(
      #|[QuotedName("quoted name")]
    ),
  )
  debug_inspect(
    tok_kind("42"),
    content=(
      #|[Number(42)]
    ),
  )
  debug_inspect(
    tok_kind("3.14"),
    content=(
      #|[Number(3.14)]
    ),
  )
  debug_inspect(
    tok_kind("-5"),
    content=(
      #|[Number(-5)]
    ),
  )
  debug_inspect(
    tok_kind("$x-1"),
    content=(
      #|[Var("x"), Minus, Number(1)]
    ),
  )
  debug_inspect(
    tok_kind("true"),
    content=(
      #|[Boolean(true)]
    ),
  )
  debug_inspect(
    tok_kind("false"),
    content=(
      #|[Boolean(false)]
    ),
  )
  debug_inspect(
    tok_kind("null"),
    content=(
      #|[Null]
    ),
  )
}

///|
test "词法：标识符与变量" {
  debug_inspect(
    tok_kind("foo"),
    content=(
      #|[Ident("foo")]
    ),
  )
  debug_inspect(
    tok_kind("foo_bar"),
    content=(
      #|[Ident("foo_bar")]
    ),
  )
  debug_inspect(
    tok_kind("$foo"),
    content=(
      #|[Var("foo")]
    ),
  )
  debug_inspect(
    tok_kind("$"),
    content=(
      #|[Var("")]
    ),
  )
  debug_inspect(
    tok_kind("$$"),
    content=(
      #|[DollarDollar]
    ),
  )
}

///|
test "词法：运算符与标点" {
  debug_inspect(
    tok_kind("+ - * / %"),
    content=(
      #|[Plus, Minus, Star, Slash, Percent]
    ),
  )
  debug_inspect(
    tok_kind("& && | ||"),
    content=(
      #|[Amp, And, Pipe, Or]
    ),
  )
  debug_inspect(
    tok_kind("= != < <= > >="),
    content=(
      #|[Eq, NotEq, Lt, Lte, Gt, Gte]
    ),
  )
  debug_inspect(
    tok_kind("! ~> ^"),
    content=(
      #|[Not, Arrow, Caret]
    ),
  )
  debug_inspect(
    tok_kind("( ) [ ] { }"),
    content=(
      #|[LParen, RParen, LBracket, RBracket, LBrace, RBrace]
    ),
  )
  debug_inspect(
    tok_kind(": :: ; , ? @"),
    content=(
      #|[Colon, DoubleColon, Semicolon, Comma, Question, At]
    ),
  )
  debug_inspect(
    tok_kind(".. λ"),
    content=(
      #|[Range, Ident("function")]
    ),
  )
}

///|
test "词法：路径操作符" {
  debug_inspect(
    tok_kind("."),
    content=(
      #|[Dot]
    ),
  )
  debug_inspect(
    tok_kind(".*"),
    content=(
      #|[DotStar]
    ),
  )
  debug_inspect(
    tok_kind("*"),
    content=(
      #|[Star]
    ),
  )
  debug_inspect(
    tok_kind("**"),
    content=(
      #|[DoubleStar]
    ),
  )
}

///|
test "词法：注释跳过" {
  debug_inspect(
    tok_kind("// 单行注释\nfoo"),
    content=(
      #|[Ident("foo")]
    ),
  )
  debug_inspect(
    tok_kind("/* 块注释 */ foo"),
    content=(
      #|[Ident("foo")]
    ),
  )
  debug_inspect(
    tok_kind("foo /* 中 */ bar"),
    content=(
      #|[Ident("foo"), Ident("bar")]
    ),
  )
}

///|
test "词法：字符串转义" {
  debug_inspect(
    tok_kind("\"hello\\nworld\""),
    content=(
      #|[String("hello\nworld")]
    ),
  )
  debug_inspect(
    tok_kind("\"tab\\there\""),
    content=(
      #|[String("tab\there")]
    ),
  )
  debug_inspect(
    tok_kind("\"quote\\\"inside\""),
    content=(
      #|[String("quote\"inside")]
    ),
  )
  debug_inspect(
    tok_kind("\"unicode\\u0041\""),
    content=(
      #|[String("unicodeA")]
    ),
  )
}

///|
test "词法：复合表达式" {
  debug_inspect(
    tok_kind("foo.bar[0]"),
    content=(
      #|[Ident("foo"), Dot, Ident("bar"), LBracket, Number(0), RBracket]
    ),
  )
  debug_inspect(
    tok_kind("$sum($map(data, function($x) { $x * 2 }))"),
    content=(
      #|[
      #|  Var("sum"),
      #|  LParen,
      #|  Var("map"),
      #|  LParen,
      #|  Ident("data"),
      #|  Comma,
      #|  Ident("function"),
      #|  LParen,
      #|  Var("x"),
      #|  RParen,
      #|  LBrace,
      #|  Var("x"),
      #|  Star,
      #|  Number(2),
      #|  RBrace,
      #|  RParen,
      #|  RParen,
      #|]
    ),
  )
  debug_inspect(
    tok_kind("a ~> b ~> c"),
    content=(
      #|[Ident("a"), Arrow, Ident("b"), Arrow, Ident("c")]
    ),
  )
}

///|
test "词法：未终止字符串报错" {
  let result = try {
    ignore(lex("\"unterminated"))
    false
  } catch {
    _ => true
  }
  assert_true(result)
}

///|
test "词法：数字带指数" {
  debug_inspect(
    tok_kind("1e10"),
    content=(
      #|[Number(10000000000)]
    ),
  )
  debug_inspect(
    tok_kind("1.5E-3"),
    content=(
      #|[Number(0.0015)]
    ),
  )
  debug_inspect(
    tok_kind("6.022e23"),
    content=(
      #|[Number(6.022e+23)]
    ),
  )
}

///|
test "词法：token 位置" {
  let tokens = lex("foo bar")
  debug_inspect(
    tokens,
    content=(
      #|[{ kind: Ident("foo"), pos: 0 }, { kind: Ident("bar"), pos: 4 }]
    ),
  )
}
