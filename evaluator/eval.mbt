///|
/// 求值器入口：AST → JsonataValue。
pub fn eval(
  ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  ctx.tick()
  match ast {
    @ast.Ast::String(s) => @value.JsonataValue::Json(Json::string(s))
    @ast.Ast::Regex(pattern~, flags~) =>
      @value.JsonataValue::Regex(pattern~, flags~)
    @ast.Ast::Number(n) => @value.JsonataValue::Json(Json::number(n))
    @ast.Ast::Boolean(b) => @value.JsonataValue::Json(Json::boolean(b))
    @ast.Ast::Null => @value.JsonataValue::Json(Json::null())
    @ast.Ast::Placeholder => @value.JsonataValue::Undefined
    @ast.Ast::Var(name) => eval_var(name, ctx)
    @ast.Ast::Path(steps) => eval_path(steps, ctx.current(), ctx)
    @ast.Ast::Binary(op~, lhs~, rhs~) => eval_binary(op, lhs, rhs, ctx)
    @ast.Ast::Unary(op~, expr~) => eval_unary(op, expr, ctx)
    @ast.Ast::Construct(items) => eval_construct(items, ctx)
    @ast.Ast::Bind(name~, value~, body~) => eval_bind(name, value, body, ctx)
    @ast.Ast::Block(exprs) => eval_block(exprs, ctx)
    @ast.Ast::Apply(func~, args~) => eval_apply(func, args, ctx)
    @ast.Ast::Lambda(params~, body~, signature~) =>
      eval_lambda(params, body, signature, ctx)
    @ast.Ast::Chain(stages) => eval_chain(stages, ctx)
    @ast.Ast::Group(pairs) => eval_group(pairs, ctx)
    @ast.Ast::Sort(expr~, terms~) => eval_sort(expr, terms, ctx)
  }
}

///|
/// 变量求值：$ / $name / $$ / @ / #
fn eval_var(name : String, ctx : @value.EvalContext) -> @value.JsonataValue {
  match name {
    "" => ctx.current() // $ 当前上下文
    "$$" => ctx.root() // $$ 根上下文
    "@" => ctx.current() // @ 当前项
    "#" =>
      // # 位置变量（谓词过滤中绑定），未绑定时 Undefined
      match ctx.lookup("#") {
        Some(v) => v
        None => @value.JsonataValue::Undefined
      }
    _ =>
      match ctx.lookup(name) {
        Some(v) => v
        None => @value.JsonataValue::Undefined
      }
  }
}

///|
/// 路径求值：逐步遍历
fn eval_path(
  steps : Array[@ast.Step],
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let mut current = if steps.length() > 0 {
    match steps[0].kind {
      @ast.StepKind::Eval(expr) => {
        let mut base = eval(expr, ctx)
        for i in 1..<steps.length() {
          base = eval_step(steps[i], base, ctx)
        }
        return base
      }
      @ast.StepKind::Filter(@ast.Ast::Var(name)) => {
        let base = eval_var(name, ctx)
        // 对剩余步求值
        let mut v = base
        for i in 1..<steps.length() {
          v = eval_step(steps[i], v, ctx)
        }
        return v
      }
      _ => input
    }
  } else {
    input
  }
  for step in steps {
    current = eval_step(step, current, ctx)
  }
  current
}

///|
/// 单步求值
fn eval_step(
  step : @ast.Step,
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  match step.stage {
    @ast.StepStage::Recursive => eval_step_recursive(step, input, ctx)
    @ast.StepStage::Single => eval_step_single(step, input, ctx)
  }
}

///|
/// 单层步求值
fn eval_step_single(
  step : @ast.Step,
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  match step.kind {
    @ast.StepKind::Eval(expr) => eval(expr, ctx)
    @ast.StepKind::Name(name) => access_field(input, name)
    @ast.StepKind::Wildcard => access_wildcard(input)
    @ast.StepKind::Index(i) => access_index(input, i)
    @ast.StepKind::Slice(start, end) => access_slice(input, start, end)
    @ast.StepKind::Filter(expr) => access_filter(input, expr, ctx)
    @ast.StepKind::Map(expr) => access_map(input, expr, ctx)
    @ast.StepKind::Arrayify => access_arrayify(input)
  }
}

///|
/// 递归步求值（**）
fn eval_step_recursive(
  step : @ast.Step,
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let collected : Array[@value.JsonataValue] = []
  collect_recursive(input, collected)
  // 对每个收集到的值应用单层步
  let results : Array[@value.JsonataValue] = []
  for v in collected {
    let r = eval_step_single(step, v, ctx)
    match r {
      @value.JsonataValue::Undefined => continue
      @value.JsonataValue::Sequence(arr) =>
        for item in arr {
          results.push(item)
        }
      _ => results.push(r)
    }
  }
  @value.JsonataValue::sequence(results)
}

///|
/// 递归收集所有子值
fn collect_recursive(
  input : @value.JsonataValue,
  out : Array[@value.JsonataValue],
) -> Unit {
  out.push(input)
  match input {
    @value.JsonataValue::Json(j) =>
      match j {
        Json::Object(map) =>
          for _, v in map {
            collect_recursive(@value.JsonataValue::Json(v), out)
          }
        Json::Array(arr) =>
          for v in arr {
            collect_recursive(@value.JsonataValue::Json(v), out)
          }
        _ => ()
      }
    @value.JsonataValue::Sequence(arr) =>
      for v in arr {
        collect_recursive(v, out)
      }
    _ => ()
  }
}

///|
/// 字段访问
fn access_field(
  input : @value.JsonataValue,
  name : String,
) -> @value.JsonataValue {
  match input {
    @value.JsonataValue::Json(Json::Object(map)) =>
      match map.get(name) {
        Some(v) => @value.JsonataValue::Json(v)
        None => @value.JsonataValue::Undefined
      }
    @value.JsonataValue::Json(Json::Array(arr)) => {
      // 对数组元素映射访问字段
      let results : Array[@value.JsonataValue] = []
      for v in arr {
        let r = access_field(@value.JsonataValue::Json(v), name)
        push_path_result(results, r)
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Sequence(arr) => {
      let results : Array[@value.JsonataValue] = []
      for item in arr {
        let r = access_field(item, name)
        push_path_result(results, r)
      }
      @value.JsonataValue::sequence(results)
    }
    _ => @value.JsonataValue::Undefined
  }
}

///|
fn push_path_result(
  results : Array[@value.JsonataValue],
  value : @value.JsonataValue,
) -> Unit {
  match value {
    @value.JsonataValue::Undefined => ()
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        results.push(item)
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for item in arr {
        results.push(@value.JsonataValue::Json(item))
      }
    _ => results.push(value)
  }
}

///|
/// 通配符访问（所有字段或所有元素）
fn access_wildcard(input : @value.JsonataValue) -> @value.JsonataValue {
  match input {
    @value.JsonataValue::Json(Json::Object(map)) => {
      let results : Array[@value.JsonataValue] = []
      for _, v in map {
        results.push(@value.JsonataValue::Json(v))
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let results : Array[@value.JsonataValue] = []
      for v in arr {
        results.push(@value.JsonataValue::Json(v))
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Sequence(arr) => {
      let results : Array[@value.JsonataValue] = []
      for item in arr {
        let r = access_wildcard(item)
        match r {
          @value.JsonataValue::Undefined => continue
          @value.JsonataValue::Sequence(inner) =>
            for i in inner {
              results.push(i)
            }
          _ => results.push(r)
        }
      }
      @value.JsonataValue::sequence(results)
    }
    _ => @value.JsonataValue::Undefined
  }
}

///|
/// 下标访问
fn access_index(input : @value.JsonataValue, i : Int) -> @value.JsonataValue {
  match input {
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let len = arr.length()
      let idx = if i < 0 { len + i } else { i }
      if idx >= 0 && idx < len {
        @value.JsonataValue::Json(arr[idx])
      } else {
        @value.JsonataValue::Undefined
      }
    }
    @value.JsonataValue::Sequence(arr) => {
      let len = arr.length()
      let idx = if i < 0 { len + i } else { i }
      if idx >= 0 && idx < len {
        arr[idx]
      } else {
        @value.JsonataValue::Undefined
      }
    }
    _ => @value.JsonataValue::Undefined
  }
}

///|
/// 切片访问
fn access_slice(
  input : @value.JsonataValue,
  start : Int?,
  end : Int?,
) -> @value.JsonataValue {
  match input {
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let len = arr.length()
      let s = start.unwrap_or(0)
      let e = end.unwrap_or(len)
      let results : Array[@value.JsonataValue] = []
      for i in s..<e.max(0).min(len) {
        results.push(@value.JsonataValue::Json(arr[i]))
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Sequence(arr) => {
      let len = arr.length()
      let s = start.unwrap_or(0)
      let e = end.unwrap_or(len)
      let results : Array[@value.JsonataValue] = []
      for i in s..<e.max(0).min(len) {
        results.push(arr[i])
      }
      @value.JsonataValue::sequence(results)
    }
    _ => @value.JsonataValue::Undefined
  }
}

///|
/// 谓词过滤
///
/// 迭代每个元素时将其绑定为 `@`（当前项），父级 `$$` 设为输入序列。
/// 谓词表达式可引用 `@` 访问当前项字段，引用 `#` 访问当前索引。
fn access_filter(
  input : @value.JsonataValue,
  expr : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let items = input.to_array()
  let results : Array[@value.JsonataValue] = []
  for i, item in items {
    // 将当前项绑定为 @，父级设为 input
    let r = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
      // 同时绑定 # 为当前索引
      ctx.bind("#", @value.JsonataValue::Json(Json::number(i.to_double())))
      ctx.with_depth(() => eval(expr, ctx))
    })
    match r {
      @value.JsonataValue::Json(Json::True) => results.push(item)
      @value.JsonataValue::Json(Json::False) => continue
      @value.JsonataValue::Undefined => continue
      _ =>
        // 位置过滤：数字匹配索引
        match r {
          @value.JsonataValue::Json(Json::Number(n, ..)) =>
            if n.to_int() == i {
              results.push(item)
            }
          _ => results.push(r)
        }
    }
  }
  match results.length() {
    0 => @value.JsonataValue::Undefined
    _ => @value.JsonataValue::Sequence(results)
  }
}

///|
/// 空数组选择器 `[]`：强制将当前结果包装为 JSON array。
fn access_arrayify(input : @value.JsonataValue) -> @value.JsonataValue {
  let arr : Array[Json] = []
  for item in input.to_array() {
    arr.push(json_for_constructor(item))
  }
  @value.JsonataValue::Json(Json::array(arr))
}

///|
/// 路径映射 `.(expr)`。
///
/// 对输入序列中的每个元素，将其绑定为当前项并求值表达式，最后按 JSONata
/// 序列规则展平结果。
fn access_map(
  input : @value.JsonataValue,
  expr : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let items = input.to_array()
  let results : Array[@value.JsonataValue] = []
  for item in items {
    let r = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
      ctx.with_depth(() => eval(expr, ctx))
    })
    match r {
      @value.JsonataValue::Undefined => continue
      @value.JsonataValue::Sequence(arr) =>
        for v in arr {
          results.push(v)
        }
      _ => results.push(r)
    }
  }
  match results.length() {
    0 => @value.JsonataValue::Undefined
    _ => @value.JsonataValue::Sequence(results)
  }
}
