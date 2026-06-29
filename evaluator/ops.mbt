///|
/// 二元运算求值
fn eval_binary(
  op : String,
  lhs_ast : @ast.Ast,
  rhs_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let lhs = eval(lhs_ast, ctx)
  if op == "??" {
    if lhs is @value.JsonataValue::Undefined {
      return eval(rhs_ast, ctx)
    }
    return lhs
  } else if op == "?:" {
    if to_bool(lhs) {
      return lhs
    }
    return eval(rhs_ast, ctx)
  }
  if op == "&&" {
    if !to_bool(lhs) {
      return @value.JsonataValue::Json(Json::boolean(false))
    }
    let rhs = eval(rhs_ast, ctx)
    return @value.JsonataValue::Json(Json::boolean(to_bool(rhs)))
  } else if op == "||" {
    if to_bool(lhs) {
      return @value.JsonataValue::Json(Json::boolean(true))
    }
    let rhs = eval(rhs_ast, ctx)
    return @value.JsonataValue::Json(Json::boolean(to_bool(rhs)))
  }
  let rhs = eval(rhs_ast, ctx)
  // Undefined 传播（多数运算）
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    match op {
      "=" => return compare_eq(lhs, rhs)
      "!=" => return compare_neq(lhs, rhs)
      "in" => return in_op(lhs, rhs)
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
    ".." => range_op(lhs, rhs)
    "&" => concat_or_merge(lhs, rhs)
    "=" => compare_eq(lhs, rhs)
    "!=" => compare_neq(lhs, rhs)
    "<" => compare_lt(lhs, rhs)
    "<=" => compare_lte(lhs, rhs)
    ">" => compare_gt(lhs, rhs)
    ">=" => compare_gte(lhs, rhs)
    "in" => in_op(lhs, rhs)
    "&&" => logic_and(lhs, rhs)
    "||" => logic_or(lhs, rhs)
    "??" => if lhs is @value.JsonataValue::Undefined { rhs } else { lhs }
    "?:" => if to_bool(lhs) { lhs } else { rhs }
    _ => raise @error.runtime_error("未知运算符: \{op}")
  }
}

///|
fn in_op(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    return @value.JsonataValue::Json(Json::boolean(false))
  }
  let found = match rhs {
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let mut matched = false
      for item in arr {
        if json_equal(lhs.to_json(), item) {
          matched = true
          break
        }
      }
      matched
    }
    @value.JsonataValue::Sequence(arr) => {
      let mut matched = false
      for item in arr {
        if json_equal(lhs.to_json(), item.to_json()) {
          matched = true
          break
        }
      }
      matched
    }
    _ => json_equal(lhs.to_json(), rhs.to_json())
  }
  @value.JsonataValue::Json(Json::boolean(found))
}

///|
fn range_op(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  let start = to_number(lhs).to_int()
  let end = to_number(rhs).to_int()
  let items : Array[@value.JsonataValue] = []
  if start <= end {
    for i in start..<=end {
      items.push(@value.JsonataValue::Json(Json::number(i.to_double())))
    }
  }
  @value.JsonataValue::Sequence(items)
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
/// `&` 运算：对象深度合并或字符串拼接
///
/// - 两边均为对象 → 深度合并（递归合并同键的对象，否则右侧覆盖）
/// - 其他情况 → 字符串拼接
fn concat_or_merge(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  match (lhs, rhs) {
    (
      @value.JsonataValue::Json(Json::Object(a)),
      @value.JsonataValue::Json(Json::Object(b)),
    ) => {
      let result : Map[String, Json] = {}
      // 先复制左侧
      for k, v in a {
        result[k] = v
      }
      // 合并右侧：同键且均为对象则递归合并，否则右侧覆盖
      for k, v in b {
        match (result.get(k), @value.JsonataValue::Json(v)) {
          (
            Some(Json::Object(left_obj)),
            @value.JsonataValue::Json(Json::Object(right_obj)),
          ) => {
            let merged = concat_or_merge(
              @value.JsonataValue::Json(Json::object(left_obj)),
              @value.JsonataValue::Json(Json::object(right_obj)),
            )
            result[k] = merged.to_json()
          }
          _ => result[k] = v
        }
      }
      @value.JsonataValue::Json(Json::object(result))
    }
    _ => concat_str(lhs, rhs)
  }
}

///|
/// 比较：相等
fn compare_eq(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue {
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    return @value.JsonataValue::Json(Json::boolean(false))
  }
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
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    return @value.JsonataValue::Json(Json::boolean(true))
  }
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
  match (lhs, rhs) {
    (
      @value.JsonataValue::Json(Json::String(l)),
      @value.JsonataValue::Json(Json::String(r)),
    ) => @value.JsonataValue::Json(Json::boolean(l < r))
    _ => {
      let l = to_number(lhs)
      let r = to_number(rhs)
      @value.JsonataValue::Json(Json::boolean(l < r))
    }
  }
}

///|
/// 比较：小于等于
fn compare_lte(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  match (lhs, rhs) {
    (
      @value.JsonataValue::Json(Json::String(l)),
      @value.JsonataValue::Json(Json::String(r)),
    ) => @value.JsonataValue::Json(Json::boolean(l <= r))
    _ => {
      let l = to_number(lhs)
      let r = to_number(rhs)
      @value.JsonataValue::Json(Json::boolean(l <= r))
    }
  }
}

///|
/// 比较：大于
fn compare_gt(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  match (lhs, rhs) {
    (
      @value.JsonataValue::Json(Json::String(l)),
      @value.JsonataValue::Json(Json::String(r)),
    ) => @value.JsonataValue::Json(Json::boolean(l > r))
    _ => {
      let l = to_number(lhs)
      let r = to_number(rhs)
      @value.JsonataValue::Json(Json::boolean(l > r))
    }
  }
}

///|
/// 比较：大于等于
fn compare_gte(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  match (lhs, rhs) {
    (
      @value.JsonataValue::Json(Json::String(l)),
      @value.JsonataValue::Json(Json::String(r)),
    ) => @value.JsonataValue::Json(Json::boolean(l >= r))
    _ => {
      let l = to_number(lhs)
      let r = to_number(rhs)
      @value.JsonataValue::Json(Json::boolean(l >= r))
    }
  }
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
/// 数组构造。
///
/// JSONata 的数组构造返回 JSON array；运行时序列会展开为数组元素，但已经
/// 构造出来的 JSON array 作为普通元素保留，避免 `[1, [2, 3]]` 被展平。
fn eval_construct(
  items : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let results : Array[Json] = []
  for item in items {
    let v = eval(item, ctx)
    match v {
      @value.JsonataValue::Undefined => continue
      @value.JsonataValue::Sequence(arr) =>
        for item in arr {
          match item {
            @value.JsonataValue::Undefined => ()
            _ => results.push(json_for_constructor(item))
          }
        }
      _ => results.push(json_for_constructor(v))
    }
  }
  @value.JsonataValue::Json(Json::array(results))
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
  ctx.with_binding(name, value, fn() -> @value.JsonataValue raise @error.JsonataError {
    eval(body_ast, ctx)
  })
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
///
/// 支持部分应用：当提供参数少于元数时，返回捕获已提供参数的柯里化函数。
fn eval_apply(
  func_ast : @ast.Ast,
  args_ast : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let func_val = eval(func_ast, ctx)
  match func_val {
    @value.JsonataValue::Func(f) => {
      if has_placeholder(args_ast) {
        return make_partial_apply(f, args_ast, ctx)
      }
      let args : Array[@value.JsonataValue] = []
      for arg_ast in args_ast {
        args.push(eval(arg_ast, ctx))
      }
      f.check_args(args)
      if args.length() < f.arity && should_partial_on_missing(f) {
        // 部分应用：返回捕获已提供参数的柯里化函数
        let captured = args
        let remaining = f.arity - args.length()
        let original = f
        let invoke = fn(
          more_args : Array[@value.JsonataValue],
          ctx2 : @value.EvalContext,
        ) -> @value.JsonataValue raise @error.JsonataError {
          let all : Array[@value.JsonataValue] = []
          for a in more_args {
            all.push(a)
          }
          for a in captured {
            all.push(a)
          }
          ctx2.with_depth(() => (original.invoke)(all, ctx2))
        }
        @value.JsonataValue::Func(
          @value.JsonataFunc::new(
            arity=remaining,
            signature=f.signature,
            invoke~,
          ),
        )
      } else {
        ctx.with_depth(() => (f.invoke)(args, ctx))
      }
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
fn has_placeholder(args : Array[@ast.Ast]) -> Bool {
  let mut found = false
  for arg in args {
    if arg is @ast.Ast::Placeholder {
      found = true
      break
    }
  }
  found
}

///|
fn should_partial_on_missing(f : @value.JsonataFunc) -> Bool {
  match f.signature {
    Some(sig) => !sig.contains(":")
    None => true
  }
}

///|
fn make_partial_apply(
  f : @value.JsonataFunc,
  args_ast : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let captured : Array[@value.JsonataValue?] = []
  let mut placeholder_count = 0
  for arg_ast in args_ast {
    if arg_ast is @ast.Ast::Placeholder {
      captured.push(None)
      placeholder_count += 1
    } else {
      captured.push(Some(eval(arg_ast, ctx)))
    }
  }
  let invoke = fn(
    provided : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let args : Array[@value.JsonataValue] = []
    let mut provided_index = 0
    for item in captured {
      match item {
        Some(value) => args.push(value)
        None => {
          if provided_index < provided.length() {
            args.push(provided[provided_index])
          } else {
            args.push(@value.JsonataValue::Undefined)
          }
          provided_index += 1
        }
      }
    }
    ctx2.with_depth(() => (f.invoke)(args, ctx2))
  }
  @value.JsonataValue::Func(
    @value.JsonataFunc::new(
      arity=placeholder_count,
      signature=f.signature,
      invoke~,
    ),
  )
}

///|
/// Lambda 求值
fn eval_lambda(
  params : Array[String],
  body : @ast.Ast,
  signature : String?,
  _ctx : @value.EvalContext,
) -> @value.JsonataValue {
  let arity = params.length()
  let invoke = fn(
    args : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    for i, param in params {
      if i < args.length() {
        ctx2.bind(param, args[i])
      } else if lambda_missing_arg_uses_context(signature) {
        ctx2.bind(param, ctx2.current())
      }
    }
    eval(body, ctx2)
  }
  @value.JsonataValue::Func(
    @value.JsonataFunc::new(arity~, signature~, invoke~),
  )
}

///|
fn lambda_missing_arg_uses_context(signature : String?) -> Bool {
  match signature {
    Some(sig) => sig.contains("-")
    None => false
  }
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
        match result {
          @value.JsonataValue::Func(left_func) =>
            result = compose_functions(left_func, f)
          _ => result = ctx.with_depth(() => (f.invoke)([result], ctx))
        }
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
fn compose_functions(
  first : @value.JsonataFunc,
  second : @value.JsonataFunc,
) -> @value.JsonataValue {
  let invoke = fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let intermediate = ctx.with_depth(() => (first.invoke)(args, ctx))
    ctx.with_depth(() => (second.invoke)([intermediate], ctx))
  }
  @value.JsonataValue::Func(
    @value.JsonataFunc::new(
      arity=first.arity,
      signature=first.signature,
      invoke~,
    ),
  )
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
    map[key_str] = json_for_constructor(val)
  }
  @value.JsonataValue::Json(Json::object(map))
}

///|
fn json_for_constructor(value : @value.JsonataValue) -> Json {
  match value {
    @value.JsonataValue::Func(_) => Json::string("")
    @value.JsonataValue::Regex(_) => Json::string("")
    @value.JsonataValue::Sequence(arr) => {
      let out : Array[Json] = []
      for item in arr {
        out.push(json_for_constructor(item))
      }
      Json::array(out)
    }
    _ => value.to_json()
  }
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
      @value.JsonataValue::Json(Json::Number(n, ..)) => n
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
