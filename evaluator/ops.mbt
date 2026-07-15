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
  // 例外：
  // - `..`（range）需要先校验非 undefined 边界的类型（T2003/T2004）
  // - 比较运算（`<`/`<=`/`>`/`>=`）需要先校验 T2010
  // - 算术运算（`+`/`-`/`*`/`/`/`%`）需要先校验 T2001/T2002
  // 这些运算在各自的函数内处理 undefined 传播
  let excluded = op == ".." ||
    op == "<" ||
    op == "<=" ||
    op == ">" ||
    op == ">=" ||
    op == "+" ||
    op == "-" ||
    op == "*" ||
    op == "/" ||
    op == "%"
  if !excluded {
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
  }
  match op {
    "+" => arith_op(lhs, rhs, "+")
    "-" => arith_op(lhs, rhs, "-")
    "*" => arith_op(lhs, rhs, "*")
    "/" => arith_op(lhs, rhs, "/")
    "%" => arith_op(lhs, rhs, "%")
    ".." => range_op(lhs, rhs, ctx)
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
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  // T2003: The left side of the range operator (..) must evaluate to an integer
  // T2004: The right side of the range operator (..) must evaluate to an integer
  // JSONata 语义：先检查非 undefined 边界是否为整数，再处理 undefined 传播。
  // 即 [$x..true] 中 $x 为 undefined，但 true 非 integer → 抛 T2004。
  // lhs 非 undefined 时检查是否为 integer
  if not(lhs is @value.JsonataValue::Undefined) {
    let _ = match lhs {
      @value.JsonataValue::Json(Json::Number(n, ..)) => n
      @value.JsonataValue::Sequence(arr) if arr.length() == 1 =>
        match arr[0] {
          @value.JsonataValue::Json(Json::Number(n, ..)) => n
          _ =>
            raise @error.type_error(
              "T2003: The left side of the range operator (..) must evaluate to an integer",
              expected=Some("integer"),
              actual=None,
              code=Some("T2003"),
            )
        }
      _ =>
        raise @error.type_error(
          "T2003: The left side of the range operator (..) must evaluate to an integer",
          expected=Some("integer"),
          actual=None,
          code=Some("T2003"),
        )
    }
  }
  // rhs 非 undefined 时检查是否为 integer
  if not(rhs is @value.JsonataValue::Undefined) {
    let _ = match rhs {
      @value.JsonataValue::Json(Json::Number(n, ..)) => n
      @value.JsonataValue::Sequence(arr) if arr.length() == 1 =>
        match arr[0] {
          @value.JsonataValue::Json(Json::Number(n, ..)) => n
          _ =>
            raise @error.type_error(
              "T2004: The right side of the range operator (..) must evaluate to an integer",
              expected=Some("integer"),
              actual=None,
              code=Some("T2004"),
            )
        }
      _ =>
        raise @error.type_error(
          "T2004: The right side of the range operator (..) must evaluate to an integer",
          expected=Some("integer"),
          actual=None,
          code=Some("T2004"),
        )
    }
  }
  // undefined 边界 → 结果为 undefined
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    return @value.JsonataValue::Undefined
  }
  // 此时两侧均为 Number；提取值
  let start_d = match lhs {
    @value.JsonataValue::Json(Json::Number(n, ..)) => n
    _ => abort("unreachable: lhs validated above")
  }
  let end_d = match rhs {
    @value.JsonataValue::Json(Json::Number(n, ..)) => n
    _ => abort("unreachable: rhs validated above")
  }
  let start = start_d.to_int()
  let end = end_d.to_int()
  // JSONata: range bounds must be integers
  if start_d != start.to_double() {
    raise @error.type_error(
      "T2003: The left side of the range operator (..) must evaluate to an integer",
      expected=Some("integer"),
      actual=None,
      code=Some("T2003"),
    )
  }
  if end_d != end.to_double() {
    raise @error.type_error(
      "T2004: The right side of the range operator (..) must evaluate to an integer",
      expected=Some("integer"),
      actual=None,
      code=Some("T2004"),
    )
  }
  // D2014: The size of the sequence allocated by the range operator (..)
  // must not exceed 1e7
  let size = if start <= end { end - start + 1 } else { 0 }
  if size > 10000000 {
    raise @error.runtime_error(
      "D2014: The size of the sequence allocated by the range operator (..) must not exceed 1e7. Attempted to allocate \{size}.",
      code=Some("D2014"),
    )
  }
  let items : Array[@value.JsonataValue] = []
  if start <= end {
    for i in start..<=end {
      items.push(@value.JsonataValue::Json(Json::number(i.to_double())))
    }
  }
  // 序列长度护栏：range 是单次构造最大序列的操作，需在返回前检查
  ctx.check_sequence_length(items.length())
  @value.JsonataValue::Sequence(items)
}

///|
/// 算术运算
fn arith_op(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
  op : String,
) -> @value.JsonataValue raise @error.JsonataError {
  // T2001: 左侧非 undefined 时必须是数字
  if !lhs.is_undefined() {
    let _ = to_number_with_code(lhs, "left", op~)
  }
  // T2002: 右侧非 undefined 时必须是数字
  if !rhs.is_undefined() {
    let _ = to_number_with_code(rhs, "right", op~)
  }
  // undefined 传播：任一为 undefined → 结果为 undefined
  if lhs.is_undefined() || rhs.is_undefined() {
    return @value.JsonataValue::Undefined
  }
  let l = to_number_with_code(lhs, "left", op~)
  let r = to_number_with_code(rhs, "right", op~)
  // 除法特殊处理：除以零返回 Infinity/NaN（对齐 JSONata-js）
  if op == "/" {
    if r == 0.0 {
      if l == 0.0 {
        return @value.JsonataValue::Json(Json::number(@double.not_a_number)) // NaN
      } else if l > 0.0 {
        return @value.JsonataValue::Json(Json::number(@double.infinity))
      } else {
        return @value.JsonataValue::Json(Json::number(@double.neg_infinity))
      }
    }
    return @value.JsonataValue::Json(Json::number(l / r))
  }
  let result = match op {
    "+" => l + r
    "-" => l - r
    "*" => l * r
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
      let result : Map[String, Json] = Map([])
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
/// 判断值是否为可比较类型（undefined、string、number）。
/// 对齐 JSONata-js `evaluateComparisonExpression` 的 lcomparable/rcomparable 检查。
fn is_comparable_value(v : @value.JsonataValue) -> Bool {
  match v {
    @value.JsonataValue::Undefined => true
    @value.JsonataValue::Json(Json::String(_)) => true
    @value.JsonataValue::Json(Json::Number(_)) => true
    _ => false
  }
}

///|
/// 比较运算通用入口：先检查 T2010（不可比较类型），再处理 undefined 传播，
/// 再检查 T2009（类型不匹配），最后执行比较。
fn compare_op(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
  op : String,
) -> @value.JsonataValue raise @error.JsonataError {
  // 对齐 jsonata-js evaluateComparisonExpression：单元素序列先提升为标量
  let lhs = lhs.lift_singleton()
  let rhs = rhs.lift_singleton()
  // T2010: 两边都必须是可比较类型（undefined/string/number）
  if !is_comparable_value(lhs) || !is_comparable_value(rhs) {
    raise @error.runtime_error(
      "T2010: The expressions either side of operator \{op} must evaluate to numeric or string values",
      code=Some("T2010"),
    )
  }
  // undefined 传播：任一为 undefined → 结果为 undefined
  if lhs is @value.JsonataValue::Undefined ||
    rhs is @value.JsonataValue::Undefined {
    return @value.JsonataValue::Undefined
  }
  // T2009: 两边必须同类型（都是 string 或都是 number）
  let l_is_str = is_string_value(lhs)
  let r_is_str = is_string_value(rhs)
  if l_is_str != r_is_str {
    raise @error.runtime_error(
      "T2009: The values either side of operator \{op} must be of the same data type",
      code=Some("T2009"),
    )
  }
  // 执行比较
  if l_is_str {
    // 字符串比较（使用字节序比较规避 MoonBit String collation bug）
    let l = to_str(lhs)
    let r = to_str(rhs)
    let result = match op {
      "<" => str_lt(l, r)
      "<=" => str_lte(l, r)
      ">" => str_gt(l, r)
      ">=" => str_gte(l, r)
      _ => abort("unreachable: unknown comparison op")
    }
    @value.JsonataValue::Json(Json::boolean(result))
  } else {
    // 数字比较
    let l = to_number(lhs)
    let r = to_number(rhs)
    let result = match op {
      "<" => l < r
      "<=" => l <= r
      ">" => l > r
      ">=" => l >= r
      _ => abort("unreachable: unknown comparison op")
    }
    @value.JsonataValue::Json(Json::boolean(result))
  }
}

///|
/// 比较：小于
fn compare_lt(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  compare_op(lhs, rhs, "<")
}

///|
/// 比较：小于等于
fn compare_lte(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  compare_op(lhs, rhs, "<=")
}

///|
/// 比较：大于
fn compare_gt(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  compare_op(lhs, rhs, ">")
}

///|
/// 比较：大于等于
fn compare_gte(
  lhs : @value.JsonataValue,
  rhs : @value.JsonataValue,
) -> @value.JsonataValue raise @error.JsonataError {
  compare_op(lhs, rhs, ">=")
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
      // D1002: Cannot negate a non-numeric value
      let n = match v {
        @value.JsonataValue::Json(Json::Number(n, ..)) => n
        @value.JsonataValue::Json(Json::String(s)) =>
          @strconv.from_str(s) catch {
            _ =>
              raise @error.type_error(
                "无法转为数字: \{s}",
                expected=Some("number"),
                actual=Some("string"),
                code=Some("D1002"),
              )
          }
        @value.JsonataValue::Json(Json::True) => 1.0
        @value.JsonataValue::Json(Json::False) => 0.0
        @value.JsonataValue::Sequence(_) => {
          // 单元素序列提升后递归处理
          let lifted = v.lift_singleton()
          match lifted {
            @value.JsonataValue::Json(Json::Number(n, ..)) => n
            _ =>
              raise @error.type_error(
                "无法转为数字",
                expected=Some("number"),
                actual=None,
                code=Some("D1002"),
              )
          }
        }
        _ =>
          raise @error.type_error(
            "无法转为数字",
            expected=Some("number"),
            actual=None,
            code=Some("D1002"),
          )
      }
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
  // First pass: check if any element is a non-JSON value (Func, Regex)
  // If so, use Sequence to preserve them
  let mut has_non_json = false
  let evaluated : Array[@value.JsonataValue] = []
  for item in items {
    let v = eval(item, ctx)
    match v {
      @value.JsonataValue::Undefined => continue
      @value.JsonataValue::Func(_) | @value.JsonataValue::Regex(_) => {
        has_non_json = true
        evaluated.push(v)
      }
      @value.JsonataValue::Sequence(arr) =>
        for elem in arr {
          match elem {
            @value.JsonataValue::Undefined => ()
            @value.JsonataValue::Func(_) | @value.JsonataValue::Regex(_) => {
              has_non_json = true
              evaluated.push(elem)
            }
            _ => evaluated.push(elem)
          }
        }
      @value.JsonataValue::Json(Json::Array(arr)) =>
        if item is @ast.Ast::Construct(_) {
          // Nested explicit array constructor - preserve as single element
          evaluated.push(@value.JsonataValue::Json(Json::array(arr)))
        } else {
          // Flatten non-constructor arrays
          for value in arr {
            evaluated.push(@value.JsonataValue::Json(value))
          }
        }
      _ => evaluated.push(v)
    }
  }

  // If any non-JSON values, return Sequence to preserve functions/regexes
  if has_non_json {
    // 序列长度护栏：构造数组时若展开后元素数超限则抛 D2015
    ctx.check_sequence_length(evaluated.length())
    return @value.JsonataValue::Sequence(evaluated)
  }

  // Otherwise, convert to JSON array
  let results : Array[Json] = []
  for elem in evaluated {
    results.push(elem.to_json())
  }
  @value.JsonataValue::Json(Json::array(results))
}

///|
/// 绑定求值：`$name := value`，绑定变量并返回赋值结果。
/// 对 Lambda 值启用 letrec 语义——函数闭包可在 invoke 时引用自身（按 $name），
/// 修复递归 lambda 定义在跨函数返回后丢失自引用的问题（如 matcher 协议中的 $match）。
fn eval_bind(
  name : String,
  value_ast : @ast.Ast,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let value = match value_ast {
    @ast.Ast::Lambda(params~, body~, signature~, thunk~) =>
      eval_lambda_recursive(name, params, body, signature, thunk, ctx)
    _ => eval(value_ast, ctx)
  }
  ctx.bind(name, value)
  value
}

///|
/// 创建支持自引用的 Lambda（letrec 语义）。
/// 与 `eval_lambda` 相同，但 invoke 时会先绑定 `self_name` 到函数自身，
/// 使函数体内可通过 `$self_name` 递归调用。对齐 jsonata-js function declaration 语义。
fn eval_lambda_recursive(
  self_name : String,
  params : Array[String],
  body : @ast.Ast,
  signature : String?,
  thunk : Bool,
  ctx : @value.EvalContext,
) -> @value.JsonataValue {
  let arity = params.length()
  let captured_ctx = ctx.capture()
  // self_ref 持有函数自身引用，invoke 时绑定到 self_name
  // 初始为 Undefined，函数构造后更新为 Func
  let mut self_ref : @value.JsonataValue = @value.JsonataValue::Undefined
  let invoke = fn(
    args : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let call_ctx = captured_ctx.capture()
    call_ctx.sync_depth_from(ctx2)
    call_ctx.inherit_missing_bindings_from(ctx2)
    // 绑定 self_name 到函数自身，使递归调用可解析
    call_ctx.bind(self_name, self_ref)
    for i, param in params {
      if i < args.length() {
        call_ctx.bind(param, args[i])
      } else if lambda_missing_arg_uses_context(signature) {
        call_ctx.bind(param, ctx2.current())
      }
    }
    // 直接返回 eval 结果（可能是 thunk Func）。
    // trampoline 由 apply_with_trampoline / JsonataFunc::apply 处理。
    eval(body, call_ctx)
  }
  // thunk=true 时构建 thunk_call 闭包，但需要绑定 self_name 到 self_ref
  // 使尾递归调用能正确解析（与 invoke 一致的自引用语义）
  let thunk_call : (() -> (@value.JsonataFunc, Array[@value.JsonataValue]) raise @error.JsonataError)? = if thunk {
    let captured_for_thunk = ctx.capture()
    Some(fn() -> (@value.JsonataFunc, Array[@value.JsonataValue]) raise @error.JsonataError {
      // self_ref 是 mut 变量，闭包按引用捕获，读取时已是更新后的 Func
      captured_for_thunk.bind(self_name, self_ref)
      match body {
        @ast.Ast::Apply(func=func_ast, args=args_ast) => {
          let func_val = eval(func_ast, captured_for_thunk)
          match func_val {
            @value.JsonataValue::Func(f) => {
              let args : Array[@value.JsonataValue] = []
              for arg_ast in args_ast {
                args.push(eval(arg_ast, captured_for_thunk))
              }
              (f, args)
            }
            @value.JsonataValue::Undefined =>
              raise @error.runtime_error(
                match func_ast {
                  @ast.Ast::Path(steps) if steps.length() == 1 =>
                    match steps[0].kind {
                      @ast.StepKind::Name(n) => "T1005: Unknown function: \{n}"
                      _ => "T1006: Attempted to invoke a non-function"
                    }
                  _ => "T1006: Attempted to invoke a non-function"
                },
                code=Some("T1005"),
              )
            _ =>
              raise @error.runtime_error(
                "T1006: Attempted to invoke a non-function",
                code=Some("T1006"),
              )
          }
        }
        _ =>
          raise @error.runtime_error(
            "TCO thunk body 必须是 Apply AST",
            code=None,
          )
      }
    })
  } else {
    None
  }
  let func = @value.JsonataFunc::new(arity~, signature~, invoke~, thunk_call~)
  self_ref = @value.JsonataValue::Func(func)
  @value.JsonataValue::Func(func)
}

///|
/// 块求值：按顺序求值每个表达式，返回最后一个结果。
/// 块内变量绑定（:=）在块结束后自动恢复，实现块级别作用域。
fn eval_block(
  exprs : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let saved = ctx.bindings_snapshot()
  let mut result = @value.JsonataValue::Undefined
  for expr in exprs {
    result = eval(expr, ctx)
  }
  ctx.restore_bindings(saved)
  result
}

///|
/// 带尾调用优化的函数应用（trampoline）。
///
/// 委托给 `JsonataFunc::apply`，该方法的 trampoline 循环对齐 jsonata-js `apply()`：
/// 调用 `invoke` 后，若返回值是携带 `thunk_call` 的 Func，循环展开直到非 thunk。
///
/// 使 `tail-recursion/case007`（6555 层互递归）能在 max_depth=500 下完成，
/// `tail-recursion/case009`（签名不匹配）抛 T0410，
/// `tail-recursion/case006`（无限尾递归）在迭代上限内抛 U1001。
fn apply_with_trampoline(
  f : @value.JsonataFunc,
  args : Array[@value.JsonataValue],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  f.apply(args, ctx)
}

///|
/// 函数调用
///
/// 支持部分应用：当提供参数少于元数时，返回捕获已提供参数的柯里化函数。
/// 通过 trampoline 循环展开尾调用 thunk，使尾递归不增长调用栈。
fn eval_apply(
  func_ast : @ast.Ast,
  args_ast : Array[@ast.Ast],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  // 对含 ? (placeholder) 的参数，若函数值非函数则抛 T1008
  let has_placeholder = has_placeholder(args_ast)
  let func_val = eval(func_ast, ctx)
  match func_val {
    @value.JsonataValue::Func(f) => {
      if has_placeholder {
        return make_partial_apply(f, args_ast, ctx)
      }
      let args : Array[@value.JsonataValue] = []
      for arg_ast in args_ast {
        args.push(eval(arg_ast, ctx))
      }
      let args = apply_context_argument(args, f, ctx)
      let args = f.validate_args(args, ctx.current())
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
          apply_with_trampoline(original, all, ctx2)
        }
        @value.JsonataValue::Func(
          @value.JsonataFunc::new(
            arity=remaining,
            signature=f.signature,
            invoke~,
          ),
        )
      } else {
        apply_with_trampoline(f, args, ctx)
      }
    }
    @value.JsonataValue::Undefined => {
      // 区分 T1005/T1006（普通调用）与 T1007/T1008（偏应用）：
      // - 普通调用：已知函数名但求值结果为 undefined → T1005；非函数 → T1006
      // - 偏应用 `?`：已知函数名 → T1007；非函数 → T1008
      // 对齐 jsonata-js evaluateFunction 与 evaluatePartialApplication 的错误码分支
      let func_name = match func_ast {
        @ast.Ast::Path(steps) if steps.length() == 1 =>
          match steps[0].kind {
            @ast.StepKind::Name(n) => Some(n)
            _ => None
          }
        _ => None
      }
      match func_name {
        Some(name) =>
          match ctx.lookup(name) {
            Some(@value.JsonataValue::Func(_)) =>
              raise @error.runtime_error(
                if has_placeholder {
                  "T1007: Attempted to partially apply a non-function. Did you mean $\{name}?"
                } else {
                  "T1005: Unknown function: \{name}"
                },
                code=Some(if has_placeholder { "T1007" } else { "T1005" }),
              )
            _ =>
              raise @error.runtime_error(
                if has_placeholder {
                  "T1008: Attempted to partially apply a non-function"
                } else {
                  "T1006: Attempted to invoke a non-function"
                },
                code=Some(if has_placeholder { "T1008" } else { "T1006" }),
              )
          }
        None =>
          raise @error.runtime_error(
            if has_placeholder {
              "T1008: Attempted to partially apply a non-function"
            } else {
              "T1006: Attempted to invoke a non-function"
            },
            code=Some(if has_placeholder { "T1008" } else { "T1006" }),
          )
      }
    }
    _ =>
      if has_placeholder {
        raise @error.runtime_error(
          "T1008: Attempted to partially apply a non-lambda expression",
          code=Some("T1008"),
        )
      } else {
        raise @error.runtime_error(
          "T1006: Attempted to invoke a non-function",
          code=Some("T1006"),
        )
      }
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
fn should_partial_on_missing(_f : @value.JsonataFunc) -> Bool {
  false
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
    apply_with_trampoline(f, args, ctx2)
  }
  @value.JsonataValue::Func(
    @value.JsonataFunc::new(
      arity=placeholder_count,
      // 偏函数捕获了部分参数，原始签名已不能正确描述剩余所需参数的
      // 数量与位置。设为 None 跳过 validate_args 严格校验，
      // 让偏函数的 invoke 闭包自行组装完整参数列表后直接调用原函数。
      signature=None,
      invoke~,
    ),
  )
}

///|
/// Lambda 求值
///
/// 当 `thunk=true` 时，body 是尾位置函数调用（Apply AST），返回携带 `thunk_call` 的 Func。
/// `eval_apply` 通过 trampoline 循环展开 thunk，使尾递归不增长调用栈。
fn eval_lambda(
  params : Array[String],
  body : @ast.Ast,
  signature : String?,
  thunk : Bool,
  ctx : @value.EvalContext,
) -> @value.JsonataValue {
  let arity = params.length()
  let captured_ctx = ctx.capture()
  let invoke = fn(
    args : Array[@value.JsonataValue],
    ctx2 : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let call_ctx = captured_ctx.capture()
    // 同步 caller 的递归深度到 call_ctx，使递归调用能正确累积 depth 触发护栏
    // （否则每次 invoke 都从 captured_ctx.depth 起算，递归永远不超过 max_depth）。
    call_ctx.sync_depth_from(ctx2)
    call_ctx.inherit_missing_bindings_from(ctx2)
    for i, param in params {
      if i < args.length() {
        call_ctx.bind(param, args[i])
      } else if lambda_missing_arg_uses_context(signature) {
        call_ctx.bind(param, ctx2.current())
      }
    }
    // 直接返回 eval 结果（可能是 thunk Func）。
    // trampoline 由 apply_with_trampoline / JsonataFunc::apply 处理，
    // 避免 invoke 内嵌 trampoline 导致无限递归。
    eval(body, call_ctx)
  }
  // 当 thunk=true 时，thunk_call 闭包用于 eval_apply 的 trampoline：
  // 评估 Apply.func 与 Apply.args，返回 (next_func, next_args)。
  // thunk Func 的 invoke 仍可正常调用（作为 fallback），但 eval_apply 会优先走 trampoline。
  let thunk_call : (() -> (@value.JsonataFunc, Array[@value.JsonataValue]) raise @error.JsonataError)? = if thunk {
    let captured_for_thunk = ctx.capture()
    Some(fn() -> (@value.JsonataFunc, Array[@value.JsonataValue]) raise @error.JsonataError {
      match body {
        @ast.Ast::Apply(func=func_ast, args=args_ast) => {
          let func_val = eval(func_ast, captured_for_thunk)
          match func_val {
            @value.JsonataValue::Func(f) => {
              let args : Array[@value.JsonataValue] = []
              for arg_ast in args_ast {
                args.push(eval(arg_ast, captured_for_thunk))
              }
              (f, args)
            }
            @value.JsonataValue::Undefined =>
              raise @error.runtime_error(
                match func_ast {
                  @ast.Ast::Path(steps) if steps.length() == 1 =>
                    match steps[0].kind {
                      @ast.StepKind::Name(n) => "T1005: Unknown function: \{n}"
                      _ => "T1006: Attempted to invoke a non-function"
                    }
                  _ => "T1006: Attempted to invoke a non-function"
                },
                code=Some("T1005"),
              )
            _ =>
              raise @error.runtime_error(
                "T1006: Attempted to invoke a non-function",
                code=Some("T1006"),
              )
          }
        }
        _ =>
          // thunk Lambda 的 body 必须是 Apply AST（由 parser 的 tailCallOptimize 保证）
          raise @error.runtime_error(
            "TCO thunk body 必须是 Apply AST",
            code=None,
          )
      }
    })
  } else {
    None
  }
  @value.JsonataValue::Func(
    @value.JsonataFunc::new(arity~, signature~, invoke~, thunk_call~),
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
          _ => result = apply_with_trampoline(f, [result], ctx)
        }
      @value.JsonataValue::Regex(pattern~, flags~) =>
        result = chain_regex_match(result, pattern, flags)
      @value.JsonataValue::Undefined => result = @value.JsonataValue::Undefined
      _ =>
        raise @error.type_error(
          "链中非函数值",
          expected=Some("function"),
          actual=None,
          code=Some("T2006"),
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
        code=Some("T2006"),
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
    apply_with_trampoline(target, args, ctx2)
  }
  let stage_func = @value.JsonataFunc::new(
    arity=1,
    signature=target.signature,
    invoke=stage_invoke,
  )
  match input {
    @value.JsonataValue::Func(left_func) =>
      compose_functions(left_func, stage_func)
    _ => apply_with_trampoline(stage_func, [input], ctx)
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
    let intermediate = apply_with_trampoline(first, args, ctx)
    apply_with_trampoline(second, [intermediate], ctx)
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
    let map : Map[String, Json] = Map([])
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
/// 实现对齐 jsonata-js `evaluateTransformExpression`：
/// 1. 深克隆输入
/// 2. 在克隆结构中按路径步逐层定位匹配项（路径展平语义）
/// 3. 对每个终端匹配项，以匹配值为当前上下文求值 update/delete
/// 4. 通过 `Json::Object(Map)` / `Json::Array(Array)` 的可变引用在原位应用变更
fn eval_transform(
  input : @value.JsonataValue,
  path_ast : @ast.Ast,
  update_ast : @ast.Ast,
  delete_ast : @ast.Ast?,
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let cloned = deep_clone(input)
  match path_ast {
    @ast.Ast::Path(steps) =>
      if steps.length() == 0 {
        // 路径为空：根值本身即为匹配项
        apply_transform_match(cloned, update_ast, delete_ast, ctx)
      } else {
        walk_transform(cloned, steps, 0, update_ast, delete_ast, ctx)
      }
    // 非 Path 路径（如变量、块、链式）：以根为匹配项应用一次变换
    _ => apply_transform_match(cloned, update_ast, delete_ast, ctx)
  }
  cloned
}

///|
/// 在克隆结构中递归按路径步定位并应用变换。
fn walk_transform(
  value : @value.JsonataValue,
  steps : Array[@ast.Step],
  idx : Int,
  update_ast : @ast.Ast,
  delete_ast : @ast.Ast?,
  ctx : @value.EvalContext,
) -> Unit raise @error.JsonataError {
  if idx >= steps.length() {
    // 路径已耗尽：当前值即为终端匹配项
    apply_transform_match(value, update_ast, delete_ast, ctx)
    return
  }
  let step = steps[idx]
  match step.stage {
    @ast.StepStage::Recursive =>
      walk_transform_recursive(
        value, step, steps, idx, update_ast, delete_ast, ctx,
      )
    @ast.StepStage::Single =>
      walk_transform_single(
        value, step, steps, idx, update_ast, delete_ast, ctx,
      )
  }
}

///|
/// 单层步：按 step.kind 在当前结构中导航或匹配。
fn walk_transform_single(
  value : @value.JsonataValue,
  step : @ast.Step,
  steps : Array[@ast.Step],
  idx : Int,
  update_ast : @ast.Ast,
  delete_ast : @ast.Ast?,
  ctx : @value.EvalContext,
) -> Unit raise @error.JsonataError {
  let is_last = idx == steps.length() - 1
  match (value, step.kind) {
    (@value.JsonataValue::Json(Json::Object(map)), @ast.StepKind::Name(name)) =>
      match map.get(name) {
        Some(sub) =>
          if is_last {
            // 终端匹配：sub 可能是 Object / Array / 标量
            apply_transform_match(
              @value.JsonataValue::Json(sub),
              update_ast,
              delete_ast,
              ctx,
            )
          } else {
            walk_transform(
              @value.JsonataValue::Json(sub),
              steps,
              idx + 1,
              update_ast,
              delete_ast,
              ctx,
            )
          }
        None => ()
      }
    (@value.JsonataValue::Json(Json::Array(arr)), @ast.StepKind::Name(_)) =>
      // 数组遇 Name 步：路径展平，对每个元素应用同一步
      for item in arr {
        walk_transform(
          @value.JsonataValue::Json(item),
          steps,
          idx,
          update_ast,
          delete_ast,
          ctx,
        )
      }
    (@value.JsonataValue::Json(Json::Array(arr)), @ast.StepKind::Index(i)) => {
      let len = arr.length()
      let normalized = if i < 0 { len + i } else { i }
      if normalized >= 0 && normalized < len {
        let item_val = @value.JsonataValue::Json(arr[normalized])
        if is_last {
          apply_transform_match(item_val, update_ast, delete_ast, ctx)
        } else {
          walk_transform(item_val, steps, idx + 1, update_ast, delete_ast, ctx)
        }
      }
    }
    (@value.JsonataValue::Sequence(items), @ast.StepKind::Index(i)) => {
      let len = items.length()
      let normalized = if i < 0 { len + i } else { i }
      if normalized >= 0 && normalized < len {
        let item_val = items[normalized]
        if is_last {
          apply_transform_match(item_val, update_ast, delete_ast, ctx)
        } else {
          walk_transform(item_val, steps, idx + 1, update_ast, delete_ast, ctx)
        }
      }
    }
    (@value.JsonataValue::Json(Json::Object(map)), @ast.StepKind::Wildcard) =>
      for k, v in map {
        let sub_val = @value.JsonataValue::Json(v)
        if is_last {
          apply_transform_match(sub_val, update_ast, delete_ast, ctx)
        } else {
          walk_transform(sub_val, steps, idx + 1, update_ast, delete_ast, ctx)
        }
        ignore(k)
      }
    (@value.JsonataValue::Json(Json::Array(arr)), @ast.StepKind::Wildcard) =>
      for item in arr {
        let item_val = @value.JsonataValue::Json(item)
        if is_last {
          apply_transform_match(item_val, update_ast, delete_ast, ctx)
        } else {
          walk_transform(item_val, steps, idx + 1, update_ast, delete_ast, ctx)
        }
      }
    (@value.JsonataValue::Json(Json::Array(arr)), @ast.StepKind::Filter(expr)) =>
      // 数组谓词：保留满足 expr 的元素位置，对每个匹配元素推进路径
      for item in arr {
        let item_val = @value.JsonataValue::Json(item)
        let truthy = ctx.with_context(current=item_val, parent=item_val, fn() -> Bool raise @error.JsonataError {
          let r = eval(expr, ctx)
          to_bool(r)
        })
        if truthy {
          if is_last {
            apply_transform_match(item_val, update_ast, delete_ast, ctx)
          } else {
            walk_transform(
              item_val,
              steps,
              idx + 1,
              update_ast,
              delete_ast,
              ctx,
            )
          }
        }
      }
    (@value.JsonataValue::Json(Json::Object(_)), @ast.StepKind::Filter(expr)) => {
      // 对象谓词：对象视为单例序列，对对象本身求值 expr，truthy 则对象匹配
      let pred_holds = ctx.with_context(current=value, parent=value, fn() -> Bool raise @error.JsonataError {
        let r = eval(expr, ctx)
        to_bool(r)
      })
      if pred_holds {
        if is_last {
          apply_transform_match(value, update_ast, delete_ast, ctx)
        } else {
          // 对象本身匹配但路径未结束：从对象继续推进路径
          // 对象作为单例序列，等同于对对象本身推进下一步
          walk_transform(value, steps, idx + 1, update_ast, delete_ast, ctx)
        }
      }
    }
    (_, @ast.StepKind::Filter(expr)) => {
      // 标量/其它值视为单例序列，对值本身求值 expr
      let pred_holds = ctx.with_context(current=value, parent=value, fn() -> Bool raise @error.JsonataError {
        let r = eval(expr, ctx)
        to_bool(r)
      })
      if pred_holds {
        if is_last {
          apply_transform_match(value, update_ast, delete_ast, ctx)
        } else {
          walk_transform(value, steps, idx + 1, update_ast, delete_ast, ctx)
        }
      }
    }
    (
      @value.JsonataValue::Json(Json::Array(arr)),
      @ast.StepKind::Slice(start, end),
    ) => {
      let len = arr.length()
      let s = match start {
        Some(v) => if v < 0 { len + v } else { v }
        None => 0
      }
      let e = match end {
        Some(v) => if v < 0 { len + v } else { v }
        None => len
      }
      let clamped_s = if s < 0 { 0 } else if s > len { len } else { s }
      let clamped_e = if e < 0 { 0 } else if e > len { len } else { e }
      for i = clamped_s; i < clamped_e; i = i + 1 {
        let item_val = @value.JsonataValue::Json(arr[i])
        if is_last {
          apply_transform_match(item_val, update_ast, delete_ast, ctx)
        } else {
          walk_transform(item_val, steps, idx + 1, update_ast, delete_ast, ctx)
        }
      }
    }
    (_, @ast.StepKind::Eval(inner_expr)) => {
      // Eval 步：求值内部表达式，对结果继续走路径
      // 用于 (expr)[N] 等 parenthesized expression 后接索引/过滤的路径
      let eval_result = ctx.with_context(current=value, parent=value, fn() -> @value.JsonataValue raise @error.JsonataError {
        eval(inner_expr, ctx)
      })
      if is_last {
        apply_transform_match(eval_result, update_ast, delete_ast, ctx)
      } else {
        walk_transform(eval_result, steps, idx + 1, update_ast, delete_ast, ctx)
      }
    }
    (@value.JsonataValue::Sequence(items), _) =>
      // 序列输入：路径展平，对每个元素应用同一步
      for item in items {
        walk_transform(item, steps, idx, update_ast, delete_ast, ctx)
      }
    _ => ()
  }
  ignore(is_last)
}

///|
/// 递归步（`**`）：先在当前层应用 step（按 Single 语义），
/// 然后下降到所有子结构继续应用同一递归步。
/// 对于 Wildcard(Recursive)（即 `**`），当前值本身也是匹配项，
/// 需要将剩余路径应用到当前值（不仅是子结构）。
fn walk_transform_recursive(
  value : @value.JsonataValue,
  step : @ast.Step,
  steps : Array[@ast.Step],
  idx : Int,
  update_ast : @ast.Ast,
  delete_ast : @ast.Ast?,
  ctx : @value.EvalContext,
) -> Unit raise @error.JsonataError {
  match step.kind {
    @ast.StepKind::Wildcard => {
      // `**`：当前值本身是匹配项，推进剩余路径
      if idx + 1 < steps.length() {
        walk_transform(value, steps, idx + 1, update_ast, delete_ast, ctx)
      } else {
        // `**` 是路径末尾：当前值即为终端匹配
        apply_transform_match(value, update_ast, delete_ast, ctx)
      }
      // 下降到子结构，递归应用同一 `**` 步
      match value {
        @value.JsonataValue::Json(Json::Object(map)) =>
          for k, v in map {
            walk_transform_recursive(
              @value.JsonataValue::Json(v),
              step,
              steps,
              idx,
              update_ast,
              delete_ast,
              ctx,
            )
            ignore(k)
          }
        @value.JsonataValue::Json(Json::Array(arr)) =>
          for item in arr {
            walk_transform_recursive(
              @value.JsonataValue::Json(item),
              step,
              steps,
              idx,
              update_ast,
              delete_ast,
              ctx,
            )
          }
        @value.JsonataValue::Sequence(items) =>
          for item in items {
            walk_transform_recursive(
              item, step, steps, idx, update_ast, delete_ast, ctx,
            )
          }
        _ => ()
      }
    }
    _ => {
      // 其它递归步（如 **.Name）：在当前层按 Single 语义应用 step，再下降
      walk_transform_single(
        value, step, steps, idx, update_ast, delete_ast, ctx,
      )
      // 下降到子结构，递归应用同一 Recursive 步
      match value {
        @value.JsonataValue::Json(Json::Object(map)) =>
          for k, v in map {
            walk_transform_recursive(
              @value.JsonataValue::Json(v),
              step,
              steps,
              idx,
              update_ast,
              delete_ast,
              ctx,
            )
            ignore(k)
          }
        @value.JsonataValue::Json(Json::Array(arr)) =>
          for item in arr {
            walk_transform_recursive(
              @value.JsonataValue::Json(item),
              step,
              steps,
              idx,
              update_ast,
              delete_ast,
              ctx,
            )
          }
        @value.JsonataValue::Sequence(items) =>
          for item in items {
            walk_transform_recursive(
              item, step, steps, idx, update_ast, delete_ast, ctx,
            )
          }
        _ => ()
      }
    }
  }
}

///|
/// 对终端匹配项应用更新与删除（直接在 Object 的 Map 上原位修改）。
/// - 匹配值为 Object：以 match 为当前上下文求值 update_ast，合并 update_map 入 map；求值 delete_ast，移除对应键
/// - 匹配值为 Array：路径展平，对每个元素递归调用本函数
/// - 其它（标量、Undefined）：不做改动
fn apply_transform_match(
  value : @value.JsonataValue,
  update_ast : @ast.Ast,
  delete_ast : @ast.Ast?,
  ctx : @value.EvalContext,
) -> Unit raise @error.JsonataError {
  match value {
    @value.JsonataValue::Json(Json::Object(map)) => {
      // 以 match 为当前上下文求值 update/delete
      let update_val = ctx.with_context(current=value, parent=value, fn() -> @value.JsonataValue raise @error.JsonataError {
        eval(update_ast, ctx)
      })
      // T2011: update 必须是 object（undefined 跳过，对齐 jsonata-js）
      match update_val {
        @value.JsonataValue::Undefined => ()
        @value.JsonataValue::Json(Json::Object(update_map)) =>
          for k, v in update_map {
            map.set(k, v)
          }
        _ =>
          raise @error.runtime_error(
            "T2011: The insert/update clause of the transform expression must evaluate to an object",
            code=Some("T2011"),
          )
      }
      // T2012: delete 必须是 string 或 string array（undefined 跳过）
      let delete_keys : Array[String] = match delete_ast {
        Some(d) =>
          ctx.with_context(current=value, parent=value, fn() -> Array[String] raise @error.JsonataError {
            let dval = eval(d, ctx)
            extract_delete_keys(dval)
          })
        None => []
      }
      // 应用 delete
      for k in delete_keys {
        ignore(map.remove(k))
      }
    }
    @value.JsonataValue::Json(Json::Array(arr)) =>
      // 路径展平：对数组每个元素递归应用变换
      for item in arr {
        apply_transform_match(
          @value.JsonataValue::Json(item),
          update_ast,
          delete_ast,
          ctx,
        )
      }
    _ => ()
  }
}

///|
/// 从 delete 表达式求值结果提取字符串键列表。
/// 支持字符串、字符串数组（Json::Array）与序列三种形式。
/// 对齐 jsonata-js `isArrayOfStrings` 检查：非 string/array-of-strings 抛 T2012。
fn extract_delete_keys(
  dval : @value.JsonataValue,
) -> Array[String] raise @error.JsonataError {
  match dval {
    @value.JsonataValue::Undefined => []
    @value.JsonataValue::Json(Json::String(s)) => [s]
    @value.JsonataValue::Sequence(arr) => {
      let keys : Array[String] = []
      for item in arr {
        match item {
          @value.JsonataValue::Json(Json::String(s)) => keys.push(s)
          _ =>
            raise @error.runtime_error(
              "T2012: The delete clause of the transform expression must evaluate to a string or array of strings",
              code=Some("T2012"),
            )
        }
      }
      keys
    }
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let keys : Array[String] = []
      for item in arr {
        match item {
          Json::String(s) => keys.push(s)
          _ =>
            raise @error.runtime_error(
              "T2012: The delete clause of the transform expression must evaluate to a string or array of strings",
              code=Some("T2012"),
            )
        }
      }
      keys
    }
    _ =>
      raise @error.runtime_error(
        "T2012: The delete clause of the transform expression must evaluate to a string or array of strings",
        code=Some("T2012"),
      )
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
      let new_map : Map[String, Json] = Map([])
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
  // 第一遍：求值所有键值对，保留 JsonataValue（不立即转 Json）。
  // 若任意值为 Func/Regex，返回 Object 变体以保留函数字段（对齐 jsonata-js
  // 对象字面量语义——函数可作为字段值并被后续路径访问/调用，如 matcher 协议）。
  // 否则回退到 Json::object 保持向后兼容。
  let value_map : Map[String, @value.JsonataValue] = Map([])
  // 对齐 jsonata-js evaluateGroupExpression：记录每个 key 由哪个 pair 产生，
  // 同一 key 被不同 pair 表达式产生时抛 D1009。
  let key_pair_index : Map[String, Int] = Map([])
  let mut has_non_json = false
  for pair_idx, kv in pairs {
    let (key_ast, val_ast) = kv
    let key = eval(key_ast, ctx)
    // 跳过 undefined key（对齐 jsonata-js：undefined key 不产生 entry）
    if key.is_undefined() {
      continue
    }
    // T1003: key 必须为字符串（或 undefined）
    let key_str = match key {
      @value.JsonataValue::Json(Json::String(s)) => s
      _ =>
        raise @error.type_error(
          "T1003: Key in object structure must evaluate to a string; got: \{to_str(key)}",
          code=Some("T1003"),
        )
    }
    // D1009: 同一 key 被不同 pair 表达式产生
    match key_pair_index.get(key_str) {
      Some(existing_idx) =>
        if existing_idx != pair_idx {
          raise @error.runtime_error(
            "D1009: Multiple key definitions evaluate to same key: \{key_str}",
            code=Some("D1009"),
          )
        }
      None => key_pair_index[key_str] = pair_idx
    }
    let val = eval(val_ast, ctx)
    // 跳过 undefined 值（匹配 JSONata：undefined 字段不出现在对象中）
    if val.is_undefined() {
      continue
    }
    match val {
      @value.JsonataValue::Func(_) | @value.JsonataValue::Regex(_) =>
        has_non_json = true
      _ => ()
    }
    value_map[key_str] = val
  }
  // 若无函数/正则字段，回退到 Json::object 保持向后兼容
  if not(has_non_json) {
    let map : Map[String, Json] = Map([])
    for name, val in value_map {
      map[name] = json_for_constructor(val)
    }
    return @value.JsonataValue::Json(Json::object(map))
  }
  // 有函数/正则字段：返回 Object 变体保留原始 JsonataValue
  @value.JsonataValue::Object(value_map)
}

///|
fn json_for_constructor(value : @value.JsonataValue) -> Json {
  match value {
    @value.JsonataValue::Func(_) => Json::string("")
    @value.JsonataValue::Regex(_) => Json::string("")
    @value.JsonataValue::Object(map) => {
      // 将 Object 转为 Json::object（Func/Regex → ""，对齐 to_json 语义）
      let out : Map[String, Json] = Map([])
      for name, val in map {
        out[name] = json_for_constructor(val)
      }
      Json::object(out)
    }
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
  if sort_terms_contain_parent(terms) || ast_contains_tuple_binding(expr_ast) {
    return eval_sort_with_lineage(expr_ast, terms, ctx)
  }
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
  // T2007/T2008: 验证排序键类型一致性
  validate_sort_key_types(keyed, terms.length())
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
fn sort_terms_contain_parent(terms : Array[@ast.SortTerm]) -> Bool {
  let mut found = false
  for term in terms {
    if ast_contains_parent(term.expr) {
      found = true
      break
    }
  }
  found
}

///|
fn eval_sort_with_lineage(
  expr_ast : @ast.Ast,
  terms : Array[@ast.SortTerm],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  frames_to_value(eval_sort_frames(expr_ast, terms, ctx))
}

///|
fn eval_sort_frames(
  expr_ast : @ast.Ast,
  terms : Array[@ast.SortTerm],
  ctx : @value.EvalContext,
) -> Array[PathFrame] raise @error.JsonataError {
  let frames = match expr_ast {
    @ast.Ast::Path(steps) =>
      eval_path_frames(
        [path_frame(ctx.current(), ctx.ancestors())],
        steps,
        0,
        ctx,
        steps.length(),
      )
    _ => {
      let input = eval(expr_ast, ctx)
      let out : Array[PathFrame] = []
      for item in input.to_array() {
        out.push(path_frame(item, ctx.ancestors()))
      }
      out
    }
  }
  if frames.length() <= 1 {
    return frames
  }
  sort_frames_by_terms(frames, terms, ctx)
}

///|
/// Sort incoming frames by sort terms, preserving frame bindings and ancestors.
/// Used when a sort step appears mid-path in a tuple stream.
fn sort_frames_by_terms(
  frames : Array[PathFrame],
  terms : Array[@ast.SortTerm],
  ctx : @value.EvalContext,
) -> Array[PathFrame] raise @error.JsonataError {
  if frames.length() <= 1 {
    return frames
  }
  let keyed : Array[(Array[@value.JsonataValue], Int, PathFrame)] = []
  for i, frame in frames {
    let keys : Array[@value.JsonataValue] = []
    for term in terms {
      let key = ctx.with_lineage(
        current=frame.value,
        ancestors=frame.ancestors,
        fn() -> @value.JsonataValue raise @error.JsonataError {
          with_frame_bindings(ctx, frame.bindings, fn() -> @value.JsonataValue raise @error.JsonataError {
            eval(term.expr, ctx)
          })
        },
      )
      keys.push(key)
    }
    keyed.push((keys, i, frame))
  }
  // T2007/T2008: 验证排序键类型一致性
  validate_sort_key_types_frames(keyed, terms.length())
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
  let sorted : Array[PathFrame] = []
  for kv in keyed {
    let (_, _, frame) = kv
    sorted.push(frame)
  }
  sorted
}

///|
/// 排序键类型验证：对齐 JSONata-js sort 类型检查。
/// T2008: 排序表达式求值为不可比较的值（非 number/string/undefined）。
/// T2007: 排序值类型不一致（number 与 string 混合）。
fn validate_sort_key_types(
  keyed : Array[(Array[@value.JsonataValue], Int, @value.JsonataValue)],
  num_terms : Int,
) -> Unit raise @error.JsonataError {
  for j = 0; j < num_terms; j = j + 1 {
    // 记录第一个非 undefined 值的类型：0=number, 1=string
    let mut first_type : Int = -1
    for i = 0; i < keyed.length(); i = i + 1 {
      let key = keyed[i].0[j]
      match key {
        @value.JsonataValue::Undefined => ()
        @value.JsonataValue::Json(Json::Number(_)) =>
          if first_type == -1 {
            first_type = 0
          } else if first_type == 1 {
            raise @error.runtime_error(
              "T2007: Values of different types found in the sort expression result",
              code=Some("T2007"),
            )
          }
        @value.JsonataValue::Json(Json::String(_)) =>
          if first_type == -1 {
            first_type = 1
          } else if first_type == 0 {
            raise @error.runtime_error(
              "T2007: Values of different types found in the sort expression result",
              code=Some("T2007"),
            )
          }
        _ =>
          raise @error.runtime_error(
            "T2008: The sort expression doesn't evaluate to a comparable value",
            code=Some("T2008"),
          )
      }
    }
  }
}

///|
/// validate_sort_key_types 的 PathFrame 版本。
fn validate_sort_key_types_frames(
  keyed : Array[(Array[@value.JsonataValue], Int, PathFrame)],
  num_terms : Int,
) -> Unit raise @error.JsonataError {
  for j = 0; j < num_terms; j = j + 1 {
    let mut first_type : Int = -1
    for i = 0; i < keyed.length(); i = i + 1 {
      let key = keyed[i].0[j]
      match key {
        @value.JsonataValue::Undefined => ()
        @value.JsonataValue::Json(Json::Number(_)) =>
          if first_type == -1 {
            first_type = 0
          } else if first_type == 1 {
            raise @error.runtime_error(
              "T2007: Values of different types found in the sort expression result",
              code=Some("T2007"),
            )
          }
        @value.JsonataValue::Json(Json::String(_)) =>
          if first_type == -1 {
            first_type = 1
          } else if first_type == 0 {
            raise @error.runtime_error(
              "T2007: Values of different types found in the sort expression result",
              code=Some("T2007"),
            )
          }
        _ =>
          raise @error.runtime_error(
            "T2008: The sort expression doesn't evaluate to a comparable value",
            code=Some("T2008"),
          )
      }
    }
  }
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
