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
fn register(
  ctx : @value.EvalContext,
  name : String,
  arity~ : Int,
  signature? : String? = None,
  invoke~ : (Array[@value.JsonataValue], @value.EvalContext) -> @value.JsonataValue raise @error.JsonataError,
) -> Unit {
  ctx.bind(
    name,
    @value.JsonataValue::Func(
      @value.JsonataFunc::new(arity~, signature~, invoke~),
    ),
  )
}
