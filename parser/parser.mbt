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
  if not(p.at_end()) {
    raise @error.syntax_error(
      "意外的尾部 token",
      position=Some(p.peek().pos),
      token=Some(debug_tok(p.peek())),
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
    )
  }
}

///|
fn debug_tok(t : @lexer.Token) -> String {
  match t.kind {
    @lexer.TokenKind::String(_) => "string"
    @lexer.TokenKind::Number(_) => "number"
    @lexer.TokenKind::Boolean(_) => "boolean"
    @lexer.TokenKind::Null => "null"
    @lexer.TokenKind::Ident(s) => "ident(\{s})"
    @lexer.TokenKind::Var(s) => "var(\{s})"
    @lexer.TokenKind::DollarDollar => "$$"
    @lexer.TokenKind::Dot => "."
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
    @lexer.TokenKind::Question => "?"
    @lexer.TokenKind::At => "@"
    @lexer.TokenKind::Hash => "#"
  }
}

///|
fn not(b : Bool) -> Bool {
  !b
}
