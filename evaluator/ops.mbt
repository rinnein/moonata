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
      "&" => return concat_or_merge(lhs, rhs)
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
    ) => @value.JsonataValue::Json(Json::boolean(str_lt(l, r)))
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
    ) => @value.JsonataValue::Json(Json::boolean(str_lte(l, r)))
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
    ) => @value.JsonataValue::Json(Json::boolean(str_gt(l, r)))
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
    ) => @value.JsonataValue::Json(Json::boolean(str_gte(l, r)))
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
      let args = apply_context_argument(args, f, ctx)
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
fn apply_context_argument(
  args : Array[@value.JsonataValue],
  f : @value.JsonataFunc,
  ctx : @value.EvalContext,
) -> Array[@value.JsonataValue] {
  if f.arity == 0 || args.length() >= f.arity || !f.contextual {
    return args
  }
  let out : Array[@value.JsonataValue] = [ctx.current()]
  for arg in args {
    out.push(arg)
  }
  out
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
  ctx : @value.EvalContext,
) -> @value.JsonataValue {
  let arity = params.length()
  let captured_ctx = ctx.capture()
  let invoke = fn(
    args : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let call_ctx = captured_ctx.capture()
    call_ctx.inherit_missing_bindings_from(ctx2)
    for i, param in params {
      if i < args.length() {
        call_ctx.bind(param, args[i])
      } else if lambda_missing_arg_uses_context(signature) {
        call_ctx.bind(param, ctx2.current())
      }
    }
    eval(body, call_ctx)
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
    match stages[i] {
      @ast.Ast::Apply(func~, args~) =>
        if !has_placeholder(args) {
          result = eval_chain_apply_stage(result, func, args, ctx)
          continue
        }
      @ast.Ast::Transform(path~, update~, delete~) => {
        result = eval_transform(result, path, update, delete, ctx)
        continue
      }
      _ => ()
    }
    let stage = eval(stages[i], ctx)
    match stage {
      @value.JsonataValue::Func(f) =>
        match result {
          @value.JsonataValue::Func(left_func) =>
            result = compose_functions(left_func, f)
          _ => result = ctx.with_depth(() => (f.invoke)([result], ctx))
        }
      @value.JsonataValue::Regex(pattern~, flags~) =>
        result = chain_regex_match(result, pattern, flags)
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
fn eval_chain_apply_stage(
  input : @value.JsonataValue,
  func_ast : @ast.Ast,
  args_ast : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let func_val = eval(func_ast, ctx)
  let target = match func_val {
    @value.JsonataValue::Func(f) => f
    @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
    _ =>
      raise @error.type_error(
        "链中非函数值",
        expected=Some("function"),
        actual=None,
      )
  }
  let captured : Array[@value.JsonataValue] = []
  for arg_ast in args_ast {
    captured.push(eval(arg_ast, ctx))
  }
  let stage_invoke = fn(
    provided : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let args : Array[@value.JsonataValue] = []
    for item in provided {
      args.push(item)
    }
    for item in captured {
      args.push(item)
    }
    ctx2.with_depth(() => (target.invoke)(args, ctx2))
  }
  let stage_func = @value.JsonataFunc::new(
    arity=1,
    signature=target.signature,
    invoke=stage_invoke,
  )
  match input {
    @value.JsonataValue::Func(left_func) =>
      compose_functions(left_func, stage_func)
    _ => ctx.with_depth(() => (stage_func.invoke)([input], ctx))
  }
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
/// 链式正则匹配：`str ~> /regex/flags`。
fn chain_regex_match(
  input : @value.JsonataValue,
  pattern : String,
  flags : String,
) -> @value.JsonataValue {
  let s = match input {
    @value.JsonataValue::Json(Json::String(s)) => s
    _ => return @value.JsonataValue::Undefined
  }
  let re = try {
    if flags == "" {
      @regexp.compile(pattern)
    } else {
      @regexp.compile(pattern, flags~)
    }
  } catch {
    _ => return @value.JsonataValue::Undefined
  }
  let m = re.execute(s)
  if m.matched() {
    let map : Map[String, Json] = {}
    map["match"] = match m.get(0) {
      Some(s_) => Json::string(s_.to_owned())
      None => Json::string("")
    }
    let groups : Array[Json] = []
    let results = m.results()
    for i in 1..<results.length() {
      match results[i] {
        Some(g) => groups.push(Json::string(g.to_owned()))
        None => groups.push(Json::null())
      }
    }
    map["groups"] = Json::array(groups)
    @value.JsonataValue::Json(Json::object(map))
  } else {
    @value.JsonataValue::Undefined
  }
}

///|
/// 变换求值：在输入结构中按路径定位并应用更新/删除。
fn eval_transform(
  input : @value.JsonataValue,
  path_ast : @ast.Ast,
  update_ast : @ast.Ast,
  delete_ast : @ast.Ast?,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  // 深克隆输入
  let cloned = deep_clone(input)

  // 计算更新模板（一次性求值）
  let update_val = eval(update_ast, ctx)

  // 计算删除键（一次性求值）
  let delete_keys = match delete_ast {
    Some(d) => {
      let dval = eval(d, ctx)
      match dval {
        @value.JsonataValue::Sequence(arr) => {
          let keys : Array[String] = []
          for item in arr {
            match item {
              @value.JsonataValue::Json(Json::String(s)) => keys.push(s)
              _ => continue
            }
          }
          keys
        }
        @value.JsonataValue::Json(Json::String(s)) => [s]
        _ => []
      }
    }
    None => []
  }

  // 递归在深克隆结构中替换变换匹配项
  transform_replace(cloned, path_ast, update_val, delete_keys, ctx)
}

///|
/// 递归在深克隆结构中替换变换匹配项。
fn transform_replace(
  root : @value.JsonataValue,
  path_ast : @ast.Ast,
  update_val : @value.JsonataValue,
  delete_keys : Array[String],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  // 重新计算路径以获取匹配项索引
  let path_result = ctx.with_context(current=root, parent=root, fn() -> @value.JsonataValue raise @error.JsonataError {
    eval(path_ast, ctx)
  })
  let matches = path_result.to_array()
  if matches.length() == 0 {
    return root
  }

  // 遍历路径步：如果路径是简单的 Path(steps)，则按步逐层定位并替换
  match path_ast {
    @ast.Ast::Path(steps) if steps.length() > 0 => {
      let mut result = root
      for i = 0; i < steps.length(); i = i + 1 {
        let step = steps[i]
        let is_last = i == steps.length() - 1
        result = transform_replace_step(
          result, step, is_last, update_val, delete_keys, steps, i, ctx,
        )
      }
      result
    }
    _ => root
  }
}

///|
/// 对单个路径步执行深克隆替换。
fn transform_replace_step(
  input : @value.JsonataValue,
  step : @ast.Step,
  is_last : Bool,
  update_val : @value.JsonataValue,
  delete_keys : Array[String],
  all_steps : Array[@ast.Step],
  step_idx : Int,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  match (input, step.kind) {
    (@value.JsonataValue::Json(Json::Array(arr)), _) => {
      let out : Array[Json] = []
      for item in arr {
        let result = transform_replace_step(
          @value.JsonataValue::Json(item),
          step,
          is_last,
          update_val,
          delete_keys,
          all_steps,
          step_idx,
          ctx,
        )
        let json_val = match result {
          @value.JsonataValue::Json(j) => j
          _ => item
        }
        out.push(json_val)
      }
      @value.JsonataValue::Json(Json::array(out))
    }
    (@value.JsonataValue::Sequence(items), _) => {
      let out : Array[@value.JsonataValue] = []
      for item in items {
        let result = transform_replace_step(
          item, step, is_last, update_val, delete_keys, all_steps, step_idx, ctx,
        )
        out.push(result)
      }
      @value.JsonataValue::sequence(out)
    }
    (@value.JsonataValue::Json(Json::Object(map)), @ast.StepKind::Name(name)) => {
      let new_map : Map[String, Json] = {}
      for k, v in map {
        new_map[k] = v
      }
      let name_match = if is_last {
        let new_val = apply_transform_update(
          @value.JsonataValue::Json(map.get(name).unwrap_or(Json::null())),
          update_val,
          delete_keys,
        )
        match new_val {
          @value.JsonataValue::Json(j) => Some(j)
          _ => new_map.get(name)
        }
      } else {
        let sub_result = transform_replace_step(
          @value.JsonataValue::Json(map.get(name).unwrap_or(Json::null())),
          all_steps[step_idx + 1],
          step_idx + 1 == all_steps.length() - 1,
          update_val,
          delete_keys,
          all_steps,
          step_idx + 1,
          ctx,
        )
        match sub_result {
          @value.JsonataValue::Json(j) => Some(j)
          _ => new_map.get(name)
        }
      }
      match name_match {
        Some(j) => new_map.set(name, j)
        None => ()
      }
      @value.JsonataValue::Json(Json::object(new_map))
    }
    _ => input
  }
}

///|
/// 对单值应用更新/删除。
fn apply_transform_update(
  value : @value.JsonataValue,
  update_val : @value.JsonataValue,
  delete_keys : Array[String],
) -> @value.JsonataValue {
  match value {
    @value.JsonataValue::Json(Json::Object(map)) => {
      let new_map : Map[String, Json] = {}
      for k, v in map {
        new_map[k] = v
      }
      match update_val {
        @value.JsonataValue::Json(Json::Object(update_map)) =>
          for k, v in update_map {
            new_map[k] = v
          }
        _ => ()
      }
      for k in delete_keys {
        new_map.remove(k) |> ignore
      }
      @value.JsonataValue::Json(Json::object(new_map))
    }
    _ => value
  }
}

///|
/// 深克隆 JsonataValue。
fn deep_clone(value : @value.JsonataValue) -> @value.JsonataValue {
  match value {
    @value.JsonataValue::Json(j) =>
      @value.JsonataValue::Json(deep_clone_json(j))
    @value.JsonataValue::Sequence(items) => {
      let cloned : Array[@value.JsonataValue] = []
      for item in items {
        cloned.push(deep_clone(item))
      }
      @value.JsonataValue::sequence(cloned)
    }
    _ => value
  }
}

///|
fn deep_clone_json(json : Json) -> Json {
  match json {
    Json::Object(map) => {
      let new_map : Map[String, Json] = {}
      for k, v in map {
        new_map[k] = deep_clone_json(v)
      }
      Json::object(new_map)
    }
    Json::Array(arr) => {
      let new_arr : Array[Json] = []
      for item in arr {
        new_arr.push(deep_clone_json(item))
      }
      Json::array(new_arr)
    }
    _ => json
  }
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
    // 跳过 undefined 值（匹配 JSONata：undefined 字段不出现在对象中）
    if val.is_undefined() {
      continue
    }
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
    @value.JsonataValue::Sequence(arr) =>
      match arr.length() {
        0 => Json::null()
        1 => json_for_constructor(arr[0])
        _ => {
          let out : Array[Json] = []
          for item in arr {
            out.push(json_for_constructor(item))
          }
          Json::array(out)
        }
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
  // 对每项在上下文中求值排序键，保留原始索引用于稳定排序
  let keyed : Array[(Array[@value.JsonataValue], Int, @value.JsonataValue)] = []
  for i, item in items {
    let keys : Array[@value.JsonataValue] = []
    for term in terms {
      let key = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
        eval(term.expr, ctx)
      })
      keys.push(key)
    }
    keyed.push((keys, i, item))
  }
  keyed.sort_by(fn(a, b) {
    let (ka, ia, _) = a
    let (kb, ib, _) = b
    let cmp = compare_keys(ka, kb, terms)
    if cmp != 0 {
      cmp
    } else {
      ia - ib
    }
  })
  let sorted : Array[@value.JsonataValue] = []
  for kv in keyed {
    let (_, _, item) = kv
    sorted.push(item)
  }
  @value.JsonataValue::sequence(sorted)
}

///|
/// 多键比较：Dictionary order，每个键按方向判别。
fn compare_keys(
  ka : Array[@value.JsonataValue],
  kb : Array[@value.JsonataValue],
  terms : Array[@ast.SortTerm],
) -> Int {
  for i = 0; i < ka.length(); i = i + 1 {
    let descending = terms[i].descending
    let cmp = compare_sort_value(ka[i], kb[i])
    if cmp != 0 {
      return if descending { -cmp } else { cmp }
    }
  }
  0
}

///|
/// 排序值比较：Number 数值比较，String 字典比较，Undefined 排在最后。
fn compare_sort_value(a : @value.JsonataValue, b : @value.JsonataValue) -> Int {
  match (a, b) {
    (
      @value.JsonataValue::Json(Json::Number(na, ..)),
      @value.JsonataValue::Json(Json::Number(nb, ..)),
    ) => Double::compare(na, nb)
    (
      @value.JsonataValue::Json(Json::String(sa)),
      @value.JsonataValue::Json(Json::String(sb)),
    ) => str_cmp(sa, sb)
    (@value.JsonataValue::Undefined, @value.JsonataValue::Undefined) => 0
    (@value.JsonataValue::Undefined, _) => 1 // Undefined 排在最后
    (_, @value.JsonataValue::Undefined) => -1
    _ => {
      let sa = to_str(a)
      let sb = to_str(b)
      str_cmp(sa, sb)
    }
  }
}

///|
/// 字节序字符串比较替代（规避 MoonBit String< collation bug）。
fn str_lt(sa : String, sb : String) -> Bool {
  str_cmp(sa, sb) < 0
}

///|
fn str_gt(sa : String, sb : String) -> Bool {
  str_cmp(sa, sb) > 0
}

///|
fn str_lte(sa : String, sb : String) -> Bool {
  str_cmp(sa, sb) <= 0
}

///|
fn str_gte(sa : String, sb : String) -> Bool {
  str_cmp(sa, sb) >= 0
}

///|
/// 字节序字符串比较，返回 -1/0/1（规避 MoonBit String< collation bug）。
fn str_cmp(sa : String, sb : String) -> Int {
  let la = sa.length()
  let lb = sb.length()
  let len = if la < lb { la } else { lb }
  for i = 0; i < len; i = i + 1 {
    let ca = sa[i]
    let cb = sb[i]
    if ca != cb {
      return if ca.to_int() < cb.to_int() { -1 } else { 1 }
    }
  }
  if la < lb {
    -1
  } else if la > lb {
    1
  } else {
    0
  }
}
