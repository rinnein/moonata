///|
/// 主表达式：字面量、变量、路径、分组、序列构造、Lambda
fn Parser::parse_primary(self : Parser) -> @ast.Ast raise @error.JsonataError {
  // 先检查是否是 Lambda 关键字 "function"
  if self.peek_kind() is @lexer.TokenKind::Ident(name) && name == "function" {
    ignore(self.advance())
    return self.parse_lambda()
  }
  let tok = self.peek()
  match tok.kind {
    @lexer.TokenKind::String(s) => {
      ignore(self.advance())
      @ast.Ast::String(s)
    }
    @lexer.TokenKind::Regex(pattern~, flags~) => {
      ignore(self.advance())
      @ast.Ast::Regex(pattern~, flags~)
    }
    @lexer.TokenKind::Number(n) => {
      ignore(self.advance())
      @ast.Ast::Number(n)
    }
    @lexer.TokenKind::Boolean(b) => {
      ignore(self.advance())
      @ast.Ast::Boolean(b)
    }
    @lexer.TokenKind::Null => {
      if self.at_end() {
        raise @error.syntax_error(
          "意外的输入结束",
          position=Some(tok.pos),
          token=None,
        )
      }
      ignore(self.advance())
      @ast.Ast::Null
    }
    @lexer.TokenKind::Question => {
      ignore(self.advance())
      @ast.Ast::Placeholder
    }
    @lexer.TokenKind::Var(name) => {
      ignore(self.advance())
      @ast.Ast::Var(name)
    }
    @lexer.TokenKind::DollarDollar => {
      ignore(self.advance())
      @ast.Ast::Var("$$")
    }
    @lexer.TokenKind::At => {
      ignore(self.advance())
      @ast.Ast::Var("@")
    }
    @lexer.TokenKind::Hash => {
      ignore(self.advance())
      @ast.Ast::Var("#")
    }
    @lexer.TokenKind::Ident(name) => {
      ignore(self.advance())
      @ast.Ast::Path([@ast.name_step(name)])
    }
    @lexer.TokenKind::And => {
      ignore(self.advance())
      @ast.Ast::Path([@ast.name_step("and")])
    }
    @lexer.TokenKind::Or => {
      ignore(self.advance())
      @ast.Ast::Path([@ast.name_step("or")])
    }
    @lexer.TokenKind::Star => {
      // * 作为路径第一步 → 通配符
      ignore(self.advance())
      @ast.Ast::Path([@ast.wildcard_step()])
    }
    @lexer.TokenKind::DoubleStar => {
      // ** 作为路径第一步 → 递归通配符
      ignore(self.advance())
      @ast.Ast::Path([@ast.wildcard_step(recursive=true)])
    }
    @lexer.TokenKind::DotStar => {
      // .* 作为路径第一步 → 通配符
      ignore(self.advance())
      @ast.Ast::Path([@ast.wildcard_step()])
    }
    @lexer.TokenKind::LParen => {
      ignore(self.advance())
      let expr = self.parse_block()
      self.expect(@lexer.TokenKind::RParen, what="')'")
      expr
    }
    @lexer.TokenKind::LBracket => {
      ignore(self.advance())
      let items : Array[@ast.Ast] = []
      if self.peek_kind() != @lexer.TokenKind::RBracket {
        items.push(self.parse_block())
        while self.match_kind(@lexer.TokenKind::Comma) {
          items.push(self.parse_block())
        }
      }
      self.expect(@lexer.TokenKind::RBracket, what="']'")
      @ast.Ast::Construct(items)
    }
    @lexer.TokenKind::LBrace => {
      ignore(self.advance())
      self.parse_group()
    }
    _ =>
      raise @error.syntax_error(
        "意外的 token: \{debug_tok(tok)}",
        position=Some(tok.pos),
        token=Some(debug_tok(tok)),
      )
  }
}

///|
/// 解析分组表达式 `{ ... }`（花括号已消费）。
fn Parser::parse_group(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let pairs : Array[(@ast.Ast, @ast.Ast)] = []
  if self.peek_kind() != @lexer.TokenKind::RBrace {
    pairs.push(self.parse_group_pair())
    while self.match_kind(@lexer.TokenKind::Comma) {
      if self.peek_kind() == @lexer.TokenKind::RBrace {
        break
      }
      pairs.push(self.parse_group_pair())
    }
  }
  self.expect(@lexer.TokenKind::RBrace, what="'}'")
  @ast.Ast::Group(pairs)
}

///|
fn Parser::parse_group_pair(
  self : Parser,
) -> (@ast.Ast, @ast.Ast) raise @error.JsonataError {
  let key = self.parse_block()
  self.expect(@lexer.TokenKind::Colon, what="':'")
  let value = self.parse_block()
  (key, value)
}

///|
/// 解析 Lambda `function($a, $b) { body }`（function 已消费）。
fn Parser::parse_lambda(self : Parser) -> @ast.Ast raise @error.JsonataError {
  self.expect(@lexer.TokenKind::LParen, what="'(' for lambda params")
  let params : Array[String] = []
  if self.peek_kind() != @lexer.TokenKind::RParen {
    params.push(self.parse_param())
    while self.match_kind(@lexer.TokenKind::Comma) {
      params.push(self.parse_param())
    }
  }
  self.expect(@lexer.TokenKind::RParen, what="')'")
  self.expect(@lexer.TokenKind::LBrace, what="'{' for lambda body")
  let body = self.parse_block()
  self.expect(@lexer.TokenKind::RBrace, what="'}'")
  @ast.Ast::Lambda(params~, body~)
}

///|
fn Parser::parse_param(self : Parser) -> String raise @error.JsonataError {
  match self.peek_kind() {
    @lexer.TokenKind::Var(name) => {
      ignore(self.advance())
      name
    }
    _ =>
      raise @error.syntax_error(
        "Lambda 参数期望 $name",
        position=Some(self.peek().pos),
        token=Some(debug_tok(self.peek())),
      )
  }
}
