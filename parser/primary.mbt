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
    @lexer.TokenKind::QuotedName(s) => {
      ignore(self.advance())
      @ast.Ast::QuotedName(s)
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
          code=Some("S0207"),
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
    @lexer.TokenKind::Percent => {
      ignore(self.advance())
      @ast.Ast::Path([@ast.parent_step()])
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
      let expr = if self.peek_kind() == @lexer.TokenKind::RParen {
        @ast.Ast::Block([])
      } else {
        let inner = self.parse_block()
        // Always wrap in Block so that single-expression parenthesized
        // forms like ($foo := nothing) get block-level variable scoping.
        match inner {
          @ast.Ast::Block(_) => inner
          _ => @ast.Ast::Block([inner])
        }
      }
      self.expect(@lexer.TokenKind::RParen, what="')'")
      // Parenthesized expression followed by path postfix (.[{):
      // wrap in Eval step so that subsequent [N]/slice do flat indexing,
      // preserving (expr)[N] ≠ expr[N] semantics.
      if is_path_postfix_kind(self.peek_kind()) {
        @ast.Ast::Path([@ast.eval_step(expr)])
      } else {
        expr
      }
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
        code=Some("S0211"),
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
  let signature = self.parse_signature()
  match signature {
    Some(sig) => validate_signature_syntax(sig)
    None => ()
  }
  self.expect(@lexer.TokenKind::LBrace, what="'{' for lambda body")
  let body = self.parse_block()
  self.expect(@lexer.TokenKind::RBrace, what="'}'")
  @ast.Ast::Lambda(params~, body~, signature~)
}

///|
/// 校验函数签名的语法正确性，提前抛出 `S0401`/`S0402`。
///
/// 完整的运行时类型校验在 `value` 包中进行；本函数仅检测 JSONata 签名
/// 语法层面的错误，使错误在解析阶段就向上传播，避免被后续 `expect('{')` 等
/// 语法错误掩盖。
fn validate_signature_syntax(sig : String) -> Unit raise @error.JsonataError {
  let chars = sig.to_array()
  let n = chars.length()
  // 跳过外层 `<>`
  let mut start = 0
  let mut end = n
  if n >= 2 && chars[0] == '<' && chars[n - 1] == '>' {
    start = 1
    end = n - 1
  }
  let mut paren_depth = 0
  let mut prev_base : Char? = None
  let mut i = start
  while i < end {
    let c = chars[i]
    match c {
      's' | 'n' | 'b' | 'o' | 'l' | 'a' | 'f' | 'j' | 'x' => prev_base = Some(c)
      '(' => {
        paren_depth += 1
        prev_base = None
      }
      ')' => {
        paren_depth -= 1
        prev_base = None
      }
      '<' => {
        // 类型参数：仅允许在 'a' 或 'f' 之后；不允许在 (...) 内
        if paren_depth > 0 {
          raise @error.signature_error(
            "S0402: 选择类型内不支持参数化类型 '<...>' in signature: \{sig}",
          )
        }
        match prev_base {
          Some(b) if b == 'a' || b == 'f' => ()
          _ =>
            raise @error.signature_error(
              "S0401: 类型参数 '<...>' 只能跟在 'a' 或 'f' 之后 in signature: \{sig}",
            )
        }
        // 跳过到匹配的 '>'
        let mut depth = 1
        i += 1
        let mut found = false
        while i < end {
          if chars[i] == '<' {
            depth += 1
          } else if chars[i] == '>' {
            depth -= 1
            if depth == 0 {
              found = true
              break
            }
          }
          i += 1
        }
        if !found {
          raise @error.signature_error(
            "S0401: 未闭合的 '<' in signature: \{sig}",
          )
        }
        prev_base = None
      }
      '?' | '+' | '-' | ':' | ' ' | '\t' | '\n' | '\r' => ()
      _ =>
        raise @error.signature_error(
          "S0401: 无法识别的签名符号 '\{c}' in signature: \{sig}",
        )
    }
    i += 1
  }
}

///|
fn Parser::parse_signature(self : Parser) -> String? raise @error.JsonataError {
  if self.peek_kind() != @lexer.TokenKind::Lt {
    return None
  }
  // 拼接原始词素，保留 JSONata 签名语义（如 `a<s>s?:s`）以便运行时校验
  let out = StringBuilder::new()
  out.write_string("<")
  ignore(self.advance()) // 消费起始 '<'
  let mut depth = 1
  while depth > 0 {
    if self.at_end() {
      raise @error.syntax_error(
        "未终止的函数签名",
        position=Some(self.peek().pos),
        token=None,
      )
    }
    match self.peek_kind() {
      @lexer.TokenKind::Lt => {
        depth += 1
        out.write_string(token_lexeme(self.peek()))
        ignore(self.advance())
      }
      @lexer.TokenKind::Gt => {
        depth -= 1
        out.write_string(token_lexeme(self.peek()))
        ignore(self.advance())
        if depth == 0 {
          break
        }
      }
      _ => {
        out.write_string(token_lexeme(self.peek()))
        ignore(self.advance())
      }
    }
  }
  Some(out.to_string())
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
        code=Some("S0208"),
      )
  }
}
