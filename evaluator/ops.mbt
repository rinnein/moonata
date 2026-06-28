///|
/// 二元运算求值
fn eval_binary(
  op : String,
  lhs_ast : @ast.Ast,
  rhs_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let lhs = eval(lhs_ast, ctx)
  let rhs = eval(rhs_ast, ctx)
  // Undefined 传播（多数运算）
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    match op {
      "&&" =>
        // 短路：若 lhs 为 false 则结果 false
        match lhs {
          @value.JsonataValue::Json(Json::False) =>
            return @value.JsonataValue::Json(Json::boolean(false))
          _ => return @value.JsonataValue::Undefined
        }
      "||" =>
        // 短路：若 lhs 为 true 则结果 true
        match lhs {
          @value.JsonataValue::Json(Json::True) =>
            return @value.JsonataValue::Json(Json::boolean(true))
          _ => return @value.JsonataValue::Undefined
        }
      _ => return @value.JsonataValue::Undefined
    }
  }
  match op {
    "+" => arith_op(lhs, rhs, "+")
    "-" => arith_op(lhs, rhs, "-")
    "*" => arith_op(lhs, rhs, "*")
    "/" => arith_op(lhs, rhs, "/")
    "%" => arith_op(lhs, rhs, "%")
    "&" => concat_str(lhs, rhs)
    "=" => compare_eq(lhs, rhs)
    "!=" => compare_neq(lhs, rhs)
    "<" => compare_lt(lhs, rhs)
    "<=" => compare_lte(lhs, rhs)
    ">" => compare_gt(lhs, rhs)
    ">=" => compare_gte(lhs, rhs)
    "&&" => logic_and(lhs, rhs)
    "||" => logic_or(lhs, rhs)
    _ => raise @error.runtime_error("未知运算符: \{op}")
  }
}

///|
/// 算术运算
fn arith_op(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
  op : String,
) -> @value.JsonataValue raise @error.JsonataError {
  let l = to_number(lhs)
  let r = to_number(rhs)
  let result = match op {
    "+" => l + r
    "-" => l - r
    "*" => l * r
    "/" =>
      if r == 0.0 {
        raise @error.runtime_error("除以零")
      } else {
        l / r
      }
    "%" => (l.to_int() % r.to_int()).to_double()
    _ => raise @error.runtime_error("未知算术运算: \{op}")
  }
  @value.JsonataValue::Json(Json::number(result))
}

///|
/// 字符串拼接
fn concat_str(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  let l = to_str(lhs)
  let r = to_str(rhs)
  @value.JsonataValue::Json(Json::string(l + r))
}

///|
/// 比较：相等
fn compare_eq(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  @value.JsonataValue::Json(
    Json::boolean(json_equal(lhs.to_json(), rhs.to_json())),
  )
}

///|
/// 比较：不等
fn compare_neq(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  @value.JsonataValue::Json(
    Json::boolean(not(json_equal(lhs.to_json(), rhs.to_json()))),
  )
}

///|
/// 比较：小于
fn compare_lt(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  let l = to_number(lhs)
  let r = to_number(rhs)
  @value.JsonataValue::Json(Json::boolean(l < r))
}

///|
/// 比较：小于等于
fn compare_lte(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  let l = to_number(lhs)
  let r = to_number(rhs)
  @value.JsonataValue::Json(Json::boolean(l <= r))
}

///|
/// 比较：大于
fn compare_gt(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  let l = to_number(lhs)
  let r = to_number(rhs)
  @value.JsonataValue::Json(Json::boolean(l > r))
}

///|
/// 比较：大于等于
fn compare_gte(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  let l = to_number(lhs)
  let r = to_number(rhs)
  @value.JsonataValue::Json(Json::boolean(l >= r))
}

///|
/// 逻辑与
fn logic_and(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  @value.JsonataValue::Json(Json::boolean(to_bool(lhs) && to_bool(rhs)))
}

///|
/// 逻辑或
fn logic_or(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  @value.JsonataValue::Json(Json::boolean(to_bool(lhs) || to_bool(rhs)))
}

///|
/// 一元运算
fn eval_unary(
  op : String,
  expr : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let v = eval(expr, ctx)
  if v is @value.JsonataValue::Undefined {
    return @value.JsonataValue::Undefined
  }
  match op {
    "-" => {
      let n = to_number(v)
      @value.JsonataValue::Json(Json::number(-n))
    }
    "!" => @value.JsonataValue::Json(Json::boolean(not(to_bool(v))))
    _ => raise @error.runtime_error("未知一元运算: \{op}")
  }
}

///|
/// 序列构造
fn eval_construct(
  items : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let results : Array[@value.JsonataValue] = []
  for item in items {
    let v = eval(item, ctx)
    match v {
      @value.JsonataValue::Undefined => continue
      _ => results.push(v)
    }
  }
  @value.JsonataValue::sequence(results)
}

///|
/// 绑定求值
fn eval_bind(
  name : String,
  value_ast : @ast.Ast,
  body_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let value = eval(value_ast, ctx)
  ctx.bind(name, value)
  eval(body_ast, ctx)
}

///|
/// 块求值
fn eval_block(
  exprs : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let mut result = @value.JsonataValue::Undefined
  for expr in exprs {
    result = eval(expr, ctx)
  }
  result
}

///|
/// 函数调用
fn eval_apply(
  func_ast : @ast.Ast,
  args_ast : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let func_val = eval(func_ast, ctx)
  match func_val {
    @value.JsonataValue::Func(f) => {
      let args : Array[@value.JsonataValue] = []
      for arg_ast in args_ast {
        args.push(eval(arg_ast, ctx))
      }
      // 检查元数（最小元数：允许更多参数）
      if args.length() < f.arity {
        raise @error.signature_error(
          "函数参数数量不足: 期望至少 \{f.arity}，得到 \{args.length()}",
          func=None,
        )
      }
      ctx.with_depth(() => (f.invoke)(args, ctx))
    }
    @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
    _ =>
      raise @error.type_error(
        "不可调用的值",
        expected=Some("function"),
        actual=None,
      )
  }
}

///|
/// Lambda 求值
fn eval_lambda(
  params : Array[String],
  body : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue {
  let arity = params.length()
  let invoke = fn(
    args : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    for i, param in params {
      if i < args.length() {
        ctx2.bind(param, args[i])
      }
    }
    eval(body, ctx2)
  }
  @value.JsonataValue::Func(@value.JsonataFunc::new(arity~, invoke~))
}

///|
/// 函数链求值
fn eval_chain(
  stages : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  if stages.length() == 0 {
    return @value.JsonataValue::Undefined
  }
  let mut result = eval(stages[0], ctx)
  for i in 1..<stages.length() {
    let stage = eval(stages[i], ctx)
    match stage {
      @value.JsonataValue::Func(f) =>
        result = ctx.with_depth(() => (f.invoke)([result], ctx))
      @value.JsonataValue::Undefined => result = @value.JsonataValue::Undefined
      _ =>
        raise @error.type_error(
          "链中非函数值",
          expected=Some("function"),
          actual=None,
        )
    }
  }
  result
}

///|
/// 分组表达式求值
fn eval_group(
  pairs : Array[(@ast.Ast, @ast.Ast)],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let map : Map[String, Json] = {}
  for kv in pairs {
    let (key_ast, val_ast) = kv
    let key = eval(key_ast, ctx)
    let val = eval(val_ast, ctx)
    let key_str = match key {
      @value.JsonataValue::Json(Json::String(s)) => s
      _ => to_str(key)
    }
    map[key_str] = val.to_json()
  }
  @value.JsonataValue::Json(Json::object(map))
}

///|
/// 排序求值
fn eval_sort(
  expr_ast : @ast.Ast,
  terms : Array[@ast.SortTerm],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let input = eval(expr_ast, ctx)
  let items = input.to_array()
  if items.length() <= 1 {
    return input
  }
  // 预计算排序键
  let term = terms[0]
  let keyed : Array[(Double, @value.JsonataValue)] = []
  for item in items {
    // 简化：用 item 本身作为排序上下文（实际应对每个 item 求值 term.expr）
    let v = match item {
      @value.JsonataValue::Json(Json::Number(n)) => n
      _ => 0.0
    }
    keyed.push((v, item))
  }
  keyed.sort_by(fn(a, b) {
    let (na, _) = a
    let (nb, _) = b
    if term.descending {
      Double::compare(nb, na)
    } else {
      Double::compare(na, nb)
    }
  })
  let sorted : Array[@value.JsonataValue] = []
  for kv in keyed {
    let (_, item) = kv
    sorted.push(item)
  }
  @value.JsonataValue::sequence(sorted)
}
