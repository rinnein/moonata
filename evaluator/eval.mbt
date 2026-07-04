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
    @ast.Ast::Conditional(condition~, consequent~, alternate~) =>
      eval_conditional(condition, consequent, alternate, ctx)
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
fn eval_conditional(
  condition_ast : @ast.Ast,
  consequent : @ast.Ast,
  alternate : @ast.Ast?,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let condition = eval(condition_ast, ctx)
  if to_bool(condition) {
    eval(consequent, ctx)
  } else {
    match alternate {
      Some(expr) => eval(expr, ctx)
      None => @value.JsonataValue::Undefined
    }
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
/// 路径求值：逐步遍历。
/// 处理 focus/tuple 变量绑定步（由 `@ $var` 标注）。
/// GroupAggregate 步在 eval_path_from 内联处理以保留变量绑定。
fn eval_path(
  steps : Array[@ast.Step],
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  if steps.length() == 0 {
    return input
  }
  eval_path_from(input, steps, 0, ctx, steps.length())
}

///|
/// 从指定位置开始路径求值，处理 focus/tuple 变量绑定步。
///
/// 当某步带有 `focus` 标注时，先正常求值该步，再对每项绑定变量名，
/// 并将 *原始* 输入传给后续步（匹配 JSONata-js tuple stream 语义：
/// `@ $var` 标注的步求值后，`inputSequence` 不更新）。
///
/// 若剩余步以 GroupAggregate 结尾，则 focus 分支结果合并且键值聚合，
/// 而非当作独立元素收集（保留变量绑定）。
fn eval_path_from(
  input : @value.JsonataValue,
  steps : Array[@ast.Step],
  start : Int,
  ctx : @value.EvalContext,
  stop_at : Int,
) -> @value.JsonataValue raise @error.JsonataError {
  let mut current = input
  let mut i = start
  let mut name_was_grouped = false
  while i < stop_at {
    let step = steps[i]
    // 非 focus 步中的 GroupAggregate：对当前元素求值并合并
    if is_aggregate_step(step) {
      return access_group_aggregate(current, agg_ast(step).unwrap(), ctx)
    }
    // #$var 位置索引绑定：在上下文中持久化 pos_var 名，后续 filter/map 步迭代时自动绑定
    match step.pos_var {
      Some(pos_name) => {
        name_was_grouped = false
        current = eval_step(step, current, ctx)
        ctx.bind("__pos__", @value.JsonataValue::Json(Json::string(pos_name)))
        i = i + 1
      }
      None =>
        match step.focus {
          Some(name) => {
            name_was_grouped = false
            // 步带 focus：求值步结果，对每项绑变量，后续步从原始 input 开始
            let step_result = eval_step(step, current, ctx)
            // 检查剩余步是否以 GroupAggregate 结尾
            let has_group = stop_at > i + 1 &&
              is_aggregate_step(steps[stop_at - 1])
            if has_group {
              let merged : Map[String, Array[Json]] = {}
              for item in step_result.to_array() {
                let r = ctx.with_binding(name, item, fn() -> @value.JsonataValue raise @error.JsonataError {
                  eval_path_from(input, steps, i + 1, ctx, stop_at)
                })
                merge_into_group(r, merged)
              }
              return @value.JsonataValue::Json(
                Json::object(build_merged_group(merged)),
              )
            } else {
              let results : Array[@value.JsonataValue] = []
              for item in step_result.to_array() {
                let r = ctx.with_binding(name, item, fn() -> @value.JsonataValue raise @error.JsonataError {
                  eval_path_from(input, steps, i + 1, ctx, stop_at)
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
              return @value.JsonataValue::Sequence(results)
            }
          }
          None => {
            // Group-aware evaluation for Name→Index/Slice patterns:
            // a.b[N] means index each b individually, not the flat result.
            // Only when the Name step was processed via access_field_grouped
            // (i.e., it had an Index/Slice step following).
            if name_was_grouped {
              match step.kind {
                @ast.StepKind::Index(_) | @ast.StepKind::Slice(_, _) =>
                  current = access_grouped(current, step, ctx)
                _ => current = eval_step(step, current, ctx)
              }
              name_was_grouped = false
            } else {
              match step.kind {
                @ast.StepKind::Name(name) =>
                  if i + 1 < stop_at {
                    match steps[i + 1].kind {
                      @ast.StepKind::Index(_) | @ast.StepKind::Slice(_, _) => {
                        current = access_field_grouped(current, name)
                        name_was_grouped = true
                      }
                      _ => current = eval_step(step, current, ctx)
                    }
                  } else {
                    current = eval_step(step, current, ctx)
                  }
                _ => current = eval_step(step, current, ctx)
              }
            }
            i = i + 1
          }
        }
    }
  }
  current
}

///|
/// 判断步是否为 GroupAggregate。
fn is_aggregate_step(step : @ast.Step) -> Bool {
  match step.kind {
    @ast.StepKind::GroupAggregate(_) => true
    _ => false
  }
}

///|
/// 提取 GroupAggregate 的 AST（仅在 is_aggregate_step 为 true 时安全）。
fn agg_ast(step : @ast.Step) -> @ast.Ast? {
  match step.kind {
    @ast.StepKind::GroupAggregate(ast) => Some(ast)
    _ => None
  }
}

///|
/// 将分组求值结果合并到 accumulator 中。
fn merge_into_group(
  value : @value.JsonataValue,
  merged : Map[String, Array[Json]],
) -> Unit {
  match value {
    @value.JsonataValue::Json(Json::Object(map)) =>
      for name, val in map {
        match merged.get(name) {
          Some(values) => values.push(val)
          None => merged.set(name, [val])
        }
      }
    @value.JsonataValue::Sequence(arr) =>
      for v in arr {
        merge_into_group(v, merged)
      }
    @value.JsonataValue::Undefined => ()
    _ => ()
  }
}

///|
/// 从合并后的 accumulator 构建最终 Json::Object。
/// 单值保持原样，多值转为数组。
fn build_merged_group(merged : Map[String, Array[Json]]) -> Map[String, Json] {
  let out : Map[String, Json] = {}
  for name, values in merged {
    out[name] = if values.length() == 1 {
      values[0]
    } else {
      Json::array(values)
    }
  }
  out
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
    @ast.StepKind::GroupAggregate(_) => input
  }
}

///|
/// 递归步求值（**）：深度优先遍历，每层先应用步再下降。
fn eval_step_recursive(
  step : @ast.Step,
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let results : Array[@value.JsonataValue] = []
  descend_apply(input, step, ctx, results)
  @value.JsonataValue::sequence(results)
}

///|
/// 深度优先下降：对当前节点应用步，再递归进入子节点。
/// Name/Index 步仅对 Object 应用以避免数组展开与下降重复；
/// Wildcard/Arrayify 等步对结构类型（Object/Array/Sequence）展开后丢弃容器。
fn descend_apply(
  current : @value.JsonataValue,
  step : @ast.Step,
  ctx : @value.EvalContext,
  results : Array[@value.JsonataValue],
) -> Unit raise @error.JsonataError {
  // Name/Index 步仅对 Object 应用，避免数组展开与下降元素重复
  let apply_now : Bool = match step.kind {
    @ast.StepKind::Name(_) | @ast.StepKind::Index(_) =>
      match current {
        @value.JsonataValue::Json(Json::Object(_)) => true
        _ => false
      }
    _ => true // Wildcard / Slice / Filter / Map / Arrayify 等都应用
  }
  if apply_now {
    let r = eval_step_single(step, current, ctx)
    // 如果步带有 index（来自 **.X[0] 解析合并），对每项单独索引
    match step.index {
      Some(idx) =>
        for item in r.to_array() {
          let indexed = access_index(item, idx)
          push_path_result(results, indexed)
        }
      None => push_path_result(results, r)
    }
  }
  // 下降进入子节点
  match current {
    @value.JsonataValue::Json(j) =>
      match j {
        Json::Object(map) =>
          for _, v in map {
            descend_apply(@value.JsonataValue::Json(v), step, ctx, results)
          }
        Json::Array(arr) =>
          for v in arr {
            descend_apply(@value.JsonataValue::Json(v), step, ctx, results)
          }
        _ => ()
      }
    @value.JsonataValue::Sequence(arr) =>
      for v in arr {
        descend_apply(v, step, ctx, results)
      }
    _ => ()
  }
}

///|
/// 字段访问。
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
/// 分组感知的字段访问：与 access_field 相同，但保留顶层数组元素为单元素
/// 以支持后续 [N]/Slice 路径步的逐元素索引（如 a.b[N] 语义）。
fn access_field_grouped(
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
      let results : Array[@value.JsonataValue] = []
      for v in arr {
        let r = access_field_grouped(@value.JsonataValue::Json(v), name)
        match r {
          @value.JsonataValue::Undefined => continue
          @value.JsonataValue::Sequence(inner) =>
            for e in inner {
              results.push(e)
            }
          _ => results.push(r)
        }
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Sequence(arr) => {
      let results : Array[@value.JsonataValue] = []
      for item in arr {
        let r = access_field_grouped(item, name)
        match r {
          @value.JsonataValue::Undefined => continue
          @value.JsonataValue::Sequence(inner) =>
            for e in inner {
              results.push(e)
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
fn push_path_result(
  results : Array[@value.JsonataValue],
  value : @value.JsonataValue,
) -> Unit {
  match value {
    @value.JsonataValue::Undefined => ()
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        push_path_result(results, item)
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
    @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
    // Non-array/sequence values: [0] is a no-op (keep as singleton)
    _ => input
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
/// 分组感知的 Index/Slice：对 Sequence 中每个元素单独应用 Index/Slice 步，
/// 分组感知的 Index/Slice：对 Sequence 中每个元素单独应用 Index/Slice 步，
/// 保留数组元素的分组上下文（如 `arr.nest1[0]` 应为每个 `nest1` 的 `[0]`）。
fn access_grouped(
  input : @value.JsonataValue,
  step : @ast.Step,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  match input {
    @value.JsonataValue::Sequence(arr) => {
      let results : Array[@value.JsonataValue] = []
      for item in arr {
        let r = eval_step_single(step, item, ctx)
        match r {
          @value.JsonataValue::Undefined => continue
          _ => results.push(r)
        }
      }
      @value.JsonataValue::sequence(results)
    }
    _ => eval_step(step, input, ctx)
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
  let pos_var : String? = match ctx.lookup("__pos__") {
    Some(@value.JsonataValue::Json(Json::String(name))) => Some(name)
    _ => None
  }
  for i, item in items {
    // 将当前项绑定为 @，父级设为 input
    let r = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
      // 同时绑定 # 为当前索引
      ctx.bind("#", @value.JsonataValue::Json(Json::number(i.to_double())))
      // 若有 #$var 位置变量，一并绑定
      match pos_var {
        Some(name) =>
          ctx.bind(name, @value.JsonataValue::Json(Json::number(i.to_double())))
        None => ()
      }
      ctx.with_depth(() => eval(expr, ctx))
    })
    match r {
      @value.JsonataValue::Json(Json::True) => results.push(item)
      @value.JsonataValue::Json(Json::False) => continue
      @value.JsonataValue::Undefined => continue
      _ =>
        // 位置过滤：数字匹配索引，负数从末尾算起
        match r {
          @value.JsonataValue::Json(Json::Number(n, ..)) => {
            let num = n.to_int()
            let target = if num < 0 { items.length() + num } else { num }
            if target == i {
              results.push(item)
            }
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
/// 序列规则展平结果。字段访问返回的数组自动展开为序列元素，
/// 但显式构造数组 `[ ... ]` 保持原样。
fn access_map(
  input : @value.JsonataValue,
  expr : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let items = input.to_array()
  let results : Array[@value.JsonataValue] = []
  let top_is_construct = expr is @ast.Ast::Construct(_)
  let pos_var : String? = match ctx.lookup("__pos__") {
    Some(@value.JsonataValue::Json(Json::String(name))) => Some(name)
    _ => None
  }
  for i, item in items {
    let r = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
      match pos_var {
        Some(name) =>
          ctx.bind(name, @value.JsonataValue::Json(Json::number(i.to_double())))
        None => ()
      }
      ctx.with_depth(() => eval(expr, ctx))
    })
    match r {
      @value.JsonataValue::Undefined => continue
      @value.JsonataValue::Sequence(arr) =>
        for v in arr {
          push_path_result(results, v)
        }
      @value.JsonataValue::Json(Json::Array(arr)) =>
        if top_is_construct {
          results.push(r)
        } else {
          for v in arr {
            results.push(@value.JsonataValue::Json(v))
          }
        }
      _ => results.push(r)
    }
  }
  match results.length() {
    0 => @value.JsonataValue::Undefined
    _ => @value.JsonataValue::Sequence(results)
  }
}

///|
/// 分组聚合 `{...}`（无前置 `.`）：对输入中每项求值 Group，再将所有结果
/// 的键值对合并为单个对象。重复键的值收集为数组。
fn access_group_aggregate(
  input : @value.JsonataValue,
  group_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let items = input.to_array()
  let merged : Map[String, Array[Json]] = {}
  for item in items {
    let r = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
      ctx.with_depth(() => eval(group_ast, ctx))
    })
    match r {
      @value.JsonataValue::Json(Json::Object(map)) =>
        for name, val in map {
          match merged.get(name) {
            Some(values) => values.push(val)
            None => merged.set(name, [val])
          }
        }
      @value.JsonataValue::Undefined => continue
      _ => ()
    }
  }
  // 将合并结果转为最终对象：单值保持单值，多值作为数组
  let out : Map[String, Json] = {}
  for name, values in merged {
    out[name] = if values.length() == 1 {
      values[0]
    } else {
      Json::array(values)
    }
  }
  @value.JsonataValue::Json(Json::object(out))
}
