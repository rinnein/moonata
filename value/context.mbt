///|
/// 默认最大递归深度。
/// 设为 8000：覆盖 case007 的 6555 层互递归；同时较低以保证在 8MB native 栈耗尽前
/// 触发 U1001 拦截无限递归（case005/case006）。
pub let default_max_depth : Int = 8000

///|
/// 默认最大求值步数。
/// 设为 1000000：覆盖复杂表达式求值（如 performance/case001 的 256 项嵌套路径）。
/// 无限尾递归（TCO trampoline）通过 per-trampoline 迭代计数器拦截，
/// 不依赖全局 max_steps。
pub let default_max_steps : Int = 1_000_000

///|
/// 默认最大序列长度。-1 表示不限制。
///
/// 对应 JSONata `guardrails` 文档 `sequence` 选项（默认不开启）。
/// 通过 `EvalOptions::sequence` 显式启用，超限抛 `D2015`。
pub let default_max_sequence : Int = -1

///|
/// 求值上下文：持有根数据、绑定表与递归/步数/序列护栏。
///
/// - `root`：`$` 根数据（不可变，JSONata 中 `$` 始终指原始根）。
/// - `bindings`：变量绑定表（含内建函数），Map 本身可变，字段无需 `mut`。
/// - `depth`/`max_depth`：递归深度护栏。
/// - `steps`/`max_steps`：求值步数护栏。
/// - `max_sequence`：序列长度护栏（-1 不限制），对齐 JSONata `guardrails` `sequence` 选项。
/// - `depth_exceeded_code`/`steps_exceeded_code`/`sequence_exceeded_code`：
///   护栏超限时抛出的错误码。默认 `U1001`/`U1001`/`D2015`，
///   通过 `EvalOptions::stack`/`timeout`/`sequence` 启用时改用 `D1011`/`D1012`/`D2015`
///   对齐 JSONata 官方文档（U1001 仅用于 jsonata-js test runner 的 `timeboxExpression` 兼容路径）。
/// - `current`：`@` 当前项（谓词过滤/路径迭代时绑定）。
/// - `parent`：`$$` 父级上下文。
/// - `ancestors`：当前项的父级链，首项为 `%`，后续项支持 `%.%`。
pub struct EvalContext {
  root : JsonataValue
  mut bindings : Map[String, JsonataValue]
  mut depth : Int
  max_depth : Int
  mut steps : Int
  max_steps : Int
  max_sequence : Int
  depth_exceeded_code : String
  steps_exceeded_code : String
  sequence_exceeded_code : String
  mut current : JsonataValue
  mut parent : JsonataValue
  mut ancestors : Array[JsonataValue]
}

///|
/// 构造上下文（使用默认护栏阈值）。
pub fn EvalContext::new(root : JsonataValue) -> EvalContext {
  {
    root,
    bindings: Map([]),
    depth: 0,
    max_depth: default_max_depth,
    steps: 0,
    max_steps: default_max_steps,
    max_sequence: default_max_sequence,
    depth_exceeded_code: "U1001",
    steps_exceeded_code: "U1001",
    sequence_exceeded_code: "D2015",
    current: root,
    parent: root,
    ancestors: [root],
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
    bindings: Map([]),
    depth: 0,
    max_depth,
    steps: 0,
    max_steps,
    max_sequence: default_max_sequence,
    depth_exceeded_code: "U1001",
    steps_exceeded_code: "U1001",
    sequence_exceeded_code: "D2015",
    current: root,
    parent: root,
    ancestors: [root],
  }
}

///|
/// 构造上下文并指定完整护栏配置（含序列长度与错误码）。
///
/// 用于 `EvalOptions` 启用 JSONata 官方 `guardrails` 语义：
/// - `stack` 对应 `max_depth`，超限抛 `D1011`
/// - `timeout`（毫秒）映射为 `max_steps` 的近似上限（MoonBit 当前无原生 wall-clock
///   超时支持，使用步数上限近似），超限抛 `D1012`
/// - `sequence` 对应 `max_sequence`，超限抛 `D2015`
pub fn EvalContext::new_with_guardrails(
  root : JsonataValue,
  max_depth? : Int = default_max_depth,
  max_steps? : Int = default_max_steps,
  max_sequence? : Int = default_max_sequence,
  depth_exceeded_code? : String = "U1001",
  steps_exceeded_code? : String = "U1001",
  sequence_exceeded_code? : String = "D2015",
) -> EvalContext {
  {
    root,
    bindings: Map([]),
    depth: 0,
    max_depth,
    steps: 0,
    max_steps,
    max_sequence,
    depth_exceeded_code,
    steps_exceeded_code,
    sequence_exceeded_code,
    current: root,
    parent: root,
    ancestors: [root],
  }
}

///|
/// 复制求值上下文，保留当前项、父级、护栏计数与已有绑定。
pub fn EvalContext::capture(self : EvalContext) -> EvalContext {
  let bindings : Map[String, JsonataValue] = Map([])
  for name, value in self.bindings {
    bindings[name] = value
  }
  {
    root: self.root,
    bindings,
    depth: self.depth,
    max_depth: self.max_depth,
    steps: self.steps,
    max_steps: self.max_steps,
    max_sequence: self.max_sequence,
    depth_exceeded_code: self.depth_exceeded_code,
    steps_exceeded_code: self.steps_exceeded_code,
    sequence_exceeded_code: self.sequence_exceeded_code,
    current: self.current,
    parent: self.parent,
    ancestors: self.ancestors.copy(),
  }
}

///|
/// 从另一个上下文补齐当前尚未捕获的绑定。
pub fn EvalContext::inherit_missing_bindings_from(
  self : EvalContext,
  other : EvalContext,
) -> Unit {
  for name, value in other.bindings {
    if self.bindings.get(name) is None {
      self.bindings[name] = value
    }
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
  match self.ancestors {
    [first, ..] => first
    [] => self.parent
  }
}

///|
/// 获取父级链副本。
pub fn EvalContext::ancestors(self : EvalContext) -> Array[JsonataValue] {
  self.ancestors.copy()
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
  self.ancestors = [v]
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
  let old_ancestors = self.ancestors
  self.current = current
  self.parent = parent
  let next_ancestors : Array[JsonataValue] = [parent]
  for ancestor in old_ancestors {
    next_ancestors.push(ancestor)
  }
  self.ancestors = next_ancestors
  try {
    let r = f()
    self.current = old_current
    self.parent = old_parent
    self.ancestors = old_ancestors
    r
  } catch {
    e => {
      self.current = old_current
      self.parent = old_parent
      self.ancestors = old_ancestors
      raise e
    }
  }
}

///|
/// 在指定当前项与完整父级链下执行函数，自动恢复。
pub fn[T] EvalContext::with_lineage(
  self : EvalContext,
  current~ : JsonataValue,
  ancestors~ : Array[JsonataValue],
  f : () -> T raise @error.JsonataError,
) -> T raise @error.JsonataError {
  let old_current = self.current
  let old_parent = self.parent
  let old_ancestors = self.ancestors
  self.current = current
  self.ancestors = ancestors.copy()
  self.parent = match self.ancestors {
    [first, ..] => first
    [] => JsonataValue::Undefined
  }
  try {
    let r = f()
    self.current = old_current
    self.parent = old_parent
    self.ancestors = old_ancestors
    r
  } catch {
    e => {
      self.current = old_current
      self.parent = old_parent
      self.ancestors = old_ancestors
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
/// 在局部变量绑定下执行函数，结束后恢复旧绑定。
pub fn[T] EvalContext::with_binding(
  self : EvalContext,
  name : String,
  value : JsonataValue,
  f : () -> T raise @error.JsonataError,
) -> T raise @error.JsonataError {
  let old = self.bindings.get(name)
  self.bindings[name] = value
  try {
    let r = f()
    restore_binding(self.bindings, name, old)
    r
  } catch {
    e => {
      restore_binding(self.bindings, name, old)
      raise e
    }
  }
}

///|
fn restore_binding(
  bindings : Map[String, JsonataValue],
  name : String,
  old : JsonataValue?,
) -> Unit {
  match old {
    Some(v) => bindings[name] = v
    None => ignore(bindings.remove(name))
  }
}

///|
/// 查找绑定，未找到返回 None。
pub fn EvalContext::lookup(self : EvalContext, name : String) -> JsonataValue? {
  self.bindings.get(name)
}

///|
/// 获取绑定的不可变快照（用于块级作用域保存/恢复）。
pub fn EvalContext::bindings_snapshot(
  self : EvalContext,
) -> Map[String, JsonataValue] {
  let copy : Map[String, JsonataValue] = Map([])
  for name, value in self.bindings {
    copy[name] = value
  }
  copy
}

///|
/// 恢复绑定的快照（用于块级作用域退出时）。
pub fn EvalContext::restore_bindings(
  self : EvalContext,
  snapshot : Map[String, JsonataValue],
) -> Unit {
  let new_map : Map[String, JsonataValue] = Map([])
  for name, value in snapshot {
    new_map[name] = value
  }
  self.bindings = new_map
}

///|
/// 进入递归层（护栏：超限抛 GuardrailError）。
///
/// 错误码：
/// - 默认 `U1001`（对齐 jsonata-js test runner `timeboxExpression` 语义，
///   用于 `evaluate_with_max_depth` 等 legacy 路径）
/// - 通过 `EvalOptions::stack` 启用时改用 `D1011`（对齐 JSONata `guardrails` 文档）
pub fn EvalContext::enter(self : EvalContext) -> Unit raise @error.JsonataError {
  self.depth = self.depth + 1
  if self.depth > self.max_depth {
    raise @error.guardrail_error(
      "\{self.depth_exceeded_code}: Stack overflow error: Check for non-terminating recursive function.  Consider rewriting as tail-recursive. (depth=\{self.depth}, max_depth=\{self.max_depth})",
      limit=Some("max_depth=\{self.max_depth}"),
      code=Some(self.depth_exceeded_code),
    )
  }
}

///|
/// 同步 caller 的递归深度到当前上下文（用于 Lambda invoke 跨上下文传播深度计数）。
/// Lambda 闭包捕获定义时的 depth，invoke 时若不与 caller 同步会导致护栏失效。
pub fn EvalContext::sync_depth_from(
  self : EvalContext,
  other : EvalContext,
) -> Unit {
  self.depth = other.depth
}

///|
/// 退出递归层。
pub fn EvalContext::exit(self : EvalContext) -> Unit {
  self.depth = self.depth - 1
}

///|
/// 记录一步求值（护栏：超限抛 GuardrailError）。
///
/// 错误码：
/// - 默认 `U1001`（对齐 jsonata-js test runner 的 `timeboxExpression` 超时语义，
///   使无限尾递归（如 `tail-recursion/case006`）在 TCO trampoline 下也能被拦截）
/// - 通过 `EvalOptions::timeout` 启用时改用 `D1012`（对齐 JSONata `guardrails` 文档）
pub fn EvalContext::tick(self : EvalContext) -> Unit raise @error.JsonataError {
  self.steps = self.steps + 1
  if self.steps > self.max_steps {
    raise @error.guardrail_error(
      "\{self.steps_exceeded_code}: Stack overflow error: Check for non-terminating recursive function.  Consider rewriting as tail-recursive. (steps=\{self.steps}, max_steps=\{self.max_steps})",
      limit=Some("max_steps=\{self.max_steps}"),
      code=Some(self.steps_exceeded_code),
    )
  }
}

///|
/// 检查序列长度是否超限（护栏：超限抛 GuardrailError，错误码 `D2015`）。
///
/// 对齐 JSONata `guardrails` 文档 `sequence` 选项：
/// > The `sequence` option can be set to specify the maximum sequence length
/// > that can be created by an expression, including any intermediate sequences
/// > created by sub-expressions. Error `D2015` will be thrown if, during the
/// > evaluation of an expression, the evaluator attempts to generate a sequence
/// > exceeding this upper limit.
///
/// 当 `max_sequence <= 0` 时不限制（默认行为）。
pub fn EvalContext::check_sequence_length(
  self : EvalContext,
  length : Int,
) -> Unit raise @error.JsonataError {
  if self.max_sequence > 0 && length > self.max_sequence {
    raise @error.guardrail_error(
      "\{self.sequence_exceeded_code}: The maximum sequence length of \{self.max_sequence} has been exceeded: \{length}",
      limit=Some("max_sequence=\{self.max_sequence}"),
      code=Some(self.sequence_exceeded_code),
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
