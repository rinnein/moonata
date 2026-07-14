///|
/// JSONata 函数签名参数描述。
///
/// 对应 JSONata-js `parseSignature` 中每个参数节点的字段：
/// - `base_type`：基础类型码（`s`/`n`/`b`/`o`/`a`/`f`/`j`/`x`/`l`/`(`）。
/// - `regex`：用于匹配参数符号的正则字符类（如 `[sm]`、`[asnblfom]`）。
/// - `array`：基础类型是否为 `a`（数组），允许标量提升为单元素数组。
/// - `subtype`：`a<...>` / `f<...>` 的内层类型字符串（如 `s`、`n`）。
/// - `optional`：`?` 后缀，参数可缺省。
/// - `variadic`：`+` 后缀，参数可重复 1 次以上。
/// - `context`：`-` 后缀，参数缺省时使用上下文值。
priv struct SigParam {
  base_type : String
  mut regex : String
  mut array : Bool
  mut subtype : String?
  mut optional : Bool
  mut variadic : Bool
  mut context : Bool
}

///|
fn SigParam::new(base_type : String, regex : String) -> SigParam {
  {
    base_type,
    regex,
    array: false,
    subtype: None,
    optional: false,
    variadic: false,
    context: false,
  }
}

///|
/// 已解析的 JSONata 函数签名。
///
/// 仅含参数列表；返回类型在解析阶段被丢弃（当前实现不校验返回值）。
priv struct FunctionSignature {
  params : Array[SigParam]
}

///|
/// 判断签名字符串是否包含复杂构造（需要严格校验）。
///
/// 仅含基础类型字符（如 `sn`、`sss`）的签名视为简单签名，沿用旧有宽松校验；
/// 含 `?`/`+`/`-`/`:`/`<`/`>`/`(`/`)` 任意一个的签名视为复杂签名，
/// 走完整 JSONata 语义校验（包含参数数量与类型检查）。
fn is_complex_signature(sig : String) -> Bool {
  for c in sig {
    match c {
      '?' | '+' | '-' | ':' | '<' | '>' | '(' | ')' => return true
      _ => ()
    }
  }
  false
}

///|
/// 剥离外层 `<>`，返回签名内部内容。
fn strip_outer_angles(sig : String) -> String {
  let chars = sig.to_array()
  let n = chars.length()
  if n >= 2 && chars[0] == '<' && chars[n - 1] == '>' {
    let out = StringBuilder::new()
    let end = n - 1
    for i in 1..<end {
      out.write_char(chars[i])
    }
    out.to_string()
  } else {
    sig
  }
}

///|
/// 解析 JSONata 函数签名（不含外层 `<>`）。
///
/// 错误：
/// - `S0401`：`<...>` 类型参数出现在非 `a`/`f` 类型之后；或签名结构无法解析。
/// - `S0402`：`(...)` 选择类型内嵌 `<...>` 参数化类型（当前不支持）。
fn parse_function_signature(
  sig : String,
) -> FunctionSignature raise @error.JsonataError {
  let inner = strip_outer_angles(sig)
  let chars = inner.to_array()
  let n = chars.length()
  let params : Array[SigParam] = []
  let mut prev_param : SigParam? = None
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == ':' {
      // 返回类型起始；当前实现不校验返回值，直接丢弃剩余字符
      break
    }
    match c {
      's' | 'n' | 'b' | 'o' | 'l' => {
        let p = SigParam::new(c.to_string(), "[\{c}m]")
        params.push(p)
        prev_param = Some(p)
      }
      'a' => {
        let p = SigParam::new("a", "[asnblfom]")
        p.array = true
        params.push(p)
        prev_param = Some(p)
      }
      'f' => {
        let p = SigParam::new("f", "f")
        params.push(p)
        prev_param = Some(p)
      }
      'j' => {
        let p = SigParam::new("j", "[asnblom]")
        params.push(p)
        prev_param = Some(p)
      }
      'x' => {
        let p = SigParam::new("x", "[asnblfom]")
        params.push(p)
        prev_param = Some(p)
      }
      '-' =>
        // 上下文填充：修改前一个参数
        match prev_param {
          Some(p) =>
            if p.context {
              raise @error.signature_error(
                "S0401: 重复的上下文修饰符 '-' in signature: \{sig}",
                code=Some("S0401"),
              )
            } else {
              p.context = true
              p.regex = p.regex + "?"
            }
          None =>
            raise @error.signature_error(
              "S0401: 上下文修饰符 '-' 缺少前驱参数 in signature: \{sig}",
              code=Some("S0401"),
            )
        }
      '?' =>
        match prev_param {
          Some(p) => p.optional = true
          None =>
            raise @error.signature_error(
              "S0401: 可选修饰符 '?' 缺少前驱参数 in signature: \{sig}",
              code=Some("S0401"),
            )
        }
      '+' =>
        match prev_param {
          Some(p) => p.variadic = true
          None =>
            raise @error.signature_error(
              "S0401: 可变修饰符 '+' 缺少前驱参数 in signature: \{sig}",
              code=Some("S0401"),
            )
        }
      '(' => {
        // 选择类型：搜索匹配的 ')'
        let mut depth = 1
        let mut j = i + 1
        let mut found = false
        while j < n {
          if chars[j] == '(' {
            depth += 1
          } else if chars[j] == ')' {
            depth -= 1
            if depth == 0 {
              found = true
              break
            }
          }
          j += 1
        }
        if !found {
          raise @error.signature_error(
            "S0401: 未闭合的 '(' in signature: \{sig}",
            code=Some("S0401"),
          )
        }
        // 提取 (...) 内的字符
        let choice = StringBuilder::new()
        let start = i + 1
        for k in start..<j {
          choice.write_char(chars[k])
        }
        let choice_str = choice.to_string()
        // choice 内不允许出现 `<`（参数化类型）
        if choice_str.contains("<") {
          raise @error.signature_error(
            "S0402: 选择类型内不支持参数化类型 '<...>' in signature: \{sig}",
            code=Some("S0402"),
          )
        }
        let p = SigParam::new("(\{choice_str})", "[\{choice_str}m]")
        params.push(p)
        prev_param = Some(p)
        i = j
      }
      '<' =>
        // 类型参数：仅允许出现在 'a' 或 'f' 之后
        match prev_param {
          Some(p) if p.base_type == "a" || p.base_type == "f" => {
            // 搜索匹配的 '>'
            let mut depth = 1
            let mut j = i + 1
            let mut found = false
            while j < n {
              if chars[j] == '<' {
                depth += 1
              } else if chars[j] == '>' {
                depth -= 1
                if depth == 0 {
                  found = true
                  break
                }
              }
              j += 1
            }
            if !found {
              raise @error.signature_error(
                "S0401: 未闭合的 '<' in signature: \{sig}",
                code=Some("S0401"),
              )
            }
            let sub = StringBuilder::new()
            let start = i + 1
            for k in start..<j {
              sub.write_char(chars[k])
            }
            p.subtype = Some(sub.to_string())
            i = j
          }
          _ =>
            raise @error.signature_error(
              "S0401: 类型参数 '<...>' 只能跟在 'a' 或 'f' 之后 in signature: \{sig}",
              code=Some("S0401"),
            )
        }
      ' ' | '\t' | '\n' | '\r' => () // 忽略空白
      _ =>
        raise @error.signature_error(
          "S0401: 无法识别的签名符号 '\{c}' in signature: \{sig}",
          code=Some("S0401"),
        )
    }
    i += 1
  }
  { params, }
}

///|
/// 将运行时值转换为 JSONata 类型符号字符。
///
/// - `s` string、`n` number、`b` boolean、`o` object、`a` array、`f` function、`l` null
/// - `m` missing（undefined）
fn get_value_symbol(value : JsonataValue) -> Char {
  match value {
    Undefined => 'm'
    Func(_) => 'f'
    Regex(..) => 'f'
    Json(Json::String(_)) => 's'
    Json(Json::Number(_)) => 'n'
    Json(Json::True) | Json(Json::False) => 'b'
    Json(Json::Null) => 'l'
    Json(Json::Object(_)) => 'o'
    Json(Json::Array(_)) => 'a'
    Object(_) => 'o'
    Sequence(_) => 'a'
  }
}

///|
/// 判断符号字符是否匹配参数 regex。
///
/// regex 形如 `[abc]` 或 `[abc]?`（context 修饰后），取方括号内字符；
/// 也支持非括号形式如 `f`（单一类型码）。
fn symbol_in_class(sym : Char, regex : String) -> Bool {
  let chars = regex.to_array()
  let n = chars.length()
  // 若 regex 以 '[' 开头，取方括号内字符
  if n > 0 && chars[0] == '[' {
    let mut i = 1
    while i < n && chars[i] != ']' {
      if chars[i] == sym {
        return true
      }
      i += 1
    }
    return false
  }
  // 否则 regex 是单一类型码（如 "f"），直接比较首字符
  if n > 0 {
    return chars[0] == sym
  }
  false
}

///|
/// 校验数组参数的元素类型，并在必要时将标量包装为单元素数组。
///
/// - 对于 `a<s>` 等带子类型的数组参数：
///   - `m`（undefined）：跳过元素校验，原样返回（与 JSONata 行为一致）。
///   - 数组实参：检查所有元素是否匹配子类型首字符；不匹配抛出 T0412。
///   - 标量实参：检查标量本身是否匹配子类型首字符；匹配则包装为单元素数组。
/// - 无子类型：原样返回。
fn validate_array_arg(
  arg : JsonataValue,
  sym : Char,
  subtype : String,
) -> JsonataValue raise @error.JsonataError {
  // undefined 直通——JSONata 中 undefined 通过所有签名检查
  if sym == 'm' {
    return arg
  }
  let sub_chars = subtype.to_array()
  let expected_char = sub_chars[0]
  match sym {
    'a' => {
      // 数组实参：逐个元素检查类型
      let items = arg.to_array()
      for item in items {
        let item_sym = get_value_symbol(item)
        if item_sym != expected_char {
          raise @error.signature_error(
            "T0412: Argument has wrong type. Expected array of \{subtype}, got \{item_sym}",
            code=Some("T0412"),
          )
        }
      }
      arg
    }
    _ => {
      // 标量实参：检查标量本身是否匹配子类型
      if sym != expected_char {
        raise @error.signature_error(
          "T0412: Argument has wrong type. Expected array of \{subtype}, got \{sym}",
          code=Some("T0412"),
        )
      }
      // 包装为单元素数组
      let arr : Array[Json] = [arg.to_json()]
      Json(Json::array(arr))
    }
  }
}

///|
/// 严格校验参数列表，返回可能被包装（标量→单元素数组）后的参数。
///
/// 错误：
/// - `T0410`：参数数量或类型不匹配。
/// - `T0411`：上下文填充值类型不兼容。
/// - `T0412`：数组元素类型不匹配。
///
/// 实现策略：先用回溯匹配为每个参数分配实参数量（对齐 JSONata-js
/// `parseSignature` 生成的正则 `^(p1)(p2)...(pN)$` 的贪婪与回溯语义），
/// 然后按分配结果逐参数校验类型与子类型。
fn FunctionSignature::validate(
  self : FunctionSignature,
  args : Array[JsonataValue],
  context : JsonataValue,
) -> Array[JsonataValue] raise @error.JsonataError {
  let n_params = self.params.length()
  // counts[i] = 第 i 个参数消费的实参数量（用于 variadic 回溯）
  let counts : Array[Int] = []
  for _ in 0..<n_params {
    counts.push(0)
  }
  // 回溯匹配：尝试为每个参数分配 [0..n_args] 个匹配实参，使总和等于 n_args
  if !backtrack_match(self.params, args, 0, 0, counts) {
    raise @error.signature_error(
      "T0410: Arguments are not of expected type",
      code=Some("T0410"),
    )
  }
  // 按分配结果生成 validated args
  let validated : Array[JsonataValue] = []
  let mut arg_idx = 0
  for p_idx, param in self.params {
    let count = counts[p_idx]
    if count == 0 {
      // 缺省：对齐 JSONata-js `signature.validate` 行为——
      // 可选/上下文/可变参数即使未匹配实参，也消费 arg_idx 位置（可能为 undefined），
      // 然后递增 arg_idx。这使得后续参数绑定向后偏移一位。
      if param.context {
        let ctx_sym = get_value_symbol(context)
        if !symbol_in_class(ctx_sym, param.regex) {
          raise @error.signature_error(
            "T0411: Context value not compatible with argument \{p_idx + 1}",
            code=Some("T0411"),
          )
        }
        validated.push(context)
      } else if arg_idx < args.length() {
        validated.push(args[arg_idx])
        arg_idx += 1
      } else {
        validated.push(Undefined)
      }
      continue
    }
    // 消费 count 个匹配实参；若 arg_idx 越界则用 Undefined（对齐 JSONata-js
    // 中 `args[argIndex]` 越界返回 undefined 的行为）
    for _ in 0..<count {
      let arg = if arg_idx < args.length() { args[arg_idx] } else { Undefined }
      let sym = get_value_symbol(arg)
      // 数组参数：校验子类型并按需包装
      let final_arg = if param.array {
        match param.subtype {
          Some(subtype) => validate_array_arg(arg, sym, subtype)
          None => arg
        }
      } else {
        arg
      }
      validated.push(final_arg)
      arg_idx += 1
    }
  }
  validated
}

///|
/// 回溯匹配：为 params 从 param_idx 开始，args 从 arg_idx 开始，
/// 尝试为每个参数分配匹配的实参，使总和等于剩余 args 数量。
///
/// - 对于必需参数：分配恰好 1 个匹配实参。
/// - 对于可选参数：分配 0 或 1 个匹配实参。
/// - 对于可变参数：分配 1+ 个匹配实参。
/// - 对于上下文参数：分配 0 或 1 个匹配实参（缺省走上下文）。
fn backtrack_match(
  params : Array[SigParam],
  args : Array[JsonataValue],
  param_idx : Int,
  arg_idx : Int,
  counts : Array[Int],
) -> Bool {
  let n_params = params.length()
  let n_args = args.length()
  if param_idx == n_params {
    return arg_idx == n_args
  }
  let param = params[param_idx]
  // 确定可分配的实参范围
  let max_count = if param.variadic {
    // 可变：可消费 0..(剩余-后续必需) 个
    n_args - arg_idx
  } else if param.optional || param.context {
    1 // 可选/上下文：0 或 1
  } else {
    1 // 必需：1
  }
  // 起始 count：可变/可选/上下文从 0 开始；必需从 1 开始
  let start_count = if param.variadic || param.optional || param.context {
    0
  } else {
    1
  }
  // 但可变参数至少要 1 个（除非后续参数能消费剩下的）
  // 先尝试从大到小（贪婪），更接近 JSONata 正则语义
  let mut k = max_count
  while k >= start_count {
    // 检查 args[arg_idx..arg_idx+k] 是否都匹配 param 类型
    let mut ok = true
    for j in 0..<k {
      if arg_idx + j >= n_args {
        ok = false
        break
      }
      let sym = get_value_symbol(args[arg_idx + j])
      if !symbol_in_class(sym, param.regex) {
        ok = false
        break
      }
    }
    if ok {
      // 可变参数若 k==0，要求后续能匹配所有剩余
      // 必需参数 k 必须 >= 1
      if !param.variadic && !param.optional && !param.context && k == 0 {
        // 必需参数不能为 0
        k -= 1
        continue
      }
      counts[param_idx] = k
      if backtrack_match(params, args, param_idx + 1, arg_idx + k, counts) {
        return true
      }
    }
    k -= 1
  }
  // 必需参数若未匹配到，则失败
  false
}

///|
/// 对外入口：解析签名并校验参数。
///
/// 简单签名（仅基础类型字符）走宽松校验：仅检查 min(args, params) 个参数类型，
/// 不强制参数数量；保持与历史内建函数签名兼容。
/// 复杂签名走严格校验。
pub fn validate_function_args(
  signature : String,
  args : Array[JsonataValue],
  context : JsonataValue,
) -> Array[JsonataValue] raise @error.JsonataError {
  if !is_complex_signature(signature) {
    // 简单签名：仅做逐参数类型检查，不强制数量
    let chars = signature.to_array()
    let limit = args.length().min(chars.length())
    for i in 0..<limit {
      let sym = get_value_symbol(args[i])
      let expected = chars[i]
      if !symbol_matches_simple(sym, expected) {
        raise @error.signature_error(
          "T0410: Arguments are not of expected type",
          code=Some("T0410"),
        )
      }
    }
    // 返回原 args（不做包装）
    args
  } else {
    let parsed = parse_function_signature(signature)
    parsed.validate(args, context)
  }
}

///|
/// 简单签名逐字符匹配：`m`（undefined）通过所有检查。
fn symbol_matches_simple(sym : Char, expected : Char) -> Bool {
  if sym == 'm' {
    return true
  }
  match expected {
    'j' =>
      sym == 's' ||
      sym == 'n' ||
      sym == 'b' ||
      sym == 'o' ||
      sym == 'a' ||
      sym == 'l'
    'x' =>
      sym == 's' ||
      sym == 'n' ||
      sym == 'b' ||
      sym == 'o' ||
      sym == 'a' ||
      sym == 'l' ||
      sym == 'f'
    's' => sym == 's'
    'n' => sym == 'n'
    'b' => sym == 'b'
    'o' => sym == 'o'
    'a' => sym == 'a'
    'f' => sym == 'f'
    'l' => sym == 'l'
    _ => true
  }
}
