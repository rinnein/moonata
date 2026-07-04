///|
/// JSONata AST 节点：单一 enum + 标签字段。
///
/// 所有节点统一为 `Ast` enum，子结构 `Step`/`SortTerm` 独立定义。
/// 路径访问统一用 `Path(Array[Step])` 表示，`Step` 携带 `StepKind` 与 `StepStage`。
pub(all) enum Ast {
  String(String)
  Regex(pattern~ : String, flags~ : String)
  Number(Double)
  Boolean(Bool)
  Null
  Placeholder
  Path(Array[Step])
  Binary(op~ : String, lhs~ : Ast, rhs~ : Ast)
  Unary(op~ : String, expr~ : Ast)
  Conditional(condition~ : Ast, consequent~ : Ast, alternate~ : Ast?)
  Construct(Array[Ast])
  Group(Array[(Ast, Ast)])
  Sort(expr~ : Ast, terms~ : Array[SortTerm])
  Lambda(params~ : Array[String], body~ : Ast, signature~ : String?)
  Var(String)
  Bind(name~ : String, value~ : Ast, body~ : Ast)
  Apply(func~ : Ast, args~ : Array[Ast])
  Chain(Array[Ast])
  Block(Array[Ast])
} derive(Debug, Eq)

///|
/// 路径步：由种类与阶段（单层/递归）组成。
/// `focus` 与 `tuple` 由 `@ $var` 标注：focus 绑定变量名，tuple 标记进入 tuple stream 模式。
/// `index` 仅在 stage=Recursive 时有效：表示 `**.X[idx]` 需对每个匹配项单独索引。
pub(all) struct Step {
  kind : StepKind
  stage : StepStage
  focus : String?
  tuple : Bool
  index : Int?
} derive(Debug, Eq)

///|
/// 路径步种类。
pub(all) enum StepKind {
  Name(String)
  Wildcard
  Index(Int)
  Slice(Int?, Int?)
  Eval(Ast)
  Filter(Ast)
  Map(Ast)
  GroupAggregate(Ast)
  Arrayify
} derive(Debug, Eq)

///|
/// 路径步阶段：单层访问或递归降序（`**`）。
pub(all) enum StepStage {
  Single
  Recursive
} derive(Debug, Eq)

///|
/// 排序项：表达式 + 升降序标记。
pub(all) struct SortTerm {
  expr : Ast
  descending : Bool
} derive(Debug, Eq)

///|
/// 构造路径步。
pub fn Step::new(
  kind~ : StepKind,
  stage~ : StepStage,
  focus? : String? = None,
  tuple? : Bool = false,
  index? : Int? = None,
) -> Step {
  { kind, stage, focus, tuple, index }
}

///|
/// 构造排序项（默认升序）。
pub fn SortTerm::new(expr : Ast, descending? : Bool = false) -> SortTerm {
  { expr, descending }
}

///|
/// 便捷构造单步路径。
pub fn Ast::path1(step : Step) -> Ast {
  Path([step])
}

///|
/// 便捷构造名称步。
pub fn name_step(name : String, recursive? : Bool = false) -> Step {
  Step::new(
    kind=StepKind::Name(name),
    stage=if recursive { StepStage::Recursive } else { StepStage::Single },
  )
}

///|
/// 便捷构造通配符步。
pub fn wildcard_step(recursive? : Bool = false) -> Step {
  Step::new(
    kind=StepKind::Wildcard,
    stage=if recursive { StepStage::Recursive } else { StepStage::Single },
  )
}

///|
/// 便捷构造路径基值求值步。
pub fn eval_step(expr : Ast) -> Step {
  Step::new(kind=StepKind::Eval(expr), stage=StepStage::Single)
}

///|
/// 便捷构造路径映射步 `.(expr)`。
pub fn map_step(expr : Ast) -> Step {
  Step::new(kind=StepKind::Map(expr), stage=StepStage::Single)
}

///|
/// 便捷构造空数组选择器 `[]`。
pub fn arrayify_step() -> Step {
  Step::new(kind=StepKind::Arrayify, stage=StepStage::Single)
}
