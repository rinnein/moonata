///|
/// 路径求值中的值与父级链。
priv struct PathFrame {
  value : @value.JsonataValue
  ancestors : Array[@value.JsonataValue]
  bindings : Map[String, @value.JsonataValue]
}

///|
fn path_frame(
  value : @value.JsonataValue,
  ancestors : Array[@value.JsonataValue],
) -> PathFrame {
  { value, ancestors, bindings: {} }
}

///|
fn path_frame_with_bindings(
  value : @value.JsonataValue,
  ancestors : Array[@value.JsonataValue],
  bindings : Map[String, @value.JsonataValue],
) -> PathFrame {
  { value, ancestors, bindings: copy_frame_bindings(bindings) }
}

///|
fn copy_frame_bindings(
  bindings : Map[String, @value.JsonataValue],
) -> Map[String, @value.JsonataValue] {
  let out : Map[String, @value.JsonataValue] = {}
  for name, value in bindings {
    out[name] = value
  }
  out
}

///|
fn bind_frame(
  frame : PathFrame,
  name : String,
  value : @value.JsonataValue,
) -> PathFrame {
  let bindings = copy_frame_bindings(frame.bindings)
  bindings[name] = value
  path_frame_with_bindings(frame.value, frame.ancestors, bindings)
}

///|
fn bind_frame_index(frame : PathFrame, name : String, index : Int) -> PathFrame {
  bind_frame(
    frame,
    name,
    @value.JsonataValue::Json(Json::number(index.to_double())),
  )
}

///|
fn[T] with_frame_bindings(
  ctx : @value.EvalContext,
  bindings : Map[String, @value.JsonataValue],
  f : () -> T raise @error.JsonataError,
) -> T raise @error.JsonataError {
  if bindings.length() == 0 {
    return f()
  }
  let saved = ctx.bindings_snapshot()
  for name, value in bindings {
    ctx.bind(name, value)
  }
  try {
    let r = f()
    ctx.restore_bindings(saved)
    r
  } catch {
    e => {
      ctx.restore_bindings(saved)
      raise e
    }
  }
}

///|
fn prepend_ancestor(
  parent : @value.JsonataValue,
  ancestors : Array[@value.JsonataValue],
) -> Array[@value.JsonataValue] {
  let next : Array[@value.JsonataValue] = [parent]
  for ancestor in ancestors {
    next.push(ancestor)
  }
  next
}

///|
fn tail_ancestors(
  ancestors : Array[@value.JsonataValue],
) -> Array[@value.JsonataValue] {
  let next : Array[@value.JsonataValue] = []
  if ancestors.length() > 1 {
    for i in 1..<ancestors.length() {
      next.push(ancestors[i])
    }
  }
  next
}

///|
fn ast_contains_parent(ast : @ast.Ast) -> Bool {
  match ast {
    @ast.Ast::Path(steps) => steps_contain_parent(steps)
    @ast.Ast::QuotedName(_) => false
    @ast.Ast::Binary(lhs~, rhs~, ..) =>
      ast_contains_parent(lhs) || ast_contains_parent(rhs)
    @ast.Ast::Unary(expr~, ..) => ast_contains_parent(expr)
    @ast.Ast::Conditional(condition~, consequent~, alternate~) => {
      let alt_contains = match alternate {
        Some(expr) => ast_contains_parent(expr)
        None => false
      }
      ast_contains_parent(condition) ||
      ast_contains_parent(consequent) ||
      alt_contains
    }
    @ast.Ast::Construct(items) => {
      let mut found = false
      for item in items {
        if ast_contains_parent(item) {
          found = true
          break
        }
      }
      found
    }
    @ast.Ast::Group(pairs) => {
      let mut found = false
      for pair in pairs {
        let (key, val) = pair
        if ast_contains_parent(key) || ast_contains_parent(val) {
          found = true
          break
        }
      }
      found
    }
    @ast.Ast::Sort(expr~, terms~) =>
      if ast_contains_parent(expr) {
        true
      } else {
        let mut found = false
        for term in terms {
          if ast_contains_parent(term.expr) {
            found = true
            break
          }
        }
        found
      }
    @ast.Ast::Lambda(body~, ..) => ast_contains_parent(body)
    @ast.Ast::Bind(value~, ..) => ast_contains_parent(value)
    @ast.Ast::Apply(func~, args~) =>
      if ast_contains_parent(func) {
        true
      } else {
        let mut found = false
        for arg in args {
          if ast_contains_parent(arg) {
            found = true
            break
          }
        }
        found
      }
    @ast.Ast::Chain(stages) | @ast.Ast::Block(stages) => {
      let mut found = false
      for stage in stages {
        if ast_contains_parent(stage) {
          found = true
          break
        }
      }
      found
    }
    @ast.Ast::Transform(path~, update~, delete~) => {
      let delete_contains = match delete {
        Some(expr) => ast_contains_parent(expr)
        None => false
      }
      ast_contains_parent(path) ||
      ast_contains_parent(update) ||
      delete_contains
    }
    _ => false
  }
}

///|
fn steps_contain_parent(steps : Array[@ast.Step]) -> Bool {
  let mut found = false
  for step in steps {
    if step.kind == @ast.StepKind::Parent {
      found = true
      break
    }
    match step.kind {
      @ast.StepKind::Eval(expr)
      | @ast.StepKind::Filter(expr)
      | @ast.StepKind::Map(expr)
      | @ast.StepKind::GroupAggregate(expr) =>
        if ast_contains_parent(expr) {
          found = true
          break
        }
      _ => ()
    }
  }
  found
}

///|
fn ast_contains_tuple_binding(ast : @ast.Ast) -> Bool {
  match ast {
    @ast.Ast::Path(steps) => steps_contain_tuple_binding(steps)
    @ast.Ast::Sort(expr~, ..) => ast_contains_tuple_binding(expr)
    _ => false
  }
}

///|
fn steps_contain_tuple_binding(steps : Array[@ast.Step]) -> Bool {
  let mut found = false
  for step in steps {
    if step.pos_var is Some(_) || step.focus is Some(_) || step.tuple {
      found = true
      break
    }
    match step.kind {
      @ast.StepKind::Eval(expr)
      | @ast.StepKind::Filter(expr)
      | @ast.StepKind::Map(expr)
      | @ast.StepKind::GroupAggregate(expr) =>
        if ast_contains_tuple_binding(expr) {
          found = true
          break
        }
      _ => ()
    }
  }
  found
}

///|
/// 求值器入口：AST → JsonataValue。
pub fn eval(
  ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  ctx.tick()
  match ast {
    @ast.Ast::String(s) => @value.JsonataValue::Json(Json::string(s))
    @ast.Ast::QuotedName(name) =>
      eval_path([@ast.name_step(name)], ctx.current(), ctx)
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
    @ast.Ast::Bind(name~, value~) => eval_bind(name, value, ctx)
    @ast.Ast::Block(exprs) => eval_block(exprs, ctx)
    @ast.Ast::Apply(func~, args~) => eval_apply(func, args, ctx)
    @ast.Ast::Lambda(params~, body~, signature~) =>
      eval_lambda(params, body, signature, ctx)
    @ast.Ast::Chain(stages) => eval_chain(stages, ctx)
    @ast.Ast::Group(pairs) => eval_group(pairs, ctx)
    @ast.Ast::Sort(expr~, terms~) => eval_sort(expr, terms, ctx)
    @ast.Ast::Transform(path~, update~, delete~) =>
      eval_transform(ctx.current(), path, update, delete, ctx)
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
/// `[]`（Arrayify）步在路径末尾阻止单例提升，确保结果始终为 JSON array。
fn eval_path(
  steps : Array[@ast.Step],
  input : @value.JsonataValue,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  if steps.length() == 0 {
    return input
  }
  let has_arrayify = steps_has_arrayify(steps)
  let result = if steps_contain_parent(steps) ||
    steps_contain_tuple_binding(steps) {
    let frames = eval_path_frames(
      [path_frame(input, ctx.ancestors())],
      steps,
      0,
      ctx,
      steps.length(),
    )
    frames_to_value(frames)
  } else {
    eval_path_from(input, steps, 0, ctx, steps.length())
  }
  if has_arrayify {
    arrayify_wrap(result)
  } else {
    result
  }
}

///|
/// 检查路径步中是否包含 Arrayify 步。
fn steps_has_arrayify(steps : Array[@ast.Step]) -> Bool {
  let mut found = false
  for step in steps {
    if step.kind == @ast.StepKind::Arrayify {
      found = true
      break
    }
  }
  found
}

///|
/// 将值包装为 JSON array（用于 `[]` 步的语义）。
/// `Sequence` → 保持为 `Json::Array`（阻止单例提升）
/// `Json::Array` → 保持原样（已是数组）
/// 其它单值 → `Json::Array([value])`
fn arrayify_wrap(value : @value.JsonataValue) -> @value.JsonataValue {
  match value {
    @value.JsonataValue::Sequence(arr) =>
      @value.JsonataValue::Json(Json::array(arr.map(fn(v) { v.to_json() })))
    @value.JsonataValue::Json(Json::Array(_)) => value
    @value.JsonataValue::Json(v) => @value.JsonataValue::Json(Json::array([v]))
    @value.JsonataValue::Undefined => @value.JsonataValue::Json(Json::array([]))
    _ => @value.JsonataValue::Json(Json::array([]))
  }
}

///|
/// 父级感知路径求值：只在表达式树包含 `%` 时启用。
fn eval_path_frames(
  input : Array[PathFrame],
  steps : Array[@ast.Step],
  start : Int,
  ctx : @value.EvalContext,
  stop_at : Int,
) -> Array[PathFrame] raise @error.JsonataError {
  let mut frames = input
  let mut i = start
  let mut name_was_grouped = false
  let mut is_first_step = true
  while i < stop_at {
    let step = steps[i]
    if step.kind == @ast.StepKind::Parent {
      frames = parent_frames(frames)
      i = i + 1
      continue
    }
    if is_aggregate_step(step) {
      return value_to_frames(
        access_group_aggregate_frames(frames, agg_ast(step).unwrap(), ctx),
        ctx.current(),
        ctx.ancestors(),
      )
    }
    match step.pos_var {
      Some(pos_name) => {
        name_was_grouped = false
        frames = eval_step_frames(step, frames, ctx, grouped=false)
        for j, frame in frames {
          frames[j] = bind_frame_index(frame, pos_name, j)
        }
        i = i + 1
      }
      None =>
        match step.focus {
          Some(name) => {
            name_was_grouped = false
            let step_frames = eval_step_frames(step, frames, ctx, grouped=false)
            let has_group = stop_at > i + 1 &&
              is_aggregate_step(steps[stop_at - 1])
            if has_group {
              let merged : Map[String, Array[Json]] = {}
              for frame in step_frames {
                let r = ctx.with_binding(name, frame.value, fn() -> @value.JsonataValue raise @error.JsonataError {
                  frames_to_value(
                    eval_path_frames(input, steps, i + 1, ctx, stop_at),
                  )
                })
                merge_into_group(r, merged)
              }
              return value_to_frames(
                @value.JsonataValue::Json(
                  Json::object(build_merged_group(merged)),
                ),
                ctx.current(),
                ctx.ancestors(),
              )
            } else {
              let results : Array[PathFrame] = []
              for frame in step_frames {
                let r = ctx.with_binding(name, frame.value, fn() -> @value.JsonataValue raise @error.JsonataError {
                  frames_to_value(
                    eval_path_frames(input, steps, i + 1, ctx, stop_at),
                  )
                })
                match r {
                  @value.JsonataValue::Undefined => continue
                  _ =>
                    for
                      out in value_to_frames_with_bindings(
                        r,
                        frame.value,
                        frame.ancestors,
                        frame.bindings,
                      ) {
                      results.push(out)
                    }
                }
              }
              return results
            }
          }
          None => {
            if name_was_grouped {
              match step.kind {
                @ast.StepKind::Index(_) | @ast.StepKind::Slice(_, _) =>
                  frames = eval_step_frames(step, frames, ctx, grouped=true)
                _ => frames = eval_step_frames(step, frames, ctx, grouped=false)
              }
              name_was_grouped = false
            } else {
              match step.kind {
                @ast.StepKind::Index(i) =>
                  frames = index_frame_sequence(frames, i)
                @ast.StepKind::Slice(start, end) =>
                  frames = slice_frame_sequence(frames, start, end)
                @ast.StepKind::Name(_) =>
                  if i + 1 < stop_at {
                    match steps[i + 1].kind {
                      @ast.StepKind::Index(_) | @ast.StepKind::Slice(_, _) =>
                        if is_first_step && frames_are_sequence_like(frames) {
                          frames = eval_step_frames(
                            step,
                            frames,
                            ctx,
                            grouped=false,
                          )
                        } else {
                          frames = eval_step_frames(
                            step,
                            frames,
                            ctx,
                            grouped=true,
                          )
                          name_was_grouped = true
                        }
                      _ =>
                        frames = eval_step_frames(
                          step,
                          frames,
                          ctx,
                          grouped=false,
                        )
                    }
                  } else {
                    frames = eval_step_frames(step, frames, ctx, grouped=false)
                  }
                _ => frames = eval_step_frames(step, frames, ctx, grouped=false)
              }
              is_first_step = false
            }
            i = i + 1
          }
        }
    }
  }
  frames
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
  // 标记是否为路径的"首个有效步"：首步的 Name→Index 在 Array/Sequence
  // 输入上不应分组（如 phone[0] 应索引整体而非每元素），后续步的
  // Name→Index 则应分组（如 a.b[0] 需每元素索引）。
  let mut is_first_step = true
  // 父级栈：维护路径上非 Parent 步的输入值，用于 % 导航
  let parent_stack : Array[@value.JsonataValue] = []
  while i < stop_at {
    let step = steps[i]
    // Parent 步：回到栈顶父级值；栈空时回退到 ctx.parent（Filter/Map 内部场景）
    if step.kind == @ast.StepKind::Parent {
      match parent_stack.pop() {
        Some(p) => current = p
        None => current = ctx.parent()
      }
      i = i + 1
      continue
    }
    // 非 Parent 步：将当前值入栈（作为后续 % 的父级）
    parent_stack.push(current)
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
                  _ => results.push(item)
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
              let mut should_clear = true
              match step.kind {
                @ast.StepKind::Index(_) | @ast.StepKind::Slice(_, _) =>
                  current = access_grouped(current, step, ctx)
                @ast.StepKind::Filter(expr) => {
                  current = access_filter_grouped(current, expr, ctx)
                  should_clear = false
                }
                _ => current = eval_step(step, current, ctx)
              }
              if should_clear {
                name_was_grouped = false
              }
            } else {
              match step.kind {
                @ast.StepKind::Name(name) =>
                  if i + 1 < stop_at {
                    match steps[i + 1].kind {
                      @ast.StepKind::Index(_) | @ast.StepKind::Slice(_, _) =>
                        // Group Name→Index: index each sub-array individually,
                        // not the flat result.  Only skip grouping for the very
                        // first step on an Array/Sequence root (e.g. phone[0]
                        // should index the overall flat sequence).
                        if is_first_step {
                          match current {
                            @value.JsonataValue::Sequence(_)
                            | @value.JsonataValue::Json(Json::Array(_)) =>
                              current = eval_step(step, current, ctx)
                            _ => {
                              current = access_field_grouped(current, name)
                              name_was_grouped = true
                            }
                          }
                        } else {
                          current = access_field_grouped(current, name)
                          name_was_grouped = true
                        }
                      @ast.StepKind::Filter(_) =>
                        // Group Name→Filter: preserve array structure so that
                        // subsequent Index/Slice steps apply per-element.
                        if is_first_step {
                          match current {
                            @value.JsonataValue::Sequence(_)
                            | @value.JsonataValue::Json(Json::Array(_)) =>
                              current = eval_step(step, current, ctx)
                            _ => {
                              current = access_field_grouped(current, name)
                              name_was_grouped = true
                            }
                          }
                        } else {
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
              is_first_step = false
            }
            i = i + 1
          }
        }
    }
  }
  current
}

///|
fn index_frame_sequence(
  frames : Array[PathFrame],
  index : Int,
) -> Array[PathFrame] {
  let results : Array[PathFrame] = []
  let len = frames.length()
  let idx = if index < 0 { len + index } else { index }
  if idx >= 0 && idx < len {
    results.push(frames[idx])
  }
  results
}

///|
fn slice_frame_sequence(
  frames : Array[PathFrame],
  start : Int?,
  end : Int?,
) -> Array[PathFrame] {
  let results : Array[PathFrame] = []
  let len = frames.length()
  let s = start.unwrap_or(0)
  let e = end.unwrap_or(len)
  for i in s..<e.max(0).min(len) {
    results.push(frames[i])
  }
  results
}

///|
fn frames_to_value(frames : Array[PathFrame]) -> @value.JsonataValue {
  let values : Array[@value.JsonataValue] = []
  for frame in frames {
    values.push(frame.value)
  }
  @value.JsonataValue::sequence(values)
}

///|
fn value_to_frames(
  value : @value.JsonataValue,
  parent : @value.JsonataValue,
  ancestors : Array[@value.JsonataValue],
) -> Array[PathFrame] {
  value_to_frames_with_bindings(value, parent, ancestors, {})
}

///|
fn value_to_frames_with_bindings(
  value : @value.JsonataValue,
  parent : @value.JsonataValue,
  ancestors : Array[@value.JsonataValue],
  bindings : Map[String, @value.JsonataValue],
) -> Array[PathFrame] {
  let frames : Array[PathFrame] = []
  let lineage = prepend_ancestor(parent, ancestors)
  match value {
    @value.JsonataValue::Undefined => ()
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        for
          frame in value_to_frames_with_bindings(
            item, parent, ancestors, bindings,
          ) {
          frames.push(frame)
        }
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for item in arr {
        frames.push(
          path_frame_with_bindings(
            @value.JsonataValue::Json(item),
            lineage,
            bindings,
          ),
        )
      }
    _ => frames.push(path_frame_with_bindings(value, lineage, bindings))
  }
  frames
}

///|
fn parent_frames(frames : Array[PathFrame]) -> Array[PathFrame] {
  let results : Array[PathFrame] = []
  for frame in frames {
    if frame.ancestors.length() > 0 {
      results.push(
        path_frame_with_bindings(
          frame.ancestors[0],
          tail_ancestors(frame.ancestors),
          frame.bindings,
        ),
      )
    }
  }
  results
}

///|
fn frames_are_sequence_like(frames : Array[PathFrame]) -> Bool {
  if frames.length() != 1 {
    false
  } else {
    match frames[0].value {
      @value.JsonataValue::Sequence(_)
      | @value.JsonataValue::Json(Json::Array(_)) => true
      _ => false
    }
  }
}

///|
fn eval_step_frames(
  step : @ast.Step,
  frames : Array[PathFrame],
  ctx : @value.EvalContext,
  grouped~ : Bool,
) -> Array[PathFrame] raise @error.JsonataError {
  let results : Array[PathFrame] = []
  match step.kind {
    @ast.StepKind::Filter(expr) => {
      access_filter_frames(frames, expr, ctx, results)
      return results
    }
    @ast.StepKind::Map(expr) => {
      access_map_frames(frames, expr, ctx, results)
      return results
    }
    @ast.StepKind::GroupAggregate(ast) => {
      let r = access_group_aggregate_frames(frames, ast, ctx)
      for out in value_to_frames(r, ctx.current(), ctx.ancestors()) {
        results.push(out)
      }
      return results
    }
    _ => ()
  }
  match step.kind {
    @ast.StepKind::Eval(@ast.Ast::Sort(expr~, terms~)) if ast_contains_tuple_binding(
        expr,
      ) => {
      for out in eval_sort_frames(expr, terms, ctx) {
        results.push(out)
      }
      return results
    }
    _ => ()
  }
  for frame in frames {
    match step.stage {
      @ast.StepStage::Recursive => {
        let r = eval_step_recursive(step, frame.value, ctx)
        for
          out in value_to_frames_with_bindings(
            r,
            frame.value,
            frame.ancestors,
            frame.bindings,
          ) {
          results.push(out)
        }
      }
      @ast.StepStage::Single =>
        eval_step_frame_single(step, frame, ctx, results, grouped~)
    }
  }
  results
}

///|
fn eval_step_frame_single(
  step : @ast.Step,
  frame : PathFrame,
  ctx : @value.EvalContext,
  results : Array[PathFrame],
  grouped~ : Bool,
) -> Unit raise @error.JsonataError {
  match step.kind {
    @ast.StepKind::Eval(expr) => {
      let r = ctx.with_lineage(current=frame.value, ancestors=frame.ancestors, fn() -> @value.JsonataValue raise @error.JsonataError {
        with_frame_bindings(ctx, frame.bindings, fn() -> @value.JsonataValue raise @error.JsonataError {
          eval(expr, ctx)
        })
      })
      for
        out in value_to_frames_with_bindings(
          r,
          frame.value,
          frame.ancestors,
          frame.bindings,
        ) {
        results.push(out)
      }
    }
    @ast.StepKind::Name(name) =>
      if grouped {
        access_field_grouped_frames(frame, name, results)
      } else {
        access_field_frames(frame, name, results)
      }
    @ast.StepKind::Wildcard => access_wildcard_frames(frame, results)
    @ast.StepKind::Index(i) => access_index_frame(frame, i, results, grouped~)
    @ast.StepKind::Slice(start, end) =>
      access_slice_frame(frame, start, end, results, grouped~)
    @ast.StepKind::Filter(_) => ()
    @ast.StepKind::Map(_) => ()
    @ast.StepKind::Arrayify =>
      // 作为 no-op 标记，实际数组包裹由 eval_path 在末尾处理
      results.push(frame)
    @ast.StepKind::GroupAggregate(_) => ()
    @ast.StepKind::Parent =>
      for out in parent_frames([frame]) {
        results.push(out)
      }
  }
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
/// 单值保持原样；重复的相同字符串折叠为标量，否则转为数组。
fn build_merged_group(merged : Map[String, Array[Json]]) -> Map[String, Json] {
  let out : Map[String, Json] = {}
  for name, values in merged {
    out[name] = json_for_merged_values(values)
  }
  out
}

///|
fn json_for_merged_values(values : Array[Json]) -> Json {
  if values.length() == 1 || all_string_values_equal(values) {
    values[0]
  } else if all_are_json_arrays(values) {
    // 所有值都是 Json::Array，展平为单个数组
    // 例如 [[1], [2]] → [1, 2]
    let flat : Array[Json] = []
    for v in values {
      match v {
        Json::Array(arr) =>
          for item in arr {
            flat.push(item)
          }
        _ => flat.push(v)
      }
    }
    Json::array(flat)
  } else {
    Json::array(values)
  }
}

///|
fn all_string_values_equal(values : Array[Json]) -> Bool {
  if values.length() <= 1 {
    return true
  }
  let first = match values[0] {
    Json::String(s) => s
    _ => return false
  }
  for i in 1..<values.length() {
    match values[i] {
      Json::String(s) if s == first => ()
      _ => return false
    }
  }
  true
}

///|
fn all_are_json_arrays(values : Array[Json]) -> Bool {
  for v in values {
    match v {
      Json::Array(_) => ()
      _ => return false
    }
  }
  true
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
    @ast.StepKind::Parent => ctx.parent()
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
  if step.kind == @ast.StepKind::Wildcard {
    match current {
      @value.JsonataValue::Json(Json::Object(_))
      | @value.JsonataValue::Json(Json::Array(_))
      | @value.JsonataValue::Sequence(_) =>
        push_unique_recursive_result(results, current)
      _ => ()
    }
  }
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
      None =>
        if step.kind == @ast.StepKind::Wildcard {
          push_unique_recursive_path_result(results, r)
        } else {
          push_path_result(results, r)
        }
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
fn push_unique_recursive_path_result(
  results : Array[@value.JsonataValue],
  value : @value.JsonataValue,
) -> Unit {
  match value {
    @value.JsonataValue::Undefined => ()
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        push_unique_recursive_path_result(results, item)
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for item in arr {
        push_unique_recursive_result(results, @value.JsonataValue::Json(item))
      }
    _ => push_unique_recursive_result(results, value)
  }
}

///|
fn push_unique_recursive_result(
  results : Array[@value.JsonataValue],
  value : @value.JsonataValue,
) -> Unit {
  for item in results {
    if item.equal(value) {
      return
    }
  }
  results.push(value)
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
fn access_field_frames(
  frame : PathFrame,
  name : String,
  results : Array[PathFrame],
) -> Unit {
  match frame.value {
    @value.JsonataValue::Json(Json::Object(map)) =>
      match map.get(name) {
        Some(v) => push_child_json_frames(v, frame, results, flatten_array=true)
        None => ()
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for v in arr {
        access_field_frames(
          path_frame_with_bindings(
            @value.JsonataValue::Json(v),
            frame.ancestors,
            frame.bindings,
          ),
          name,
          results,
        )
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        access_field_frames(
          path_frame_with_bindings(item, frame.ancestors, frame.bindings),
          name,
          results,
        )
      }
    _ => ()
  }
}

///|
fn access_field_grouped_frames(
  frame : PathFrame,
  name : String,
  results : Array[PathFrame],
) -> Unit {
  match frame.value {
    @value.JsonataValue::Json(Json::Object(map)) =>
      match map.get(name) {
        Some(v) =>
          push_child_json_frames(v, frame, results, flatten_array=false)
        None => ()
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for v in arr {
        access_field_grouped_frames(
          path_frame_with_bindings(
            @value.JsonataValue::Json(v),
            frame.ancestors,
            frame.bindings,
          ),
          name,
          results,
        )
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        access_field_grouped_frames(
          path_frame_with_bindings(item, frame.ancestors, frame.bindings),
          name,
          results,
        )
      }
    _ => ()
  }
}

///|
fn push_child_json_frames(
  json : Json,
  parent_frame : PathFrame,
  results : Array[PathFrame],
  flatten_array~ : Bool,
) -> Unit {
  let lineage = prepend_ancestor(parent_frame.value, parent_frame.ancestors)
  match json {
    Json::Array(arr) if flatten_array =>
      for item in arr {
        results.push(
          path_frame_with_bindings(
            @value.JsonataValue::Json(item),
            lineage,
            parent_frame.bindings,
          ),
        )
      }
    _ =>
      results.push(
        path_frame_with_bindings(
          @value.JsonataValue::Json(json),
          lineage,
          parent_frame.bindings,
        ),
      )
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
/// 通配符访问（所有字段或所有元素），内层数组展平到序列中。
fn access_wildcard(input : @value.JsonataValue) -> @value.JsonataValue {
  match input {
    @value.JsonataValue::Json(Json::Object(map)) => {
      let results : Array[@value.JsonataValue] = []
      for _, v in map {
        push_path_result(results, @value.JsonataValue::Json(v))
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let results : Array[@value.JsonataValue] = []
      for v in arr {
        push_path_result(results, @value.JsonataValue::Json(v))
      }
      @value.JsonataValue::sequence(results)
    }
    @value.JsonataValue::Sequence(arr) => {
      let results : Array[@value.JsonataValue] = []
      for item in arr {
        let r = access_wildcard(item)
        push_path_result(results, r)
      }
      @value.JsonataValue::sequence(results)
    }
    _ => @value.JsonataValue::Undefined
  }
}

///|
fn access_wildcard_frames(
  frame : PathFrame,
  results : Array[PathFrame],
) -> Unit {
  let lineage = prepend_ancestor(frame.value, frame.ancestors)
  match frame.value {
    @value.JsonataValue::Json(Json::Object(map)) =>
      for _, v in map {
        match v {
          Json::Array(arr) =>
            for item in arr {
              results.push(
                path_frame_with_bindings(
                  @value.JsonataValue::Json(item),
                  lineage,
                  frame.bindings,
                ),
              )
            }
          _ =>
            results.push(
              path_frame_with_bindings(
                @value.JsonataValue::Json(v),
                lineage,
                frame.bindings,
              ),
            )
        }
      }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for v in arr {
        results.push(
          path_frame_with_bindings(
            @value.JsonataValue::Json(v),
            frame.ancestors,
            frame.bindings,
          ),
        )
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        access_wildcard_frames(
          path_frame_with_bindings(item, frame.ancestors, frame.bindings),
          results,
        )
      }
    _ => ()
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
fn access_index_frame(
  frame : PathFrame,
  i : Int,
  results : Array[PathFrame],
  grouped~ : Bool,
) -> Unit {
  match frame.value {
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let len = arr.length()
      let idx = if i < 0 { len + i } else { i }
      if idx >= 0 && idx < len {
        let ancestors = if grouped {
          frame.ancestors
        } else {
          prepend_ancestor(frame.value, frame.ancestors)
        }
        results.push(
          path_frame_with_bindings(
            @value.JsonataValue::Json(arr[idx]),
            ancestors,
            frame.bindings,
          ),
        )
      }
    }
    @value.JsonataValue::Sequence(arr) => {
      let len = arr.length()
      let idx = if i < 0 { len + i } else { i }
      if idx >= 0 && idx < len {
        results.push(
          path_frame_with_bindings(arr[idx], frame.ancestors, frame.bindings),
        )
      }
    }
    @value.JsonataValue::Undefined => ()
    _ => results.push(frame)
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
fn access_slice_frame(
  frame : PathFrame,
  start : Int?,
  end : Int?,
  results : Array[PathFrame],
  grouped~ : Bool,
) -> Unit {
  match frame.value {
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let len = arr.length()
      let s = start.unwrap_or(0)
      let e = end.unwrap_or(len)
      let ancestors = if grouped {
        frame.ancestors
      } else {
        prepend_ancestor(frame.value, frame.ancestors)
      }
      for i in s..<e.max(0).min(len) {
        results.push(
          path_frame_with_bindings(
            @value.JsonataValue::Json(arr[i]),
            ancestors,
            frame.bindings,
          ),
        )
      }
    }
    @value.JsonataValue::Sequence(arr) => {
      let len = arr.length()
      let s = start.unwrap_or(0)
      let e = end.unwrap_or(len)
      for i in s..<e.max(0).min(len) {
        results.push(
          path_frame_with_bindings(arr[i], frame.ancestors, frame.bindings),
        )
      }
    }
    _ => ()
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
        match filter_index_match(r, i, items.length()) {
          Some(true) => results.push(item)
          Some(false) => continue
          None => results.push(item)
        }
    }
  }
  match results.length() {
    0 => @value.JsonataValue::Undefined
    _ => @value.JsonataValue::Sequence(results)
  }
}

///|
/// 分组感知的谓词过滤：对 Sequence 中每个元素（预期为数组）独立应用 filter，
/// 保留数组结构以便后续 Index/Slice 步逐元素操作。
fn access_filter_grouped(
  input : @value.JsonataValue,
  expr : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let items = input.to_array()
  let results : Array[@value.JsonataValue] = []
  for item in items {
    let r = access_filter(item, expr, ctx)
    match r {
      @value.JsonataValue::Undefined => continue
      _ => results.push(r)
    }
  }
  @value.JsonataValue::sequence(results)
}

///|
fn access_filter_frames(
  frames : Array[PathFrame],
  expr : @ast.Ast,
  ctx : @value.EvalContext,
  results : Array[PathFrame],
) -> Unit raise @error.JsonataError {
  let pos_var : String? = match ctx.lookup("__pos__") {
    Some(@value.JsonataValue::Json(Json::String(name))) => Some(name)
    _ => None
  }
  for i, frame in frames {
    let r = ctx.with_lineage(current=frame.value, ancestors=frame.ancestors, fn() -> @value.JsonataValue raise @error.JsonataError {
      with_frame_bindings(ctx, frame.bindings, fn() -> @value.JsonataValue raise @error.JsonataError {
        ctx.bind("#", @value.JsonataValue::Json(Json::number(i.to_double())))
        match pos_var {
          Some(name) =>
            ctx.bind(
              name,
              @value.JsonataValue::Json(Json::number(i.to_double())),
            )
          None => ()
        }
        ctx.with_depth(() => eval(expr, ctx))
      })
    })
    match r {
      @value.JsonataValue::Json(Json::True) => results.push(frame)
      @value.JsonataValue::Json(Json::False) => continue
      @value.JsonataValue::Undefined => continue
      _ =>
        match filter_index_match(r, i, frames.length()) {
          Some(true) => results.push(frame)
          Some(false) => continue
          None => results.push(frame)
        }
    }
  }
}

///|
fn filter_index_match(
  value : @value.JsonataValue,
  index : Int,
  length : Int,
) -> Bool? {
  match value {
    @value.JsonataValue::Json(Json::Number(n, ..)) =>
      Some(normalize_index(n.to_int(), length) == index)
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let mut matched = false
      for item in arr {
        match item {
          Json::Number(n, ..) =>
            if normalize_index(n.to_int(), length) == index {
              matched = true
            }
          _ => return None
        }
      }
      Some(matched)
    }
    @value.JsonataValue::Sequence(arr) => {
      let mut matched = false
      for item in arr {
        match filter_index_match(item, index, length) {
          Some(true) => matched = true
          Some(false) => ()
          None => return None
        }
      }
      Some(matched)
    }
    _ => None
  }
}

///|
fn normalize_index(index : Int, length : Int) -> Int {
  if index < 0 {
    length + index
  } else {
    index
  }
}

///|
/// 空数组选择器 `[]`：在路径求值中作为 no-op 标记，阻止最终值的单例提升。
/// 实际数组包裹由 `eval_path` 在路径末尾根据 `has_arrayify` 标志完成。
fn access_arrayify(input : @value.JsonataValue) -> @value.JsonataValue {
  input
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
fn access_map_frames(
  frames : Array[PathFrame],
  expr : @ast.Ast,
  ctx : @value.EvalContext,
  results : Array[PathFrame],
) -> Unit raise @error.JsonataError {
  let top_is_construct = expr is @ast.Ast::Construct(_)
  let pos_var : String? = match ctx.lookup("__pos__") {
    Some(@value.JsonataValue::Json(Json::String(name))) => Some(name)
    _ => None
  }
  for i, frame in frames {
    let r = ctx.with_lineage(current=frame.value, ancestors=frame.ancestors, fn() -> @value.JsonataValue raise @error.JsonataError {
      with_frame_bindings(ctx, frame.bindings, fn() -> @value.JsonataValue raise @error.JsonataError {
        match pos_var {
          Some(name) =>
            ctx.bind(
              name,
              @value.JsonataValue::Json(Json::number(i.to_double())),
            )
          None => ()
        }
        ctx.with_depth(() => eval(expr, ctx))
      })
    })
    match r {
      @value.JsonataValue::Undefined => continue
      @value.JsonataValue::Sequence(arr) =>
        for v in arr {
          for
            out in value_to_frames_with_bindings(
              v,
              frame.value,
              frame.ancestors,
              frame.bindings,
            ) {
            results.push(out)
          }
        }
      @value.JsonataValue::Json(Json::Array(arr)) =>
        if top_is_construct {
          results.push(
            path_frame_with_bindings(r, frame.ancestors, frame.bindings),
          )
        } else {
          for v in arr {
            results.push(
              path_frame_with_bindings(
                @value.JsonataValue::Json(v),
                frame.ancestors,
                frame.bindings,
              ),
            )
          }
        }
      _ =>
        results.push(
          path_frame_with_bindings(r, frame.ancestors, frame.bindings),
        )
    }
  }
}

///|
/// 分组聚合 `{...}`（无前置 `.`）：对输入中每项求值 key-expression，
/// 按 key 分组合并输入项，再对每组求值 value-expression（匹配 JSONata-js
/// `evaluateGroupExpression` 语义）。
fn access_group_aggregate(
  input : @value.JsonataValue,
  group_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let items = input.to_array()
  let pairs : Array[(@ast.Ast, @ast.Ast)] = match group_ast {
    @ast.Ast::Group(p) => p
    _ => return @value.JsonataValue::Json(Json::object({}))
  }
  if items.length() == 0 {
    return @value.JsonataValue::Json(Json::object({}))
  }
  // 第 1 阶段：按 key 分组，每组的输入项收集为原始数组
  let groups : Map[String, Array[@value.JsonataValue]] = {}
  for item in items {
    // 对每组 key/value pair 求值 key
    for kv in pairs {
      let (key_ast, _val_ast) = kv
      let key_val = ctx.with_context(current=item, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
        ctx.with_depth(() => eval(key_ast, ctx))
      })
      let key_str = match key_val {
        @value.JsonataValue::Json(Json::String(s)) => s
        _ => to_str(key_val)
      }
      match groups.get(key_str) {
        Some(arr) => arr.push(item)
        None => groups.set(key_str, [item])
      }
    }
  }
  // 第 2 阶段：对每组求值 value-expression，合并结果
  let merged : Map[String, Array[Json]] = {}
  for key_str, group_items in groups {
    let group_input = @value.JsonataValue::sequence(group_items)
    for kv in pairs {
      let (key_ast, val_ast) = kv
      // 验证 key 匹配当前组
      let sample_key = ctx.with_context(current=group_items[0], parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
        ctx.with_depth(() => eval(key_ast, ctx))
      })
      let actual_key = match sample_key {
        @value.JsonataValue::Json(Json::String(s)) => s
        _ => to_str(sample_key)
      }
      if actual_key != key_str {
        continue
      }
      let val = ctx.with_context(current=group_input, parent=input, fn() -> @value.JsonataValue raise @error.JsonataError {
        ctx.with_depth(() => eval(val_ast, ctx))
      })
      let json_val = json_for_constructor(val)
      match merged.get(key_str) {
        Some(values) => values.push(json_val)
        None => merged.set(key_str, [json_val])
      }
    }
  }
  // 将合并结果转为最终对象。
  let out : Map[String, Json] = {}
  for name, values in merged {
    out[name] = json_for_merged_values(values)
  }
  @value.JsonataValue::Json(Json::object(out))
}

///|
fn access_group_aggregate_frames(
  frames : Array[PathFrame],
  group_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let merged : Map[String, Array[Json]] = {}
  for frame in frames {
    let r = ctx.with_lineage(current=frame.value, ancestors=frame.ancestors, fn() -> @value.JsonataValue raise @error.JsonataError {
      with_frame_bindings(ctx, frame.bindings, fn() -> @value.JsonataValue raise @error.JsonataError {
        ctx.with_depth(() => eval(group_ast, ctx))
      })
    })
    match r {
      @value.JsonataValue::Json(Json::Object(_)) => merge_into_group(r, merged)
      @value.JsonataValue::Undefined => continue
      _ => ()
    }
  }
  let out : Map[String, Json] = {}
  for name, values in merged {
    out[name] = json_for_merged_values(values)
  }
  @value.JsonataValue::Json(Json::object(out))
}
