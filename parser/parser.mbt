///|
/// 递归下降语法分析器：token 流 → AST。
priv struct Parser {
  tokens : Array[@lexer.Token]
  mut pos : Int
}

///|
/// 语法分析入口。
pub fn parse(
  tokens : Array[@lexer.Token],
) -> @ast.Ast raise @error.JsonataError {
  let p = Parser::new(tokens)
  let result = p.parse_block()
  // 检查 `expr := ...` 模式：左侧不是 $var 时应抛 S0212
  // （parse_bind 仅在 $var 后消费 :=，非变量表达式后的 := 会作为尾部 token 残留）
  if p.peek_kind() == @lexer.TokenKind::Colon &&
    p.pos + 1 < p.tokens.length() &&
    p.tokens[p.pos + 1].kind == @lexer.TokenKind::Eq {
    raise @error.syntax_error(
      ":= 左侧必须是 $name",
      position=Some(p.peek().pos),
      token=Some(":"),
      code=Some("S0212"),
    )
  }
  if not(p.at_end()) {
    raise @error.syntax_error(
      "意外的尾部 token",
      position=Some(p.peek().pos),
      token=Some(debug_tok(p.peek())),
      code=Some("S0201"),
    )
  }
  result
}

///|
fn Parser::new(tokens : Array[@lexer.Token]) -> Parser {
  { tokens, pos: 0 }
}

///|
fn Parser::peek(self : Parser) -> @lexer.Token {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos]
  } else {
    @lexer.Token::new(kind=@lexer.TokenKind::Null, pos=-1)
  }
}

///|
fn Parser::peek_kind(self : Parser) -> @lexer.TokenKind {
  if self.pos < self.tokens.length() {
    self.tokens[self.pos].kind
  } else {
    // 用 Null 作为哨兵；parse_primary 会检测 at_end 避免误解析
    @lexer.TokenKind::Null
  }
}

///|
fn Parser::at_end(self : Parser) -> Bool {
  self.pos >= self.tokens.length()
}

///|
fn Parser::advance(self : Parser) -> @lexer.Token {
  let t = self.peek()
  self.pos = self.pos + 1
  t
}

///|
fn Parser::match_kind(self : Parser, kind : @lexer.TokenKind) -> Bool {
  if self.peek_kind() == kind {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

///|
fn Parser::expect(
  self : Parser,
  kind : @lexer.TokenKind,
  what~ : String,
) -> Unit raise @error.JsonataError {
  if not(self.match_kind(kind)) {
    raise @error.syntax_error(
      "期望 \{what}，得到 \{debug_tok(self.peek())}",
      position=Some(self.peek().pos),
      token=Some(debug_tok(self.peek())),
      code=Some("S0202"),
    )
  }
}

///|
fn debug_tok(t : @lexer.Token) -> String {
  match t.kind {
    @lexer.TokenKind::String(_) => "string"
    @lexer.TokenKind::QuotedName(_) => "quoted-name"
    @lexer.TokenKind::Regex(pattern~, flags~) => "/\{pattern}/\{flags}"
    @lexer.TokenKind::Number(_) => "number"
    @lexer.TokenKind::Boolean(_) => "boolean"
    @lexer.TokenKind::Null => "null"
    @lexer.TokenKind::Question => "?"
    @lexer.TokenKind::Ident(s) => "ident(\{s})"
    @lexer.TokenKind::Var(s) => "var(\{s})"
    @lexer.TokenKind::DollarDollar => "$$"
    @lexer.TokenKind::Dot => "."
    @lexer.TokenKind::Range => ".."
    @lexer.TokenKind::Star => "*"
    @lexer.TokenKind::DoubleStar => "**"
    @lexer.TokenKind::DotStar => ".*"
    @lexer.TokenKind::DoubleColon => "::"
    @lexer.TokenKind::LParen => "("
    @lexer.TokenKind::RParen => ")"
    @lexer.TokenKind::LBracket => "["
    @lexer.TokenKind::RBracket => "]"
    @lexer.TokenKind::LBrace => "{"
    @lexer.TokenKind::RBrace => "}"
    @lexer.TokenKind::Plus => "+"
    @lexer.TokenKind::Minus => "-"
    @lexer.TokenKind::Star2 => "*"
    @lexer.TokenKind::Slash => "/"
    @lexer.TokenKind::Percent => "%"
    @lexer.TokenKind::Amp => "&"
    @lexer.TokenKind::Pipe => "|"
    @lexer.TokenKind::Eq => "="
    @lexer.TokenKind::NotEq => "!="
    @lexer.TokenKind::Lt => "<"
    @lexer.TokenKind::Lte => "<="
    @lexer.TokenKind::Gt => ">"
    @lexer.TokenKind::Gte => ">="
    @lexer.TokenKind::And => "&&"
    @lexer.TokenKind::Or => "||"
    @lexer.TokenKind::Not => "!"
    @lexer.TokenKind::Coalesce => "??"
    @lexer.TokenKind::Default => "?:"
    @lexer.TokenKind::Arrow => "~>"
    @lexer.TokenKind::Caret => "^"
    @lexer.TokenKind::Colon => ":"
    @lexer.TokenKind::Semicolon => ";"
    @lexer.TokenKind::Comma => ","
    @lexer.TokenKind::At => "@"
    @lexer.TokenKind::Hash => "#"
  }
}

///|
/// 返回 token 的原始词素文本，用于函数签名等需要保留语义的场景。
fn token_lexeme(t : @lexer.Token) -> String {
  match t.kind {
    @lexer.TokenKind::String(s) => s
    @lexer.TokenKind::QuotedName(s) => s
    @lexer.TokenKind::Regex(pattern~, flags~) => "/\{pattern}/\{flags}"
    @lexer.TokenKind::Number(n) => n.to_string()
    @lexer.TokenKind::Boolean(b) => b.to_string()
    @lexer.TokenKind::Null => "null"
    @lexer.TokenKind::Question => "?"
    @lexer.TokenKind::Ident(s) => s
    @lexer.TokenKind::Var(s) => "$" + s
    @lexer.TokenKind::DollarDollar => "$$"
    @lexer.TokenKind::Dot => "."
    @lexer.TokenKind::Range => ".."
    @lexer.TokenKind::Star => "*"
    @lexer.TokenKind::DoubleStar => "**"
    @lexer.TokenKind::DotStar => ".*"
    @lexer.TokenKind::DoubleColon => "::"
    @lexer.TokenKind::LParen => "("
    @lexer.TokenKind::RParen => ")"
    @lexer.TokenKind::LBracket => "["
    @lexer.TokenKind::RBracket => "]"
    @lexer.TokenKind::LBrace => "{"
    @lexer.TokenKind::RBrace => "}"
    @lexer.TokenKind::Plus => "+"
    @lexer.TokenKind::Minus => "-"
    @lexer.TokenKind::Star2 => "*"
    @lexer.TokenKind::Slash => "/"
    @lexer.TokenKind::Percent => "%"
    @lexer.TokenKind::Amp => "&"
    @lexer.TokenKind::Pipe => "|"
    @lexer.TokenKind::Eq => "="
    @lexer.TokenKind::NotEq => "!="
    @lexer.TokenKind::Lt => "<"
    @lexer.TokenKind::Lte => "<="
    @lexer.TokenKind::Gt => ">"
    @lexer.TokenKind::Gte => ">="
    @lexer.TokenKind::And => "&&"
    @lexer.TokenKind::Or => "||"
    @lexer.TokenKind::Not => "!"
    @lexer.TokenKind::Coalesce => "??"
    @lexer.TokenKind::Default => "?:"
    @lexer.TokenKind::Arrow => "~>"
    @lexer.TokenKind::Caret => "^"
    @lexer.TokenKind::Colon => ":"
    @lexer.TokenKind::Semicolon => ";"
    @lexer.TokenKind::Comma => ","
    @lexer.TokenKind::At => "@"
    @lexer.TokenKind::Hash => "#"
  }
}

///|
fn not(b : Bool) -> Bool {
  !b
}
