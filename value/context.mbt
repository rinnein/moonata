///|
/// 默认最大递归深度。
let default_max_depth : Int = 1000

///|
/// 默认最大求值步数。
let default_max_steps : Int = 1_000_000

///|
/// 求值上下文：持有根数据、绑定表与递归/步数护栏。
///
/// - `root`：`$` 根数据（不可变，JSONata 中 `$` 始终指原始根）。
/// - `bindings`：变量绑定表（含内建函数），Map 本身可变，字段无需 `mut`。
/// - `depth`/`max_depth`：递归深度护栏。
/// - `steps`/`max_steps`：求值步数护栏。
/// - `current`：`@` 当前项（谓词过滤/路径迭代时绑定）。
/// - `parent`：`$$` 父级上下文。
pub struct EvalContext {
  root : JsonataValue
  bindings : Map[String, JsonataValue]
  mut depth : Int
  max_depth : Int
  mut steps : Int
  max_steps : Int
  mut current : JsonataValue
  mut parent : JsonataValue
}

///|
/// 构造上下文（使用默认护栏阈值）。
pub fn EvalContext::new(root : JsonataValue) -> EvalContext {
  {
    root,
    bindings: {},
    depth: 0,
    max_depth: default_max_depth,
    steps: 0,
    max_steps: default_max_steps,
    current: root,
    parent: root,
  }
}

///|
/// 构造上下文并指定护栏阈值。
pub fn EvalContext::new_with_limits(
  root : JsonataValue,
  max_depth? : Int = default_max_depth,
  max_steps? : Int = default_max_steps,
) -> EvalContext {
  {
    root,
    bindings: {},
    depth: 0,
    max_depth,
    steps: 0,
    max_steps,
    current: root,
    parent: root,
  }
}

///|
/// 获取根数据（`$`）。
pub fn EvalContext::root(self : EvalContext) -> JsonataValue {
  self.root
}

///|
/// 获取当前项（`@`）。
pub fn EvalContext::current(self : EvalContext) -> JsonataValue {
  self.current
}

///|
/// 获取父级上下文（`$$`）。
pub fn EvalContext::parent(self : EvalContext) -> JsonataValue {
  self.parent
}

///|
/// 设置当前项（`@`），返回旧值以便恢复。
pub fn EvalContext::set_current(
  self : EvalContext,
  v : JsonataValue,
) -> JsonataValue {
  let old = self.current
  self.current = v
  old
}

///|
/// 设置父级上下文（`$$`），返回旧值以便恢复。
pub fn EvalContext::set_parent(
  self : EvalContext,
  v : JsonataValue,
) -> JsonataValue {
  let old = self.parent
  self.parent = v
  old
}

///|
/// 在指定当前项与父级下执行函数，自动恢复（含异常路径）。
pub fn[T] EvalContext::with_context(
  self : EvalContext,
  current~ : JsonataValue,
  parent~ : JsonataValue,
  f : () -> T raise @error.JsonataError,
) -> T raise @error.JsonataError {
  let old_current = self.current
  let old_parent = self.parent
  self.current = current
  self.parent = parent
  try {
    let r = f()
    self.current = old_current
    self.parent = old_parent
    r
  } catch {
    e => {
      self.current = old_current
      self.parent = old_parent
      raise e
    }
  }
}

///|
/// 绑定变量。
pub fn EvalContext::bind(
  self : EvalContext,
  name : String,
  value : JsonataValue,
) -> Unit {
  self.bindings[name] = value
}

///|
/// 查找绑定，未找到返回 None。
pub fn EvalContext::lookup(self : EvalContext, name : String) -> JsonataValue? {
  self.bindings.get(name)
}

///|
/// 进入递归层（护栏：超限抛 GuardrailError）。
pub fn EvalContext::enter(self : EvalContext) -> Unit raise @error.JsonataError {
  self.depth = self.depth + 1
  if self.depth > self.max_depth {
    raise @error.guardrail_error(
      "递归深度超限 (depth=\{self.depth})",
      limit=Some("max_depth=\{self.max_depth}"),
    )
  }
}

///|
/// 退出递归层。
pub fn EvalContext::exit(self : EvalContext) -> Unit {
  self.depth = self.depth - 1
}

///|
/// 记录一步求值（护栏：超限抛 GuardrailError）。
pub fn EvalContext::tick(self : EvalContext) -> Unit raise @error.JsonataError {
  self.steps = self.steps + 1
  if self.steps > self.max_steps {
    raise @error.guardrail_error(
      "求值步数超限 (steps=\{self.steps})",
      limit=Some("max_steps=\{self.max_steps}"),
    )
  }
}

///|
/// 在递归层内执行函数，自动 enter/exit（含异常路径）。
pub fn[T] EvalContext::with_depth(
  self : EvalContext,
  f : () -> T raise @error.JsonataError,
) -> T raise @error.JsonataError {
  self.enter()
  try {
    let r = f()
    self.exit()
    r
  } catch {
    e => {
      self.exit()
      raise e
    }
  }
}
