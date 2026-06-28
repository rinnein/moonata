///|
/// 词法 token 种类。
pub(all) enum TokenKind {
  // 字面量
  String(String)
  Number(Double)
  Boolean(Bool)
  Null
  // 标识符与变量
  Ident(String)
  Var(String) // $name
  // 路径操作
  Dot
  Star // *
  DoubleStar // **
  DotStar // .*
  DoubleColon // ::
  // 括号
  LParen // (
  RParen // )
  LBracket // [
  RBracket // ]
  LBrace // {
  RBrace // }
  // 运算符
  Plus // +
  Minus // -
  Star2 // * (乘法，与 Star 同符号但语义不同，统一用 Star)
  Slash // /
  Percent // %
  Amp // & (合并)
  Pipe // | (未用，预留)
  // 比较
  Eq // =
  NotEq // !=
  Lt // <
  Lte // <=
  Gt // >
  Gte // >=
  // 逻辑
  And // &&
  Or // ||
  Not // !
  Coalesce // ??
  Default // ?:
  // 箭头与链
  Arrow // ~> (函数链)
  // 排序
  Caret // ^
  // 赋值/绑定
  Colon // :
  Semicolon // ;
  Comma // ,
  // 其他
  Question // ?
  At // @
  Hash // # （位置变量，谓词过滤中表示当前索引）
  DollarDollar // $$
} derive(Debug, Eq)

///|
/// 词法 token：种类 + 位置。
pub(all) struct Token {
  kind : TokenKind
  pos : Int // 字符偏移
} derive(Debug, Eq)

///|
/// 构造 token。
pub fn Token::new(kind~ : TokenKind, pos~ : Int) -> Token {
  { kind, pos }
}

///|
/// 词法分析器：将源码切分为 token 流。
priv struct Lexer {
  src : String
  mut pos : Int
  len : Int
}

///|
/// 词法分析入口：返回 token 数组。
pub fn lex(src : String) -> Array[Token] raise @error.JsonataError {
  let lex = Lexer::new(src)
  let tokens : Array[Token] = []
  for ;; {
    lex.skip_ws_and_comments()
    if lex.pos >= lex.len {
      break
    }
    let tok = lex.next_token()
    tokens.push(tok)
  }
  tokens
}

///|
fn Lexer::new(src : String) -> Lexer {
  { src, pos: 0, len: src.length() }
}

///|
fn Lexer::peek(self : Lexer) -> UInt16 {
  if self.pos < self.len {
    self.src[self.pos]
  } else {
    0
  }
}

///|
fn Lexer::peek_at(self : Lexer, offset : Int) -> UInt16 {
  let p = self.pos + offset
  if p < self.len && p >= 0 {
    self.src[p]
  } else {
    0
  }
}

///|
fn Lexer::advance(self : Lexer) -> UInt16 {
  let c = self.peek()
  self.pos = self.pos + 1
  c
}

///|
fn Lexer::skip_ws_and_comments(self : Lexer) -> Unit {
  for ;; {
    if self.pos >= self.len {
      break
    }
    let c = self.peek()
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      self.pos = self.pos + 1
    } else if c == '/' && self.peek_at(1) == '/' {
      // 单行注释
      self.pos = self.pos + 2
      while self.pos < self.len && self.peek() != '\n' {
        self.pos = self.pos + 1
      }
    } else if c == '/' && self.peek_at(1) == '*' {
      // 块注释
      self.pos = self.pos + 2
      while self.pos < self.len {
        if self.peek() == '*' && self.peek_at(1) == '/' {
          self.pos = self.pos + 2
          break
        }
        self.pos = self.pos + 1
      }
    } else {
      break
    }
  }
}

///|
fn Lexer::next_token(self : Lexer) -> Token raise @error.JsonataError {
  let start = self.pos
  let c = self.peek()
  // 字符串
  if c == '"' || c == '\'' || c == '`' {
    return self.lex_string(start)
  }
  // 数字
  if is_digit(c) || (c == '-' && is_digit(self.peek_at(1))) {
    return self.lex_number(start)
  }
  // 标识符（字母/下划线开头）
  if is_ident_start(c) {
    return self.lex_ident(start)
  }
  // 变量 $name 或 $$ 或 $
  if c == '$' {
    return self.lex_var(start)
  }
  // 运算符与标点
  self.lex_operator(start)
}

///|
fn Lexer::lex_string(
  self : Lexer,
  start : Int,
) -> Token raise @error.JsonataError {
  let quote = self.advance() // 消费引号
  let buf = StringBuilder::new()
  for ;; {
    if self.pos >= self.len {
      raise @error.syntax_error(
        "未终止的字符串",
        position=Some(start),
        token=None,
      )
    }
    let c = self.advance()
    if c == quote {
      break
    }
    if c == '\\' {
      // 转义
      if self.pos >= self.len {
        raise @error.syntax_error(
          "字符串转义不完整",
          position=Some(self.pos),
          token=None,
        )
      }
      let esc = self.advance()
      match esc {
        'n' => buf.write_char('\n')
        't' => buf.write_char('\t')
        'r' => buf.write_char('\r')
        '"' => buf.write_char('"')
        '\'' => buf.write_char('\'')
        '\\' => buf.write_char('\\')
        '/' => buf.write_char('/')
        'b' => buf.write_char('\u{08}')
        'f' => buf.write_char('\u{0c}')
        'u' => {
          // \uXXXX
          let hex = self.lex_hex4()
          buf.write_char(hex.to_char().unwrap_or('\u{FFFD}'))
        }
        _ =>
          raise @error.syntax_error(
            "未知转义: \\\{u16_to_char(esc)}",
            position=Some(self.pos),
            token=None,
          )
      }
    } else {
      buf.write_char(u16_to_char(c))
    }
  }
  Token::new(kind=TokenKind::String(buf.to_string()), pos=start)
}

///|
fn Lexer::lex_hex4(self : Lexer) -> Int raise @error.JsonataError {
  let mut val = 0
  for _ in 0..<4 {
    if self.pos >= self.len {
      raise @error.syntax_error(
        "\\u 转义需要 4 位十六进制",
        position=Some(self.pos),
        token=None,
      )
    }
    let c = self.advance()
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      raise @error.syntax_error(
        "无效十六进制位",
        position=Some(self.pos),
        token=None,
      )
    }
    val = val * 16 + digit
  }
  val
}

///|
fn Lexer::lex_number(
  self : Lexer,
  start : Int,
) -> Token raise @error.JsonataError {
  let buf = StringBuilder::new()
  if self.peek() == '-' {
    buf.write_char('-')
    self.pos = self.pos + 1
  }
  while self.pos < self.len && is_digit(self.peek()) {
    buf.write_char(u16_to_char(self.peek()))
    self.pos = self.pos + 1
  }
  if self.peek() == '.' && is_digit(self.peek_at(1)) {
    buf.write_char('.')
    self.pos = self.pos + 1
    while self.pos < self.len && is_digit(self.peek()) {
      buf.write_char(u16_to_char(self.peek()))
      self.pos = self.pos + 1
    }
  }
  // 指数 e/E
  if self.peek() == 'e' || self.peek() == 'E' {
    buf.write_char(u16_to_char(self.peek()))
    self.pos = self.pos + 1
    if self.peek() == '+' || self.peek() == '-' {
      buf.write_char(u16_to_char(self.peek()))
      self.pos = self.pos + 1
    }
    while self.pos < self.len && is_digit(self.peek()) {
      buf.write_char(u16_to_char(self.peek()))
      self.pos = self.pos + 1
    }
  }
  let s = buf.to_string()
  try {
    let d = @strconv.from_str(s)
    Token::new(kind=TokenKind::Number(d), pos=start)
  } catch {
    _ =>
      raise @error.syntax_error(
        "无效数字: \{s}",
        position=Some(start),
        token=Some(s),
      )
  }
}

///|
fn Lexer::lex_ident(self : Lexer, start : Int) -> Token {
  let buf = StringBuilder::new()
  while self.pos < self.len && is_ident_part(self.peek()) {
    buf.write_char(u16_to_char(self.peek()))
    self.pos = self.pos + 1
  }
  let s = buf.to_string()
  let kind = match s {
    "true" => TokenKind::Boolean(true)
    "false" => TokenKind::Boolean(false)
    "null" => TokenKind::Null
    "and" => TokenKind::And
    "or" => TokenKind::Or
    _ => TokenKind::Ident(s)
  }
  Token::new(kind~, pos=start)
}

///|
fn Lexer::lex_var(self : Lexer, start : Int) -> Token {
  // $$ 或 $name
  self.pos = self.pos + 1 // 消费 $
  if self.peek() == '$' {
    self.pos = self.pos + 1
    return Token::new(kind=TokenKind::DollarDollar, pos=start)
  }
  if is_ident_start(self.peek()) {
    let buf = StringBuilder::new()
    while self.pos < self.len && is_ident_part(self.peek()) {
      buf.write_char(u16_to_char(self.peek()))
      self.pos = self.pos + 1
    }
    return Token::new(kind=TokenKind::Var(buf.to_string()), pos=start)
  }
  // 单独 $ —— 视为 Var("") 表示根
  Token::new(kind=TokenKind::Var(""), pos=start)
}

///|
fn Lexer::lex_operator(
  self : Lexer,
  start : Int,
) -> Token raise @error.JsonataError {
  let c = self.advance()
  let kind : TokenKind = match c {
    '(' => TokenKind::LParen
    ')' => TokenKind::RParen
    '[' => TokenKind::LBracket
    ']' => TokenKind::RBracket
    '{' => TokenKind::LBrace
    '}' => TokenKind::RBrace
    ',' => TokenKind::Comma
    ';' => TokenKind::Semicolon
    ':' =>
      if self.peek() == ':' {
        self.pos = self.pos + 1
        TokenKind::DoubleColon
      } else {
        TokenKind::Colon
      }
    '^' => TokenKind::Caret
    '?' =>
      if self.peek() == '?' {
        self.pos = self.pos + 1
        TokenKind::Coalesce
      } else if self.peek() == ':' {
        self.pos = self.pos + 1
        TokenKind::Default
      } else {
        TokenKind::Question
      }
    '@' => TokenKind::At
    '#' => TokenKind::Hash
    '+' => TokenKind::Plus
    '-' => TokenKind::Minus
    '/' => TokenKind::Slash
    '%' => TokenKind::Percent
    '&' =>
      if self.peek() == '&' {
        self.pos = self.pos + 1
        TokenKind::And
      } else {
        TokenKind::Amp
      }
    '|' =>
      if self.peek() == '|' {
        self.pos = self.pos + 1
        TokenKind::Or
      } else {
        TokenKind::Pipe
      }
    '!' =>
      if self.peek() == '=' {
        self.pos = self.pos + 1
        TokenKind::NotEq
      } else {
        TokenKind::Not
      }
    '=' => TokenKind::Eq
    '<' =>
      if self.peek() == '=' {
        self.pos = self.pos + 1
        TokenKind::Lte
      } else {
        TokenKind::Lt
      }
    '>' =>
      if self.peek() == '=' {
        self.pos = self.pos + 1
        TokenKind::Gte
      } else {
        TokenKind::Gt
      }
    '*' =>
      if self.peek() == '*' {
        self.pos = self.pos + 1
        TokenKind::DoubleStar
      } else {
        TokenKind::Star
      }
    '.' =>
      if self.peek() == '*' {
        if self.peek_at(1) == '*' {
          // .** → Dot + DoubleStar（两个 token）
          TokenKind::Dot
        } else {
          // .* → DotStar（一个 token）
          self.pos = self.pos + 1
          TokenKind::DotStar
        }
      } else {
        TokenKind::Dot
      }
    '~' =>
      if self.peek() == '>' {
        self.pos = self.pos + 1
        TokenKind::Arrow
      } else {
        raise @error.syntax_error(
          "未知运算符 ~",
          position=Some(start),
          token=Some("~"),
        )
      }
    _ =>
      raise @error.syntax_error(
        "未知字符: \{u16_to_char(c)}",
        position=Some(start),
        token=None,
      )
  }
  Token::new(kind~, pos=start)
}

///|
fn is_digit(c : UInt16) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn is_ident_start(c : UInt16) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_part(c : UInt16) -> Bool {
  is_ident_start(c) || is_digit(c)
}

///|
/// UInt16 → Char（来自有效字符串，总是可转换；代理项用替换字符兜底）。
fn u16_to_char(c : UInt16) -> Char {
  match c.to_char() {
    Some(ch) => ch
    None => '\u{FFFD}'
  }
}
