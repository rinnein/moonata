///|
/// 块表达式：表达式序列（用 `;` 分隔），返回最后一个。
fn Parser::parse_block(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let exprs : Array[@ast.Ast] = []
  exprs.push(self.parse_chain())
  while self.match_kind(@lexer.TokenKind::Semicolon) {
    if self.at_end() ||
      self.peek_kind() == @lexer.TokenKind::RParen ||
      self.peek_kind() == @lexer.TokenKind::RBracket ||
      self.peek_kind() == @lexer.TokenKind::RBrace {
      break
    }
    exprs.push(self.parse_chain())
  }
  if exprs.length() == 1 {
    exprs[0]
  } else {
    @ast.Ast::Block(exprs)
  }
}

///|
/// 函数链 `~>`：最低优先级，左结合。
fn Parser::parse_chain(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_bind()
  while self.peek_kind() == @lexer.TokenKind::Arrow {
    ignore(self.advance())
    let right = self.parse_bind()
    // 链式：累积为 Chain
    match left {
      @ast.Ast::Chain(stages) => {
        stages.push(right)
        left = @ast.Ast::Chain(stages)
      }
      _ => left = @ast.Ast::Chain([left, right])
    }
  }
  left
}

///|
/// 绑定表达式：`$var := expr; body` 或 `$var(expr) := ...`
fn Parser::parse_bind(self : Parser) -> @ast.Ast raise @error.JsonataError {
  // 检测 $var := 模式
  if self.peek_kind() is @lexer.TokenKind::Var(_) {
    let saved = self.pos
    let name = match self.advance().kind {
      @lexer.TokenKind::Var(n) => n
      _ => abort("unreachable")
    }
    if self.peek_kind() == @lexer.TokenKind::Colon {
      ignore(self.advance())
      // 期望 :=
      if self.peek_kind() == @lexer.TokenKind::Eq {
        ignore(self.advance())
        let value = self.parse_chain()
        // 消费分隔 value 和 body 的分号
        ignore(self.match_kind(@lexer.TokenKind::Semicolon))
        let body = self.parse_block()
        return @ast.Ast::Bind(name~, value~, body~)
      }
    }
    // 回退：不是绑定
    self.pos = saved
  }
  self.parse_conditional()
}

///|
/// 条件表达式：`cond ? then` 或 `cond ? then : else`。
fn Parser::parse_conditional(
  self : Parser,
) -> @ast.Ast raise @error.JsonataError {
  let condition = self.parse_fallback()
  if !self.match_kind(@lexer.TokenKind::Question) {
    return condition
  }
  let consequent = self.parse_chain()
  let alternate : @ast.Ast? = if self.match_kind(@lexer.TokenKind::Colon) {
    Some(self.parse_chain())
  } else {
    None
  }
  @ast.Ast::Conditional(condition~, consequent~, alternate~)
}

///|
/// fallback 运算：`??` 只在 undefined 时使用右侧，`?:` 按 EBV 选择右侧。
fn Parser::parse_fallback(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_sort()
  for ;; {
    let op = match self.peek_kind() {
      @lexer.TokenKind::Coalesce => "??"
      @lexer.TokenKind::Default => "?:"
      _ => break
    }
    ignore(self.advance())
    let right = self.parse_sort()
    left = @ast.Ast::Binary(op~, lhs=left, rhs=right)
  }
  left
}

///|
/// 排序表达式 `^(term, ...)`：一元后缀。
fn Parser::parse_sort(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let expr = self.parse_or()
  if self.match_kind(@lexer.TokenKind::Caret) {
    self.expect(@lexer.TokenKind::LParen, what="'(' for sort")
    let terms : Array[@ast.SortTerm] = []
    terms.push(self.parse_sort_term())
    while self.match_kind(@lexer.TokenKind::Comma) {
      terms.push(self.parse_sort_term())
    }
    self.expect(@lexer.TokenKind::RParen, what="')'")
    return @ast.Ast::Sort(expr~, terms~)
  }
  expr
}

///|
fn Parser::parse_sort_term(
  self : Parser,
) -> @ast.SortTerm raise @error.JsonataError {
  let mut descending = false
  if self.match_kind(@lexer.TokenKind::Minus) {
    descending = true
  } else if self.match_kind(@lexer.TokenKind::Plus) {
    descending = false
  }
  let expr = self.parse_or()
  @ast.SortTerm::new(expr, descending~)
}

///|
/// 逻辑或 `||`
fn Parser::parse_or(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_and()
  while self.is_or_operator() {
    ignore(self.advance())
    let right = self.parse_and()
    left = @ast.Ast::Binary(op="||", lhs=left, rhs=right)
  }
  left
}

///|
/// 逻辑与 `&&`
fn Parser::parse_and(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_comparison()
  while self.is_and_operator() {
    ignore(self.advance())
    let right = self.parse_comparison()
    left = @ast.Ast::Binary(op="&&", lhs=left, rhs=right)
  }
  left
}

///|
fn Parser::is_or_operator(self : Parser) -> Bool {
  match self.peek_kind() {
    @lexer.TokenKind::Or => true
    @lexer.TokenKind::Ident("or") => true
    _ => false
  }
}

///|
fn Parser::is_and_operator(self : Parser) -> Bool {
  match self.peek_kind() {
    @lexer.TokenKind::And => true
    @lexer.TokenKind::Ident("and") => true
    _ => false
  }
}

///|
/// 比较 `= != < <= > >= in`
fn Parser::parse_comparison(
  self : Parser,
) -> @ast.Ast raise @error.JsonataError {
  let left = self.parse_concat()
  let op = match self.peek_kind() {
    @lexer.TokenKind::Eq => "="
    @lexer.TokenKind::NotEq => "!="
    @lexer.TokenKind::Lt => "<"
    @lexer.TokenKind::Lte => "<="
    @lexer.TokenKind::Gt => ">"
    @lexer.TokenKind::Gte => ">="
    @lexer.TokenKind::Ident("in") => "in"
    _ => return left
  }
  ignore(self.advance())
  let right = self.parse_concat()
  @ast.Ast::Binary(op~, lhs=left, rhs=right)
}

///|
/// 字符串拼接 `&`
fn Parser::parse_concat(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_additive()
  while self.peek_kind() == @lexer.TokenKind::Amp {
    ignore(self.advance())
    let right = self.parse_additive()
    left = @ast.Ast::Binary(op="&", lhs=left, rhs=right)
  }
  left
}

///|
/// 加减 `+ -`
fn Parser::parse_additive(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_range()
  for ;; {
    let op = match self.peek_kind() {
      @lexer.TokenKind::Plus => "+"
      @lexer.TokenKind::Minus => "-"
      _ => break
    }
    ignore(self.advance())
    let right = self.parse_range()
    left = @ast.Ast::Binary(op~, lhs=left, rhs=right)
  }
  left
}

///|
fn Parser::parse_range(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_multiplicative()
  while self.peek_kind() == @lexer.TokenKind::Range {
    ignore(self.advance())
    let right = self.parse_multiplicative()
    left = @ast.Ast::Binary(op="..", lhs=left, rhs=right)
  }
  left
}

///|
/// 乘除 `% /`
fn Parser::parse_multiplicative(
  self : Parser,
) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_unary()
  for ;; {
    let op = match self.peek_kind() {
      @lexer.TokenKind::Star => "*"
      @lexer.TokenKind::Slash => "/"
      @lexer.TokenKind::Percent => "%"
      _ => break
    }
    ignore(self.advance())
    let right = self.parse_unary()
    left = @ast.Ast::Binary(op~, lhs=left, rhs=right)
  }
  left
}

///|
/// 一元 `-` `!`
fn Parser::parse_unary(self : Parser) -> @ast.Ast raise @error.JsonataError {
  match self.peek_kind() {
    @lexer.TokenKind::Minus => {
      ignore(self.advance())
      let expr = self.parse_unary()
      @ast.Ast::Unary(op="-", expr~)
    }
    @lexer.TokenKind::Not => {
      ignore(self.advance())
      let expr = self.parse_unary()
      @ast.Ast::Unary(op="!", expr~)
    }
    _ => self.parse_postfix()
  }
}

///|
/// 后缀：函数调用、路径步、过滤
fn Parser::parse_postfix(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut expr = self.parse_primary()
  for ;; {
    match self.peek_kind() {
      @lexer.TokenKind::Dot => {
        ignore(self.advance())
        match self.peek_kind() {
          @lexer.TokenKind::Ident(_) => {
            let saved = self.pos
            let name = match self.peek_kind() {
              @lexer.TokenKind::Ident(n) => n
              _ => ""
            }
            if name == "function" {
              let mut mapped = self.parse_primary()
              if self.peek_kind() == @lexer.TokenKind::LParen {
                mapped = self.parse_call(mapped)
              }
              mapped = inject_current_arg_for_lambda_map(mapped)
              expr = append_step(expr, @ast.map_step(mapped))
            } else {
              self.pos = saved
              let field = match self.advance().kind {
                @lexer.TokenKind::Ident(n) => n
                _ => abort("unreachable")
              }
              expr = append_step(expr, @ast.name_step(field))
            }
          }
          @lexer.TokenKind::String(_) => {
            let name = match self.advance().kind {
              @lexer.TokenKind::String(n) => n
              _ => abort("unreachable")
            }
            expr = append_step(expr, @ast.name_step(name))
          }
          @lexer.TokenKind::LParen => {
            ignore(self.advance())
            let mapped = self.parse_block()
            self.expect(@lexer.TokenKind::RParen, what="')'")
            expr = append_step(expr, @ast.map_step(mapped))
          }
          @lexer.TokenKind::LBracket => {
            let mapped = self.parse_primary()
            expr = append_step(expr, @ast.map_step(mapped))
          }
          @lexer.TokenKind::Var(_) | @lexer.TokenKind::DollarDollar => {
            let mut mapped = self.parse_primary()
            if self.peek_kind() == @lexer.TokenKind::LParen {
              mapped = self.parse_call(mapped)
            }
            expr = append_step(expr, @ast.map_step(mapped))
          }
          @lexer.TokenKind::Star => {
            ignore(self.advance())
            expr = append_step(expr, @ast.wildcard_step())
          }
          @lexer.TokenKind::DoubleStar => {
            ignore(self.advance())
            expr = append_step(expr, @ast.wildcard_step(recursive=true))
          }
          _ =>
            raise @error.syntax_error(
              "路径点后期望标识符或 *",
              position=Some(self.peek().pos),
              token=None,
            )
        }
      }
      @lexer.TokenKind::DotStar => {
        // .* 作为单 token
        ignore(self.advance())
        expr = append_step(expr, @ast.wildcard_step())
      }
      @lexer.TokenKind::DoubleStar => {
        // ** 递归降序：后跟 name 或通配符
        ignore(self.advance())
        match self.peek_kind() {
          @lexer.TokenKind::Ident(_) => {
            let name = match self.advance().kind {
              @lexer.TokenKind::Ident(n) => n
              _ => abort("unreachable")
            }
            expr = append_step(expr, @ast.name_step(name, recursive=true))
          }
          @lexer.TokenKind::Star => {
            ignore(self.advance())
            expr = append_step(expr, @ast.wildcard_step(recursive=true))
          }
          _ =>
            // foo** 无后续 → 递归通配符
            expr = append_step(expr, @ast.wildcard_step(recursive=true))
        }
      }
      @lexer.TokenKind::LBracket => expr = self.parse_bracket_access(expr)
      @lexer.TokenKind::LParen =>
        // 函数调用
        expr = self.parse_call(expr)
      _ => break
    }
  }
  expr
}

///|
/// 数组访问 [n]、切片 [a:b]、过滤 [expr]
fn Parser::parse_bracket_access(
  self : Parser,
  target : @ast.Ast,
) -> @ast.Ast raise @error.JsonataError {
  self.expect(@lexer.TokenKind::LBracket, what="'['")
  if self.peek_kind() == @lexer.TokenKind::RBracket {
    ignore(self.advance())
    return append_step(target, @ast.arrayify_step())
  }
  // 检测切片 [a:b]
  let start_expr : @ast.Ast? = if self.peek_kind() == @lexer.TokenKind::Colon {
    None
  } else {
    Some(self.parse_block())
  }
  match self.peek_kind() {
    @lexer.TokenKind::Colon => {
      // 切片
      ignore(self.advance())
      let end_expr : @ast.Ast? = if self.peek_kind() ==
        @lexer.TokenKind::RBracket {
        None
      } else {
        Some(self.parse_block())
      }
      self.expect(@lexer.TokenKind::RBracket, what="']'")
      // start/end 必须是数字字面量
      let start = opt_int(start_expr)
      let end = opt_int(end_expr)
      append_step(
        target,
        @ast.Step::new(
          kind=@ast.StepKind::Slice(start, end),
          stage=@ast.StepStage::Single,
        ),
      )
    }
    _ =>
      // 下标或过滤
      match start_expr {
        Some(e) => {
          self.expect(@lexer.TokenKind::RBracket, what="']'")
          match e {
            @ast.Ast::Number(n) =>
              append_step(
                target,
                @ast.Step::new(
                  kind=@ast.StepKind::Index(n.to_int()),
                  stage=@ast.StepStage::Single,
                ),
              )
            _ =>
              append_step(
                target,
                @ast.Step::new(
                  kind=@ast.StepKind::Filter(e),
                  stage=@ast.StepStage::Single,
                ),
              )
          }
        }
        None =>
          raise @error.syntax_error(
            "空的 []",
            position=Some(self.peek().pos),
            token=None,
          )
      }
  }
}

///|
/// 函数调用 (arg1, arg2, ...)
fn Parser::parse_call(
  self : Parser,
  func : @ast.Ast,
) -> @ast.Ast raise @error.JsonataError {
  self.expect(@lexer.TokenKind::LParen, what="'('")
  let args : Array[@ast.Ast] = []
  if self.peek_kind() != @lexer.TokenKind::RParen {
    args.push(self.parse_block())
    while self.match_kind(@lexer.TokenKind::Comma) {
      args.push(self.parse_block())
    }
  }
  self.expect(@lexer.TokenKind::RParen, what="')'")
  @ast.Ast::Apply(func~, args~)
}

///|
/// 将可选 Ast 转为可选 Int（切片边界）
fn opt_int(expr : @ast.Ast?) -> Int? {
  match expr {
    Some(@ast.Ast::Number(n)) => Some(n.to_int())
    _ => None
  }
}

///|
/// 向路径追加步（若非路径则创建新路径）
fn append_step(target : @ast.Ast, step : @ast.Step) -> @ast.Ast {
  match target {
    @ast.Ast::Path(steps) => {
      steps.push(step)
      @ast.Ast::Path(steps)
    }
    _ => @ast.Ast::Path([@ast.eval_step(target), step])
  }
}

///|
fn inject_current_arg_for_lambda_map(expr : @ast.Ast) -> @ast.Ast {
  match expr {
    @ast.Ast::Apply(func~, args~) =>
      match func {
        @ast.Ast::Lambda(params~, body~, signature~) =>
          if args.length() < params.length() {
            let injected : Array[@ast.Ast] = [@ast.Ast::Var("")]
            for arg in args {
              injected.push(arg)
            }
            @ast.Ast::Apply(
              func=@ast.Ast::Lambda(params~, body~, signature~),
              args=injected,
            )
          } else {
            expr
          }
        _ => expr
      }
    _ => expr
  }
}
