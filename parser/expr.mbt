///|
/// 块表达式：表达式序列（用 `;` 分隔），返回最后一个。
fn Parser::parse_block(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let exprs : Array[@ast.Ast] = []
  exprs.push(self.parse_comparison_chain())
  while self.peek_kind() == @lexer.TokenKind::Semicolon {
    let semi_pos = self.peek().pos
    ignore(self.advance())
    if self.at_end() {
      // 尾部分号在顶层输入中是语法错误（S0201）
      raise @error.syntax_error(
        "意外的尾部 token",
        position=Some(semi_pos),
        token=Some(";"),
        code=Some("S0201"),
      )
    }
    if self.peek_kind() == @lexer.TokenKind::RParen ||
      self.peek_kind() == @lexer.TokenKind::RBracket ||
      self.peek_kind() == @lexer.TokenKind::RBrace {
      break
    }
    exprs.push(self.parse_comparison_chain())
  }
  if exprs.length() == 1 {
    exprs[0]
  } else {
    @ast.Ast::Block(exprs)
  }
}

///|
/// 比较与链混合层：处理 `=` `!=` `<` `<=` `>` `>=` `in` 与 `~>` 的交互。
/// JSONata 中 `~>` 与 `=` 具有相同优先级（binding power 40），
/// 因此 `a ~> b = c` 解析为 `(a ~> b) = c`。
fn Parser::parse_comparison_chain(
  self : Parser,
) -> @ast.Ast raise @error.JsonataError {
  // 先解析左侧（可能包含链）
  let left = self.parse_chain_inner()
  // 检查比较运算符
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
  // 右侧是完整的比较链（允许嵌套比较）
  let right = self.parse_comparison_chain()
  @ast.Ast::Binary(op~, lhs=left, rhs=right)
}

///|
/// 链内层：解析 `~>` 及其左侧操作数。
/// 被 parse_comparison_chain 调用，不处理比较运算符。
fn Parser::parse_chain_inner(
  self : Parser,
) -> @ast.Ast raise @error.JsonataError {
  let mut left = self.parse_bind()
  let mut trailing_arrayify = false
  while self.peek_kind() == @lexer.TokenKind::Arrow {
    ignore(self.advance())
    let raw_right = if self.peek_kind() == @lexer.TokenKind::Pipe {
      self.parse_transform()
    } else {
      // 右侧停在比较运算符之前（~> 与 = 同优先级）
      self.parse_chain_rhs()
    }
    // ~> 优先级低于 []：将右侧末尾的 [] 分离出链阶段
    let (right, has_arrayify) = split_chain_stage_arrayify(raw_right)
    trailing_arrayify = has_arrayify
    // 链式：累积为 Chain
    match left {
      @ast.Ast::Chain(stages) => {
        stages.push(right)
        left = @ast.Ast::Chain(stages)
      }
      _ => left = @ast.Ast::Chain([left, right])
    }
    // 如果还有更多 ~>，优先应用 [] 到当前链结果
    if trailing_arrayify && self.peek_kind() == @lexer.TokenKind::Arrow {
      left = append_chain_arrayify(left)
      trailing_arrayify = false
    }
  }
  // 末尾的 [] 应用到整条链结果
  if trailing_arrayify {
    left = append_chain_arrayify(left)
  }
  left
}

///|
/// 兼容别名：parse_chain 指向 parse_comparison_chain
fn Parser::parse_chain(self : Parser) -> @ast.Ast raise @error.JsonataError {
  self.parse_comparison_chain()
}

///|
/// 解析链式运算符右侧表达式，停在比较运算符之前。
/// 对应 JSONata-js 中 ~> 与 = 同优先级（40）的语义。
fn Parser::parse_chain_rhs(self : Parser) -> @ast.Ast raise @error.JsonataError {
  // 跳过 parse_comparison，直接调用 parse_concat
  // 这意味着链右侧不会消费 = != < <= > >= in 等比较运算符
  self.parse_concat()
}

///|
/// 将 Arrayify 步应用到链或非链表达式，产生 Path。
fn append_chain_arrayify(expr : @ast.Ast) -> @ast.Ast {
  let step = @ast.arrayify_step()
  match expr {
    @ast.Ast::Chain(_) => @ast.Ast::Path([@ast.eval_step(expr), step])
    _ => append_step(expr, step)
  }
}

///|
/// 从链阶段的 expr 中分离末尾 `[]`（Arrayify）步。
/// 返回（剥离后表达式，是否存在 Arrayify）。
fn split_chain_stage_arrayify(expr : @ast.Ast) -> (@ast.Ast, Bool) {
  match expr {
    @ast.Ast::Path(steps) => {
      let len = steps.length()
      if len == 0 {
        return (expr, false)
      }
      match steps[len - 1].kind {
        @ast.StepKind::Arrayify => {
          if len == 1 {
            return (@ast.Ast::Path([]), true)
          }
          let limit = len - 1
          let new_steps : Array[@ast.Step] = []
          for i in 0..<limit {
            new_steps.push(steps[i])
          }
          if limit == 1 {
            match new_steps[0].kind {
              @ast.StepKind::Eval(inner) => return (inner, true)
              _ => ()
            }
          }
          (@ast.Ast::Path(new_steps), true)
        }
        _ => (expr, false)
      }
    }
    _ => (expr, false)
  }
}

///|
/// 变换表达式 `| path | update [, delete] |`。
fn Parser::parse_transform(self : Parser) -> @ast.Ast raise @error.JsonataError {
  ignore(self.advance()) // consume opening |
  let path = self.parse_bind()
  self.expect(@lexer.TokenKind::Pipe, what="|") // separator |
  let update = self.parse_bind()
  let mut delete = None
  if self.peek_kind() == @lexer.TokenKind::Comma {
    ignore(self.advance())
    delete = Some(self.parse_bind())
  }
  self.expect(@lexer.TokenKind::Pipe, what="|") // closing |
  @ast.Ast::Transform(path~, update~, delete~)
}

///|
/// 绑定表达式：`$var := expr`
/// 返回 Bind(name, value)，分号由 parse_block 在链/块层级消费。
/// 多个 `:=` 链式赋值时，每个 `:=` 返回独立 Bind 节点，
/// 由外层 Block 串联（如 `$a := $b := 5` → `Bind("b", 5)`, `Bind("a", ...)`）。
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
        return @ast.Ast::Bind(name~, value~)
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
/// 排序层：委托给 parse_or（`^()` 在 postfix 层处理）。
fn Parser::parse_sort(self : Parser) -> @ast.Ast raise @error.JsonataError {
  self.parse_or()
}

///|
fn Parser::parse_sort_term(
  self : Parser,
) -> @ast.SortTerm raise @error.JsonataError {
  let mut descending = false
  // JSONata: < = 升序，> = 降序
  if self.match_kind(@lexer.TokenKind::Gt) {
    descending = true
  } else if self.match_kind(@lexer.TokenKind::Lt) {
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
fn is_path_postfix_kind(kind : @lexer.TokenKind) -> Bool {
  match kind {
    @lexer.TokenKind::Dot
    | @lexer.TokenKind::DotStar
    | @lexer.TokenKind::DoubleStar
    | @lexer.TokenKind::At
    | @lexer.TokenKind::LBracket
    | @lexer.TokenKind::LBrace
    | @lexer.TokenKind::LParen => true
    _ => false
  }
}

///|
/// 后缀：函数调用、路径步、过滤
fn Parser::parse_postfix(self : Parser) -> @ast.Ast raise @error.JsonataError {
  let mut expr = self.parse_primary()
  // 路径上下文中的 quoted name → 字段名；普通字符串后接 [] 保持字面量。
  if is_path_postfix_kind(self.peek_kind()) {
    match expr {
      @ast.Ast::String(name) =>
        if self.peek_kind() != @lexer.TokenKind::LBracket {
          expr = @ast.Ast::Path([@ast.name_step(name)])
        }
      @ast.Ast::QuotedName(name) =>
        expr = @ast.Ast::Path([@ast.name_step(name)])
      _ => ()
    }
  }
  let mut constructor_restriction = false
  for ;; {
    // 合并 `** .Name` → Name(Recursive)
    if self.peek_kind() == @lexer.TokenKind::Dot {
      let should_merge = match expr {
        @ast.Ast::Path(steps) if steps.length() > 0 => {
          let last = steps[steps.length() - 1]
          last.stage == @ast.StepStage::Recursive &&
          last.kind == @ast.StepKind::Wildcard
        }
        _ => false
      }
      if should_merge {
        ignore(self.advance()) // Dot
        match self.peek_kind() {
          @lexer.TokenKind::Ident(_) => {
            let name = match self.advance().kind {
              @lexer.TokenKind::Ident(n) => n
              _ => abort("unreachable")
            }
            let mut step = @ast.name_step(name, recursive=true)
            match self.try_absorb_index_0() {
              Some(idx) => step = with_index(step, idx)
              None => ()
            }
            match expr {
              @ast.Ast::Path(steps) => {
                ignore(steps.pop())
                steps.push(step)
              }
              _ => abort("unreachable")
            }
            continue
          }
          @lexer.TokenKind::String(_) | @lexer.TokenKind::QuotedName(_) => {
            let name = match self.advance().kind {
              @lexer.TokenKind::String(n) => n
              @lexer.TokenKind::QuotedName(n) => n
              _ => abort("unreachable")
            }
            let mut step = @ast.name_step(name, recursive=true)
            match self.try_absorb_index_0() {
              Some(idx) => step = with_index(step, idx)
              None => ()
            }
            match expr {
              @ast.Ast::Path(steps) => {
                ignore(steps.pop())
                steps.push(step)
              }
              _ => abort("unreachable")
            }
            continue
          }
          _ => ()
        }
      }
    }
    match self.peek_kind() {
      @lexer.TokenKind::Dot => {
        constructor_restriction = false
        ignore(self.advance())
        match self.peek_kind() {
          @lexer.TokenKind::Ident(_) => {
            let saved = self.pos
            let name = match self.peek_kind() {
              @lexer.TokenKind::Ident(n) => n
              _ => ""
            }
            if name == "function" &&
              self.pos + 1 < self.tokens.length() &&
              self.tokens[self.pos + 1].kind == @lexer.TokenKind::LParen {
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
          @lexer.TokenKind::String(_) | @lexer.TokenKind::QuotedName(_) => {
            let name = match self.advance().kind {
              @lexer.TokenKind::String(n) => n
              @lexer.TokenKind::QuotedName(n) => n
              _ => abort("unreachable")
            }
            expr = append_step(expr, @ast.name_step(name))
          }
          @lexer.TokenKind::LParen => {
            ignore(self.advance())
            let mapped = if self.peek_kind() == @lexer.TokenKind::RParen {
              @ast.Ast::Block([])
            } else {
              self.parse_block()
            }
            self.expect(@lexer.TokenKind::RParen, what="')'")
            expr = append_step(expr, @ast.map_step(mapped))
          }
          @lexer.TokenKind::LBracket => {
            let mapped = self.parse_primary()
            expr = append_step(expr, @ast.map_step(mapped))
          }
          @lexer.TokenKind::LBrace => {
            ignore(self.advance())
            let mapped = self.parse_group()
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
          @lexer.TokenKind::Percent => {
            ignore(self.advance())
            expr = append_step(expr, @ast.parent_step())
          }
          @lexer.TokenKind::DoubleStar => {
            ignore(self.advance())
            // 检查 .** 后是否跟 .name 或 ."name"，合并为递归 Name/Wildcard 步
            if self.peek_kind() == @lexer.TokenKind::Dot {
              ignore(self.advance())
              match self.peek_kind() {
                @lexer.TokenKind::Ident(_) => {
                  let name = match self.advance().kind {
                    @lexer.TokenKind::Ident(n) => n
                    _ => abort("unreachable")
                  }
                  let mut step = @ast.name_step(name, recursive=true)
                  match self.try_absorb_index_0() {
                    Some(idx) => step = with_index(step, idx)
                    None => ()
                  }
                  expr = append_step(expr, step)
                }
                @lexer.TokenKind::String(_) | @lexer.TokenKind::QuotedName(_) => {
                  let name = match self.advance().kind {
                    @lexer.TokenKind::String(n) => n
                    @lexer.TokenKind::QuotedName(n) => n
                    _ => abort("unreachable")
                  }
                  let mut step = @ast.name_step(name, recursive=true)
                  match self.try_absorb_index_0() {
                    Some(idx) => step = with_index(step, idx)
                    None => ()
                  }
                  expr = append_step(expr, step)
                }
                @lexer.TokenKind::Star => {
                  ignore(self.advance())
                  expr = append_step(expr, @ast.wildcard_step(recursive=true))
                }
                _ =>
                  expr = append_step(expr, @ast.wildcard_step(recursive=true))
              }
            } else {
              expr = append_step(expr, @ast.wildcard_step(recursive=true))
            }
          }
          @lexer.TokenKind::Number(_)
          | @lexer.TokenKind::Boolean(_)
          | @lexer.TokenKind::Null => {
            // 对齐 jsonata-js processAST：路径步为 number/boolean/null 时抛 S0213
            // 但若 number 后还有无法作为路径继续的 token（如 ident），则由顶层
            // 解析器抛 S0201（意外的尾部 token），匹配 jsonata-js 的"先解析再校验"顺序
            let num_tok = self.peek()
            let next_idx = self.pos + 1
            let next_is_end = next_idx >= self.tokens.length()
            if next_is_end {
              raise @error.syntax_error(
                "路径步不能是数字或字面量",
                position=Some(num_tok.pos),
                token=None,
                code=Some("S0213"),
              )
            } else {
              raise @error.syntax_error(
                "意外的尾部 token",
                position=Some(self.tokens[next_idx].pos),
                token=Some(debug_tok(self.tokens[next_idx])),
                code=Some("S0201"),
              )
            }
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
        constructor_restriction = false
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
            let mut step = @ast.name_step(name, recursive=true)
            match self.try_absorb_index_0() {
              Some(idx) => step = with_index(step, idx)
              None => ()
            }
            expr = append_step(expr, step)
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
      @lexer.TokenKind::At => {
        ignore(self.advance())
        // 与 jsonata-js processAST 一致：focus 绑定不能附着在已有
        // predicate/index 阶段之后；排序阶段使用独立的 S0216。
        match expr {
          @ast.Ast::Sort(..) =>
            raise @error.syntax_error(
              "focus 绑定不能应用于排序结果",
              position=Some(self.peek().pos),
              token=Some("@"),
              code=Some("S0216"),
            )
          @ast.Ast::Path(steps) if steps.length() > 0 => {
            let last = steps[steps.length() - 1]
            match last.kind {
              @ast.StepKind::Index(_)
              | @ast.StepKind::Slice(_, _)
              | @ast.StepKind::Filter(_) =>
                raise @error.syntax_error(
                  "focus 绑定不能应用于已有谓词阶段",
                  position=Some(self.peek().pos),
                  token=Some("@"),
                  code=Some("S0215"),
                )
              _ => ()
            }
          }
          _ => ()
        }
        let var_name = match self.peek_kind() {
          @lexer.TokenKind::Var(name) => {
            ignore(self.advance())
            name
          }
          @lexer.TokenKind::DollarDollar => {
            ignore(self.advance())
            "$$"
          }
          _ =>
            raise @error.syntax_error(
              "@ 后期望 $name 或 $$",
              position=Some(self.peek().pos),
              token=Some(debug_tok(self.peek())),
              code=Some("S0214"),
            )
        }
        // 标注当前路径的最后一个步，而非新增 BindVar 步
        match expr {
          @ast.Ast::Path(steps) => {
            let last = steps[steps.length() - 1]
            steps[steps.length() - 1] = @ast.Step::new(
              kind=last.kind,
              stage=last.stage,
              focus=Some(var_name),
              tuple=true,
            )
          }
          _ => expr = @ast.Ast::Path([@ast.eval_step(expr)])
        }
      }
      @lexer.TokenKind::Hash => {
        ignore(self.advance())
        let pos_name = match self.peek_kind() {
          @lexer.TokenKind::Var(name) => {
            ignore(self.advance())
            name
          }
          _ =>
            raise @error.syntax_error(
              "# 后期望 $name",
              position=Some(self.peek().pos),
              token=Some(debug_tok(self.peek())),
              code=Some("S0214"),
            )
        }
        // 标注当前路径最后一个步的 pos_var（位置索引绑定）
        match expr {
          @ast.Ast::Path(steps) if steps.length() > 0 => {
            let last = steps[steps.length() - 1]
            steps[steps.length() - 1] = @ast.Step::new(
              kind=last.kind,
              stage=last.stage,
              focus=last.focus,
              tuple=last.tuple,
              index=last.index,
              pos_var=Some(pos_name),
            )
          }
          _ => {
            let step = @ast.Step::new(
              kind=@ast.StepKind::Eval(expr),
              stage=@ast.StepStage::Single,
              pos_var=Some(pos_name),
            )
            expr = @ast.Ast::Path([step])
          }
        }
      }
      @lexer.TokenKind::LBracket => {
        if constructor_restriction {
          raise @error.syntax_error(
            "构造器后不允许谓词",
            position=Some(self.peek().pos),
            token=Some("["),
            code=Some("S0209"),
          )
        }
        expr = self.parse_bracket_access(expr)
      }
      @lexer.TokenKind::LParen =>
        // 函数调用
        expr = self.parse_call(expr)
      @lexer.TokenKind::LBrace => {
        if constructor_restriction {
          raise @error.syntax_error(
            "构造器后不允许另一个构造器",
            position=Some(self.peek().pos),
            token=Some("{"),
            code=Some("S0210"),
          )
        }
        ignore(self.advance())
        let mapped = self.parse_group()
        // 无前置 `.` 的 { ... }：是聚合分组，非逐元素映射
        expr = append_step(
          expr,
          @ast.Step::new(
            kind=@ast.StepKind::GroupAggregate(mapped),
            stage=@ast.StepStage::Single,
          ),
        )
        constructor_restriction = true
      }
      @lexer.TokenKind::Caret => {
        // 排序后缀 ^(term, ...)
        ignore(self.advance())
        self.expect(@lexer.TokenKind::LParen, what="'(' for sort")
        let terms : Array[@ast.SortTerm] = []
        terms.push(self.parse_sort_term())
        while self.match_kind(@lexer.TokenKind::Comma) {
          terms.push(self.parse_sort_term())
        }
        self.expect(@lexer.TokenKind::RParen, what="')'")
        expr = @ast.Ast::Sort(expr~, terms~)
      }
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
/// 若当前 token 是 `[0]`，则吸收并返回 Some(0)，否则不消费且返回 None。
fn Parser::try_absorb_index_0(self : Parser) -> Int? {
  if self.peek_kind() != @lexer.TokenKind::LBracket {
    return None
  }
  let saved = self.pos
  ignore(self.advance()) // [
  match self.peek_kind() {
    @lexer.TokenKind::Number(n) if n == 0.0 => {
      ignore(self.advance()) // 0
      if self.peek_kind() == @lexer.TokenKind::RBracket {
        ignore(self.advance()) // ]
        return Some(0)
      }
    }
    _ => ()
  }
  self.pos = saved
  None
}

///|
/// 用 step 的 index 字段创建一个新步（保持其他字段不变）。
fn with_index(step : @ast.Step, idx : Int) -> @ast.Step {
  @ast.Step::new(
    kind=step.kind,
    stage=step.stage,
    focus=step.focus,
    tuple=step.tuple,
    index=Some(idx),
  )
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
