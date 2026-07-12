///|
/// 注册所有内建函数到上下文。
pub fn register_builtins(ctx : @value.EvalContext) -> Unit {
  // 字符串函数
  register_string_functions(ctx)
  // 数值函数
  register_numeric_functions(ctx)
  // 聚合/数组函数
  register_array_functions(ctx)
  // 对象函数
  register_object_functions(ctx)
  // 类型转换函数
  register_type_functions(ctx)
  // 高阶函数
  register_higher_order_functions(ctx)
  // 正则相关函数
  register_regex_functions(ctx)
  // 特殊函数
  register_special_functions(ctx)
}

///|
/// 注册函数辅助
///
/// `contextual` 默认为 `true`，表示当用户提供的参数少于 `arity` 时，
/// 由 `apply_context_argument` 将当前上下文值前置为第一个参数（旧有行为，
/// 适用于 `$sum()` 等需要从上下文取首参的聚合函数）。
///
/// 设为 `false` 时，由 `validate_args` 通过签名中的 `-` 修饰符自行处理上下文
/// 替换（适用于 JSONata 签名 `<s-...>` 的函数，如 `$substringBefore`/`$substringAfter`，
/// 这样能在上下文类型不匹配时抛出 T0411 而非 T0410）。
fn register(
  ctx : @value.EvalContext,
  name : String,
  arity~ : Int,
  signature? : String? = None,
  contextual? : Bool = true,
  invoke~ : (Array[@value.JsonataValue], @value.EvalContext) -> @value.JsonataValue raise @error.JsonataError,
) -> Unit {
  ctx.bind(
    name,
    @value.JsonataValue::Func(
      @value.JsonataFunc::new(arity~, signature~, contextual~, invoke~),
    ),
  )
}
