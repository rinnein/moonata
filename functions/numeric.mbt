///|
fn register_numeric_functions(ctx : @value.EvalContext) -> Unit {
  // $sum
  register(ctx, "sum", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let mut total = 0.0
    let mut found = false
    for item in items {
      match item {
        @value.JsonataValue::Json(Json::Number(n, ..)) => {
          total += n
          found = true
        }
        _ => continue
      }
    }
    if found {
      @value.JsonataValue::Json(Json::number(total))
    } else {
      @value.JsonataValue::Undefined
    }
  })
  // $average
  register(ctx, "average", arity=1, invoke=fn(args, _ctx) {
    let input_items = args[0].to_array()
    if input_items.length() == 0 {
      return @value.JsonataValue::Undefined
    }
    let nums = value_to_num_array(args[0])
    if nums.length() == 0 {
      raise @error.runtime_error("T0412: No numbers found in the array")
    }
    let mut total = 0.0
    for n in nums {
      total = total + n
    }
    @value.JsonataValue::Json(Json::number(total / nums.length().to_double()))
  })
  // $max / $min
  register(ctx, "max", arity=1, invoke=fn(args, _ctx) {
    if args.length() > 1 {
      raise @error.runtime_error("T0410: Wrong number of arguments")
    }
    let input_items = args[0].to_array()
    if input_items.length() == 0 {
      return @value.JsonataValue::Undefined
    }
    let nums = value_to_strict_num_array(args[0])
    if nums.length() == 0 {
      raise @error.runtime_error("T0412: No numbers found in the array")
    }
    let mut m = nums[0]
    for n in nums {
      if n > m {
        m = n
      }
    }
    @value.JsonataValue::Json(Json::number(m))
  })
  register(ctx, "min", arity=1, invoke=fn(args, _ctx) {
    if args.length() > 1 {
      raise @error.runtime_error("T0410: Wrong number of arguments")
    }
    let input_items = args[0].to_array()
    if input_items.length() == 0 {
      return @value.JsonataValue::Undefined
    }
    let nums = value_to_strict_num_array(args[0])
    if nums.length() == 0 {
      raise @error.runtime_error("T0412: No numbers found in the array")
    }
    let mut m = nums[0]
    for n in nums {
      if n < m {
        m = n
      }
    }
    @value.JsonataValue::Json(Json::number(m))
  })
  // $abs
  register(ctx, "abs", arity=1, signature=Some("n"), invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) =>
        @value.JsonataValue::Json(Json::number(if n < 0.0 { -n } else { n }))
      _ => @value.JsonataValue::Undefined
    }
  })
  // $floor / $ceiling / $round
  register(ctx, "floor", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) =>
        @value.JsonataValue::Json(Json::number(n.floor()))
      _ => @value.JsonataValue::Undefined
    }
  })
  register(ctx, "ceiling", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) =>
        @value.JsonataValue::Json(Json::number(n.ceil()))
      _ => @value.JsonataValue::Undefined
    }
  })
  register(ctx, "ceil", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) =>
        @value.JsonataValue::Json(Json::number(n.ceil()))
      _ => @value.JsonataValue::Undefined
    }
  })
  register(ctx, "round", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) =>
        @value.JsonataValue::Json(
          Json::number(
            round_half_even(
              n,
              if args.length() > 1 {
                value_to_int(args[1])
              } else {
                0
              },
            ),
          ),
        )
      _ => @value.JsonataValue::Undefined
    }
  })
  // $power
  register(ctx, "power", arity=2, signature=Some("nn"), invoke=fn(args, _ctx) {
    let base = value_to_double(args[0])
    let exp = value_to_double(args[1])
    @value.JsonataValue::Json(Json::number(@math.pow(base, exp)))
  })
  // $random
  register(ctx, "random", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::number(random_fraction()))
  })
  // $sqrt
  register(ctx, "sqrt", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n, ..)) =>
        @value.JsonataValue::Json(Json::number(n.sqrt()))
      _ => @value.JsonataValue::Undefined
    }
  })
  // $pi
  register(ctx, "pi", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::number(3.14159265358979323846))
  })
  // $e
  register(ctx, "e", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::number(2.71828182845904523536))
  })
  // $formatBase(number, radix?)
  register(ctx, "formatBase", arity=1, invoke=fn(args, _ctx) {
    let n = value_to_double(args[0]).round().to_int64()
    let radix = if args.length() > 1 { value_to_int(args[1]) } else { 10 }
    if radix < 2 || radix > 36 {
      return @value.JsonataValue::Undefined
    }
    let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    let mut num = if n < 0L { -n } else { n }
    if num == 0L {
      return @value.JsonataValue::Json(Json::string("0"))
    }
    let radix64 = radix.to_int64()
    let chars : Array[Char] = []
    while num > 0L {
      let d = (num % radix64).to_int()
      match digits.get_char(d) {
        Some(c) => chars.push(c)
        None => ()
      }
      num = num / radix64
    }
    let reversed = chars.rev()
    let buf = StringBuilder::new()
    if n < 0L {
      buf.write_char('-')
    }
    for c in reversed {
      buf.write_char(c)
    }
    @value.JsonataValue::Json(Json::string(buf.to_string()))
  })
  // $formatNumber(number, picture, options?)
  register(ctx, "formatNumber", arity=2, invoke=fn(args, _ctx) {
    let n = value_to_double(args[0])
    let picture = value_to_str(args[1])
    validate_format_picture(picture)
    let per_mille = if args.length() > 2 {
      option_string(args[2], "per-mille")
    } else {
      None
    }
    let zero_digit = if args.length() > 2 {
      option_string(args[2], "zero-digit")
    } else {
      None
    }
    @value.JsonataValue::Json(
      Json::string(format_number(n, picture, per_mille, zero_digit)),
    )
  })
  // $formatInteger(number, picture)
  register(ctx, "formatInteger", arity=2, invoke=fn(args, _ctx) {
    let n = value_to_double(args[0])
    let picture = value_to_str(args[1])
    @value.JsonataValue::Json(Json::string(format_integer(n, picture)))
  })
  // $parseInteger(string, picture)
  register(ctx, "parseInteger", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let picture = value_to_str(args[1])
    @value.JsonataValue::Json(Json::number(parse_integer(s, picture)))
  })
}

///|
fn value_to_double(v : @value.JsonataValue) -> Double {
  match v {
    @value.JsonataValue::Json(Json::Number(n, ..)) => n
    _ => 0.0
  }
}

///|
fn value_to_num_array(v : @value.JsonataValue) -> Array[Double] {
  let result : Array[Double] = []
  match v {
    @value.JsonataValue::Json(Json::Number(n, ..)) => result.push(n)
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for item in arr {
        match item {
          Json::Number(n, ..) => result.push(n)
          _ => continue
        }
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        match item {
          @value.JsonataValue::Json(Json::Number(n, ..)) => result.push(n)
          _ => continue
        }
      }
    _ => ()
  }
  result
}

///|
fn value_to_strict_num_array(
  v : @value.JsonataValue,
) -> Array[Double] raise @error.JsonataError {
  let result : Array[Double] = []
  match v {
    @value.JsonataValue::Json(Json::Number(n, ..)) => result.push(n)
    @value.JsonataValue::Json(Json::Array(arr)) =>
      for item in arr {
        match item {
          Json::Number(n, ..) => result.push(n)
          _ =>
            raise @error.runtime_error(
              "T0412: Argument 1 of function must be an array of numbers",
            )
        }
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        match item {
          @value.JsonataValue::Json(Json::Number(n, ..)) => result.push(n)
          _ =>
            raise @error.runtime_error(
              "T0412: Argument 1 of function must be an array of numbers",
            )
        }
      }
    _ => ()
  }
  result
}

///|
fn random_fraction() -> Double {
  let now = @env.now()
  let seed = (now % 1_000_000).to_double()
  let mixed = @math.sin(seed * 12.9898) * 43758.5453
  mixed - mixed.floor()
}

///|
fn round_half_even(n : Double, precision : Int) -> Double {
  let scale = @math.pow(10.0, precision.to_double())
  let scaled = n * scale
  let rounded = round_half_even_integer(scaled)
  let result = rounded / scale
  if result == -0.0 {
    0.0
  } else {
    result
  }
}

///|
fn round_half_even_integer(n : Double) -> Double {
  let sign = if n < 0.0 { -1.0 } else { 1.0 }
  let abs_n = if n < 0.0 { -n } else { n }
  let base = abs_n.floor()
  let frac = abs_n - base
  let tie_delta = if frac >= 0.5 { frac - 0.5 } else { 0.5 - frac }
  let rounded_abs = if tie_delta < 0.0000000001 {
    let base_int = base.to_int()
    if base_int % 2 == 0 {
      base
    } else {
      base + 1.0
    }
  } else if frac < 0.5 {
    base
  } else {
    base + 1.0
  }
  sign * rounded_abs
}

///|
fn option_string(v : @value.JsonataValue, key : String) -> String? {
  match v {
    @value.JsonataValue::Json(Json::Object(map)) =>
      match map.get(key) {
        Some(Json::String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// 验证 $formatNumber picture 格式，无效时抛出对应 JSONata 错误码。
fn validate_format_picture(picture : String) -> Unit raise @error.JsonataError {
  // D3080: 多于一个分号（多于两个子图）
  let mut semicolons = 0
  for _, c in picture {
    if c == ';' {
      semicolons = semicolons + 1
    }
  }
  if semicolons > 1 {
    raise @error.runtime_error("D3080: Invalid picture: too many sub-pictures")
  }
  // D3086: 多个前缀特殊字符（---、%%、‰‰、%‰）
  let prefix = leading_number_prefix(picture)
  let mut prefix_special = 0
  for _, c in prefix {
    if c == '-' || c == '%' || c == '‰' {
      prefix_special = prefix_special + 1
    }
  }
  if prefix_special > 1 {
    raise @error.runtime_error(
      "D3086: Invalid picture: too many prefix characters",
    )
  }
  // D3081: 小数部分多于一个点
  let normalized = normalize_number_picture_digits(picture, None)
  let after_semicolon = match normalized.find(";") {
    Some(i) => normalized[i + 1:].to_owned()
    None => normalized
  }
  let mut dots = 0
  for _, c in after_semicolon {
    if c == '.' {
      dots = dots + 1
    }
  }
  if dots > 1 {
    raise @error.runtime_error(
      "D3081: Invalid picture: multiple decimal separators",
    )
  }
  // D3082/D3083/D3084: percent 和/或 permille 重复或混用
  let after_prefix = strip_number_prefix(after_semicolon, prefix)
  let suffix = trailing_number_suffix(after_prefix)
  let body = strip_number_suffix(after_prefix, suffix)
  let body_has_percent = body.contains("%")
  let suffix_has_percent = suffix.contains("%")
  let body_has_permille = body.contains("‰")
  let suffix_has_permille = suffix.contains("‰")
  let pct_count = (if body_has_percent { 1 } else { 0 }) +
    (if suffix_has_percent { 1 } else { 0 })
  let pm_count = (if body_has_permille { 1 } else { 0 }) +
    (if suffix_has_permille { 1 } else { 0 })
  if pct_count > 1 {
    raise @error.runtime_error("D3082: Invalid picture: multiple percent signs")
  }
  if pm_count > 1 {
    raise @error.runtime_error(
      "D3083: Invalid picture: multiple permille signs",
    )
  }
  if pct_count >= 1 && pm_count >= 1 {
    raise @error.runtime_error(
      "D3084: Invalid picture: percent and permille mixed",
    )
  }
}

///|
fn format_number(
  n : Double,
  picture : String,
  per_mille_option : String?,
  zero_digit_option : String?,
) -> String {
  let normalized_picture = normalize_number_picture_digits(
    picture, zero_digit_option,
  )
  let semicolon = normalized_picture.find(";")
  let (selected, value, emit_sign) = match semicolon {
    Some(i) =>
      if n < 0.0 {
        (normalized_picture[i + 1:].to_owned(), -n, false)
      } else {
        (normalized_picture[:i].to_owned(), n, true)
      }
    None => (normalized_picture, n, true)
  }
  translate_number_output_digits(
    format_number_picture(value, selected, per_mille_option, emit_sign),
    zero_digit_option,
  )
}

///|
fn format_number_picture(
  n : Double,
  picture : String,
  per_mille_option : String?,
  emit_sign : Bool,
) -> String {
  let per_mille = per_mille_option.unwrap_or("‰")
  let multiplier = if picture.contains("%") {
    100.0
  } else if picture.contains(per_mille) {
    1000.0
  } else {
    1.0
  }
  let suffix = if picture.contains("%") {
    "%"
  } else if picture.contains(per_mille) {
    per_mille
  } else {
    trailing_number_suffix(picture)
  }
  let prefix = leading_number_prefix(picture)
  let core_base = strip_number_suffix(
    strip_number_prefix(picture, prefix),
    suffix,
  )
  // 检测科学计数法：e/E 后跟数字格式字符
  let e_pos = find_scientific_exp(core_base)
  match e_pos {
    Some(ep) => {
      let mantissa_pic = core_base[:ep].to_owned()
      let exp_pic = core_base[ep + 1:].to_owned() // 跳过 e/E
      prefix + format_scientific(n * multiplier, mantissa_pic, exp_pic, suffix)
    }
    None => {
      let core = core_base
      let dot = core.find(".")
      let int_pic = match dot {
        Some(i) => core[:i].to_owned()
        None => core
      }
      let frac_pic = match dot {
        Some(i) => core[i + 1:].to_owned()
        None => ""
      }
      let frac_places = count_number_slots(frac_pic)
      let scaled = n * multiplier
      let rounded = round_half_even(scaled, frac_places)
      let negative = rounded < 0.0
      let abs_value = if negative { -rounded } else { rounded }
      let int_str = format_number_integer_from_double(abs_value, int_pic)
      let frac_str = format_number_fraction_from_double(
        abs_value, frac_pic, frac_places,
      )
      let sign = if negative && emit_sign { "-" } else { "" }
      if frac_str == "" {
        prefix + sign + int_str + suffix
      } else {
        prefix + sign + int_str + "." + frac_str + suffix
      }
    }
  }
}

///|
fn normalize_number_picture_digits(
  picture : String,
  zero_digit_option : String?,
) -> String {
  match zero_digit_option {
    None => picture
    Some(zero_digit) => {
      let zero = first_char(zero_digit)
      match zero {
        None => picture
        Some(z) => {
          let out = StringBuilder::new()
          for _, c in picture {
            if custom_digit_value(c, z) is Some(_) {
              out.write_char('0')
            } else {
              out.write_char(c)
            }
          }
          out.to_string()
        }
      }
    }
  }
}

///|
fn translate_number_output_digits(
  text : String,
  zero_digit_option : String?,
) -> String {
  match zero_digit_option {
    None => text
    Some(zero_digit) => {
      let zero = first_char(zero_digit)
      match zero {
        None => text
        Some(z) => {
          let out = StringBuilder::new()
          for _, c in text {
            if c >= '0' && c <= '9' {
              out.write_char(
                Int::unsafe_to_char(z.to_int() + c.to_int() - '0'.to_int()),
              )
            } else {
              out.write_char(c)
            }
          }
          out.to_string()
        }
      }
    }
  }
}

///|
fn custom_digit_value(c : Char, zero : Char) -> Int? {
  let offset = c.to_int() - zero.to_int()
  if offset >= 0 && offset <= 9 {
    Some(offset)
  } else {
    None
  }
}

///|
fn first_char(s : String) -> Char? {
  for _, c in s {
    return Some(c)
  }
  None
}

///|
/// 提取 picture 的前导前缀（第一个数字格式字符之前的文字）。
fn leading_number_prefix(picture : String) -> String {
  let chars = picture.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c == '#' || c == '0' || c == '9' || c == '.' || c == ',' || c == '%' {
      break
    }
    i = i + 1
  }
  chars_to_string(chars, 0, i)
}

///|
fn strip_number_prefix(picture : String, prefix : String) -> String {
  if prefix == "" {
    picture
  } else if picture.has_prefix(prefix) {
    picture[prefix.length():].to_owned()
  } else {
    picture
  }
}

///|
/// 在 picture 中查找科学计数法分隔符 `e` 或 `E`。
/// e/E 后必须是数字格式字符（#/0/9），否则不视为科学计数法。
fn find_scientific_exp(picture : String) -> Int? {
  // 从后往前找 e/E，因为后缀可能包含 e/E（如 SUFFIXe0）
  // 但 standard 中 e/E 位于格式字符之间
  let chars = picture.to_array()
  let mut seen_digit_pattern = false
  let mut i = chars.length()
  while i > 0 {
    i = i - 1
    let c = chars[i]
    match c {
      '#' | '0' | '9' | ',' | '.' => seen_digit_pattern = true
      'e' | 'E' => if seen_digit_pattern { return Some(i) } else { continue }
      _ => continue
    }
  }
  None
}

///|
/// 科学计数法格式化。
fn format_scientific(
  value : Double,
  mantissa_pic : String,
  exp_pic : String,
  suffix : String,
) -> String {
  let negative = value < 0.0
  let abs_val = if negative { -value } else { value }

  // 解析尾数 picture
  let dot_pos = mantissa_pic.find(".")
  let int_pic = match dot_pos {
    Some(i) => mantissa_pic[:i].to_owned()
    None => mantissa_pic
  }
  let frac_pic = match dot_pos {
    Some(i) => mantissa_pic[i + 1:].to_owned()
    None => ""
  }
  let int_slots = count_number_slots(int_pic)
  let frac_slots = count_number_slots(frac_pic)
  let mandatory_int = min_number_width(int_pic) // count of 0/9 in int_pic
  // 若 mantissa picture 包含 . 但无明确小数位，至少保留 1 位小数
  let implicit_frac = if mantissa_pic.contains(".") && frac_slots == 0 {
    1
  } else {
    0
  }

  // 计算指数
  let mut exp = 0
  let mut mantissa_val = abs_val
  if abs_val == 0.0 {
    mantissa_val = 0.0
    exp = 0
  } else if mandatory_int > 0 {
    // mandatory integer digits: normalize mantissa ∈ [10^(mandatory-1), 10^mandatory)
    while mantissa_val >= @math.pow(10.0, mandatory_int.to_double()) {
      mantissa_val = mantissa_val / 10.0
      exp = exp + 1
    }
    while mantissa_val < @math.pow(10.0, (mandatory_int - 1).to_double()) {
      mantissa_val = mantissa_val * 10.0
      exp = exp - 1
    }
  } else if int_slots > 0 {
    // optional (#) integer digits: keep mantissa < 10, or < 1 if none at all
    while mantissa_val >= 10.0 {
      mantissa_val = mantissa_val / 10.0
      exp = exp + 1
    }
    // For # only: no lower-bound normalization (allow mantissa < 1)
  } else {
    // No integer slots at all (e.g. ".00e0"): mantissa stays < 1
    while mantissa_val >= 1.0 {
      mantissa_val = mantissa_val / 10.0
      exp = exp + 1
    }
  }

  // 保留尾数数字
  let effective_frac = frac_slots + implicit_frac
  let total_precision = if int_slots + effective_frac == 0 {
    1
  } else {
    int_slots + effective_frac
  }
  let scale = @math.pow(10.0, total_precision.to_double())
  let rounded = (mantissa_val * scale).round() / scale

  // 处理进位：进位可能导致跨越边界
  let mut m_val = rounded
  let mut e_val = exp
  if mandatory_int > 0 {
    let upper = @math.pow(10.0, mandatory_int.to_double())
    if m_val >= upper && m_val > 0.0 {
      m_val = m_val / 10.0
      e_val = e_val + 1
    }
    let lower = @math.pow(10.0, (mandatory_int - 1).to_double())
    if m_val < lower && m_val > 0.0 {
      m_val = m_val * 10.0
      e_val = e_val - 1
    }
  } else if int_slots > 0 && m_val >= 10.0 && m_val > 0.0 {
    m_val = m_val / 10.0
    e_val = e_val + 1
  }

  // 格式化整数部分
  let mantissa_scale = @math.pow(10.0, effective_frac.to_double())
  let int_part = m_val.floor().to_int64()
  let frac_val = ((m_val - int_part.to_double()) * mantissa_scale)
    .round()
    .to_int64()

  // 整数部分字符串
  let mut int_part_str = int_part.to_string()
  while int_part_str.length() < mandatory_int ||
        int_part_str.length() < int_slots {
    int_part_str = "0" + int_part_str
  }

  // 小数部分
  let mut frac_str = frac_val.to_string()
  while frac_str.length() < effective_frac {
    frac_str = "0" + frac_str
  }
  // 去掉可选小数尾零（保留 implicit_frac 位）
  let mandatory = mandatory_fraction_places(frac_pic) + implicit_frac
  while frac_str.length() > mandatory &&
        frac_str.get_char(frac_str.length() - 1) == Some('0') {
    frac_str = frac_str[:frac_str.length() - 1].to_owned()
  }

  // 构建尾数字符串: 无整数部分的特殊处理
  let has_dot = mantissa_pic.contains(".")
  let mantissa_str = if int_pic == "" && int_slots == 0 {
    // No integer part at all: show nothing before "."
    "." + frac_str
  } else if frac_str == "" && !has_dot {
    int_part_str
  } else {
    int_part_str + "." + frac_str
  }

  // 格式化指数
  let exp_neg = e_val < 0
  let exp_abs = if exp_neg { -e_val } else { e_val }
  let mut exp_str = exp_abs.to_string()
  let exp_min_width = min_number_width(exp_pic)
  while exp_str.length() < exp_min_width {
    exp_str = "0" + exp_str
  }
  let exp_sign = if exp_neg { "-" } else { "" }

  let sign = if negative { "-" } else { "" }
  sign + mantissa_str + "e" + exp_sign + exp_str + suffix
}

///|
fn trailing_number_suffix(picture : String) -> String {
  let chars = picture.to_array()
  let mut i = chars.length()
  while i > 0 {
    let c = chars[i - 1]
    if c == '#' || c == '0' || c == '9' || c == ',' || c == '.' {
      break
    }
    i -= 1
  }
  chars_to_string(chars, i, chars.length())
}

///|
fn strip_number_suffix(picture : String, suffix : String) -> String {
  if suffix == "" {
    picture
  } else if picture.length() >= suffix.length() &&
    picture[picture.length() - suffix.length():].to_owned() == suffix {
    picture[:picture.length() - suffix.length()].to_owned()
  } else {
    picture
  }
}

///|
fn count_number_slots(pic : String) -> Int {
  let mut count = 0
  for c in pic {
    if c == '#' || c == '0' || c == '9' {
      count += 1
    }
  }
  count
}

///|

///|
/// 从 Double 格式化整数部分（处理超 Int64 范围的大数），替代旧 format_number_integer。
fn format_number_integer_from_double(n : Double, pic : String) -> String {
  let int_part = n.floor()
  let digits = if int_part <= 9_007_199_254_740_991.0 {
    int_part.to_int64().to_string()
  } else {
    integer_digits(int_part)
  }
  let mut d = digits
  let min_width = min_number_width(pic)
  while d.length() < min_width {
    d = "0" + d
  }
  apply_grouping(d, pic)
}

///|
/// 从 Double 格式化小数部分。
fn format_number_fraction_from_double(
  n : Double,
  frac_pic : String,
  frac_places : Int,
) -> String {
  if frac_places == 0 {
    return ""
  }
  let frac_scale = @math.pow(10.0, frac_places.to_double())
  let frac_number = ((n - n.floor()) * frac_scale).round().to_int64()
  format_number_fraction(frac_number, frac_pic, frac_places)
}

///|
fn min_number_width(pic : String) -> Int {
  let mut count = 0
  for c in pic {
    if c == '0' || c == '9' {
      count += 1
    }
  }
  count
}

///|
fn format_number_fraction(n : Int64, pic : String, places : Int) -> String {
  if places == 0 {
    return ""
  }
  let mut digits = n.to_string()
  while digits.length() < places {
    digits = "0" + digits
  }
  let mandatory = mandatory_fraction_places(pic)
  while digits.length() > mandatory &&
        digits.get_char(digits.length() - 1) == Some('0') {
    digits = digits[:digits.length() - 1].to_owned()
  }
  apply_fraction_grouping(digits, pic)
}

///|
fn mandatory_fraction_places(pic : String) -> Int {
  let mut count = 0
  for c in pic {
    if c == '0' || c == '9' {
      count += 1
    }
  }
  count
}

///|
fn apply_fraction_grouping(digits : String, pic : String) -> String {
  if !pic.contains(",") || digits == "" {
    return digits
  }
  let out = StringBuilder::new()
  let mut digit_index = 0
  for c in pic {
    if c == ',' {
      if digit_index < digits.length() {
        out.write_char(',')
      }
    } else if c == '#' || c == '0' || c == '9' {
      if digit_index < digits.length() {
        match digits.get_char(digit_index) {
          Some(d) => out.write_char(d)
          None => ()
        }
      }
      digit_index += 1
    }
  }
  out.to_string()
}

///|
fn format_integer(n : Double, picture : String) -> String {
  let ordinal = picture.contains(";o")
  let pic = base_picture(picture)
  if pic == "I" || pic == "i" {
    let r = to_roman(n.to_int())
    if pic == "i" {
      r.to_lower()
    } else {
      r
    }
  } else if pic == "A" || pic == "a" {
    let letters = to_letters(n.to_int())
    if pic == "a" {
      letters.to_lower()
    } else {
      letters
    }
  } else if pic.contains("w") || pic.contains("W") {
    let words = if ordinal {
      number_to_ordinal_words(n)
    } else {
      number_to_words(n)
    }
    if pic == "W" {
      words.to_upper()
    } else if pic == "Ww" {
      title_words(words).replace_all(old=" And ", new=" and ")
    } else {
      words
    }
  } else {
    let negative = n < 0.0
    let abs_n = if negative { -n } else { n }
    let mut digits = integer_digits(abs_n)
    let min_width = min_integer_width(pic)
    while digits.length() < min_width {
      digits = "0" + digits
    }
    digits = apply_grouping(digits, pic)
    digits = translate_digits(digits, pic)
    if negative {
      digits = "-" + digits
    }
    if ordinal {
      digits + ordinal_suffix(n.to_int())
    } else {
      digits
    }
  }
}

///|
fn parse_integer(s : String, picture : String) -> Double {
  let pic = base_picture(picture)
  if pic == "I" || pic == "i" {
    return from_roman(s).to_double()
  }
  if pic == "A" || pic == "a" {
    return from_letters(s).to_double()
  }
  if pic.contains("w") || pic.contains("W") {
    return words_to_number(s)
  }
  let buf = StringBuilder::new()
  for _, c in s {
    match normalize_digit(c) {
      Some(d) => buf.write_char(d)
      None => if c == '-' { buf.write_char(c) }
    }
  }
  @strconv.from_str(buf.to_string()) catch {
    _ => 0.0
  }
}

///|
fn base_picture(picture : String) -> String {
  match picture.find(";") {
    Some(i) => picture[:i].to_owned()
    None => picture
  }
}

///|
fn min_integer_width(pic : String) -> Int {
  let mut count = 0
  for _, c in pic {
    if c != '#' && c != ',' && c != ':' {
      count += 1
    }
  }
  count.max(1)
}

///|
fn apply_grouping(digits : String, pic : String) -> String {
  if !(pic.contains(",") || pic.contains(":")) {
    return digits
  }
  let groups : Array[(Int, Char)] = []
  let mut count = 0
  let mut i = pic.length() - 1
  while i >= 0 {
    match pic.get_char(i) {
      Some(c) =>
        if c == ',' || c == ':' {
          groups.push((count, c))
          count = 0
        } else if c != ';' {
          count += 1
        }
      None => ()
    }
    i -= 1
  }
  if groups.length() == 0 {
    return digits
  }
  let out = StringBuilder::new()
  let mut pos = digits.length()
  let mut group_index = 0
  let parts : Array[String] = []
  let repeat = should_repeat_grouping(groups)
  while pos > 0 {
    let (size, sep) = if group_index < groups.length() {
      groups[group_index]
    } else if groups.length() == 1 || repeat {
      groups[0]
    } else {
      parts.push(digits[0:pos].to_owned())
      pos = 0
      break
    }
    let actual_size = size.max(1)
    let start = (pos - actual_size).max(0)
    parts.push(digits[start:pos].to_owned())
    pos = start
    if pos > 0 {
      let sep_s = String::make(1, sep)
      parts.push(sep_s)
    }
    group_index += 1
  }
  let mut j = parts.length() - 1
  while j >= 0 {
    out.write_string(parts[j])
    j -= 1
  }
  out.to_string()
}

///|
fn should_repeat_grouping(groups : Array[(Int, Char)]) -> Bool {
  if groups.length() <= 1 {
    return true
  }
  let (size0, sep0) = groups[0]
  for group in groups {
    let (size, sep) = group
    if size != size0 || sep != sep0 {
      return false
    }
  }
  true
}

///|
fn translate_digits(digits : String, pic : String) -> String {
  let arabic = "٠١٢٣٤٥٦٧٨٩"
  let full = "０１２３４５６７８９"
  let table = if pic.contains("١") {
    arabic
  } else if pic.contains("０") {
    full
  } else {
    return digits
  }
  let out = StringBuilder::new()
  for _, c in digits {
    if c >= '0' && c <= '9' {
      match table.get_char(c.to_int() - '0'.to_int()) {
        Some(t) => out.write_char(t)
        None => out.write_char(c)
      }
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn normalize_digit(c : Char) -> Char? {
  if c >= '0' && c <= '9' {
    Some(c)
  } else if c >= '٠' && c <= '٩' {
    Some(Int::unsafe_to_char('0'.to_int() + c.to_int() - '٠'.to_int()))
  } else if c >= '０' && c <= '９' {
    Some(Int::unsafe_to_char('0'.to_int() + c.to_int() - '０'.to_int()))
  } else {
    None
  }
}

///|
fn int_abs(n : Int) -> Int {
  if n < 0 {
    -n
  } else {
    n
  }
}

///|
fn integer_digits(n : Double) -> String {
  let int_part = n.floor()
  if int_part <= 9_007_199_254_740_991.0 {
    return int_part.to_int64().to_string()
  }
  format_large_integer_digits(int_part)
}

///|
fn format_large_integer_digits(n : Double) -> String {
  if n < 1000.0 {
    return n.round().to_int().to_string()
  }
  let high = (n / 1000.0).floor()
  let group = (n - high * 1000.0).round().to_int()
  format_large_integer_digits(high) + pad3_int(group)
}

///|
fn pad3_int(n : Int) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

///|
fn ordinal_suffix(n : Int) -> String {
  let x = int_abs(n) % 100
  if x >= 11 && x <= 13 {
    "th"
  } else {
    match int_abs(n) % 10 {
      1 => "st"
      2 => "nd"
      3 => "rd"
      _ => "th"
    }
  }
}

///|
fn to_roman(n : Int) -> String {
  if n <= 0 {
    return ""
  }
  let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  let symbols = [
    "M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I",
  ]
  let out = StringBuilder::new()
  let mut num = n
  for i in 0..<values.length() {
    while num >= values[i] {
      out.write_string(symbols[i])
      num -= values[i]
    }
  }
  out.to_string()
}

///|
fn from_roman(s : String) -> Int {
  let upper = s.to_upper()
  let mut total = 0
  let mut prev = 0
  let mut i = upper.length() - 1
  while i >= 0 {
    let value = match upper.get_char(i) {
      Some('I') => 1
      Some('V') => 5
      Some('X') => 10
      Some('L') => 50
      Some('C') => 100
      Some('D') => 500
      Some('M') => 1000
      _ => 0
    }
    if value < prev {
      total -= value
    } else {
      total += value
      prev = value
    }
    i -= 1
  }
  total
}

///|
fn number_to_words(n : Double) -> String {
  if n == 0.0 {
    return "zero"
  }
  let parts : Array[String] = []
  let mut value = n.floor()
  let mut scale_index = 0
  while value >= 1.0 {
    let high = (value / 1000.0).floor()
    let group = (value - high * 1000.0).round().to_int()
    if group > 0 {
      let scale = scale_name(scale_index)
      let words = number_under_thousand(group)
      if scale == "" {
        parts.push(words)
      } else {
        parts.push(words + " " + scale)
      }
    }
    value = high
    scale_index += 1
  }
  normalize_large_word_join(reverse_strings(parts).join(", "))
}

///|
fn normalize_large_word_join(words : String) -> String {
  let collapsed = words.replace_all(
    old=" thousand trillion, ",
    new=" thousand, ",
  )
  let chars = collapsed.to_array()
  let mut comma = -1
  for i, c in chars {
    if c == ',' {
      comma = i
    }
  }
  if comma < 0 || comma + 2 >= chars.length() {
    return collapsed
  }
  let tail = chars_to_string(chars, comma + 2, chars.length())
  if tail.contains(" ") {
    collapsed
  } else {
    chars_to_string(chars, 0, comma) + " and " + tail
  }
}

///|
fn number_to_ordinal_words(n : Double) -> String {
  let words = number_to_words(n)
  let chars = words.to_array()
  let mut i = chars.length() - 1
  while i >= 0 {
    if (chars[i] >= 'a' && chars[i] <= 'z') ||
      (chars[i] >= 'A' && chars[i] <= 'Z') {
      break
    }
    i -= 1
  }
  let end = i + 1
  while i >= 0 &&
        (
          (chars[i] >= 'a' && chars[i] <= 'z') ||
          (chars[i] >= 'A' && chars[i] <= 'Z')
        ) {
    i -= 1
  }
  let start = i + 1
  chars_to_string(chars, 0, start) +
  ordinal_word(chars_to_string(chars, start, end)) +
  chars_to_string(chars, end, chars.length())
}

///|
fn reverse_strings(items : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut i = items.length() - 1
  while i >= 0 {
    out.push(items[i])
    i -= 1
  }
  out
}

///|
fn scale_name(index : Int) -> String {
  if index == 0 {
    return ""
  }
  let base = match (index - 1) % 4 {
    0 => "thousand"
    1 => "million"
    2 => "billion"
    _ => "trillion"
  }
  let trillion_count = (index - 1) / 4
  if trillion_count == 0 {
    base
  } else {
    let out = StringBuilder::new()
    out.write_string(base)
    for _ in 0..<trillion_count {
      out.write_string(" trillion")
    }
    out.to_string()
  }
}

///|
fn to_letters(n : Int) -> String {
  if n <= 0 {
    return ""
  }
  let out : Array[Char] = []
  let mut value = n
  while value > 0 {
    value -= 1
    out.push(Int::unsafe_to_char('A'.to_int() + value % 26))
    value = value / 26
  }
  let rev = out.rev()
  let buf = StringBuilder::new()
  for c in rev {
    buf.write_char(c)
  }
  buf.to_string()
}

///|
fn from_letters(s : String) -> Int {
  let mut value = 0
  for _, c0 in s {
    let c = if c0 >= 'a' && c0 <= 'z' {
      Int::unsafe_to_char(c0.to_int() - 32)
    } else {
      c0
    }
    if c >= 'A' && c <= 'Z' {
      value = value * 26 + (c.to_int() - 'A'.to_int() + 1)
    }
  }
  value
}

///|
fn number_under_thousand(n : Int) -> String {
  let ones = [
    "", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
    "eighteen", "nineteen",
  ]
  let tens = [
    "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
  ]
  if n < 20 {
    ones[n]
  } else if n < 100 {
    let rem = n % 10
    if rem == 0 {
      tens[n / 10]
    } else {
      tens[n / 10] + "-" + ones[rem]
    }
  } else {
    let rem = n % 100
    if rem == 0 {
      ones[n / 100] + " hundred"
    } else {
      ones[n / 100] + " hundred and " + number_under_thousand(rem)
    }
  }
}

///|
fn title_words(s : String) -> String {
  let out = StringBuilder::new()
  let mut start = true
  for _, c in s {
    if start && c >= 'a' && c <= 'z' {
      out.write_char(Int::unsafe_to_char(c.to_int() - 32))
    } else {
      out.write_char(c)
    }
    start = c == ' ' || c == '-'
  }
  out.to_string()
}

///|
fn words_to_number(s : String) -> Double {
  let cleaned = s
    .to_lower()
    .replace_all(old=",", new="")
    .replace_all(old="-", new=" ")
  let normalized = normalize_ordinal_words(cleaned)
  let mut total = 0.0
  let mut current = 0.0
  for part in normalized.split(" ") {
    let w = part.to_owned()
    if w == "" || w == "and" {
      continue
    }
    let value = word_value(w)
    if value == 100.0 {
      current *= 100
    } else if value >= 1000 {
      if current == 0.0 && total > 0.0 {
        total *= value
      } else {
        total += current * value
      }
      current = 0.0
    } else {
      current += value
    }
  }
  total + current
}

///|
fn normalize_ordinal_words(s : String) -> String {
  let out = StringBuilder::new()
  let mut first = true
  for part in s.split(" ") {
    let w = part.to_owned()
    if w == "" {
      continue
    }
    if !first {
      out.write_char(' ')
    }
    out.write_string(ordinal_to_cardinal(w))
    first = false
  }
  out.to_string()
}

///|
fn ordinal_word(w : String) -> String {
  match w {
    "one" => "first"
    "two" => "second"
    "three" => "third"
    "five" => "fifth"
    "eight" => "eighth"
    "nine" => "ninth"
    "twelve" => "twelfth"
    "twenty" => "twentieth"
    "thirty" => "thirtieth"
    "forty" => "fortieth"
    "fifty" => "fiftieth"
    "sixty" => "sixtieth"
    "seventy" => "seventieth"
    "eighty" => "eightieth"
    "ninety" => "ninetieth"
    "hundred" => "hundredth"
    "thousand" => "thousandth"
    "million" => "millionth"
    "billion" => "billionth"
    "trillion" => "trillionth"
    _ => w + "th"
  }
}

///|
fn ordinal_to_cardinal(w : String) -> String {
  match w {
    "first" => "one"
    "second" => "two"
    "third" => "three"
    "fourth" => "four"
    "fifth" => "five"
    "sixth" => "six"
    "seventh" => "seven"
    "eighth" => "eight"
    "ninth" => "nine"
    "tenth" => "ten"
    "eleventh" => "eleven"
    "twelfth" => "twelve"
    "thirteenth" => "thirteen"
    "fourteenth" => "fourteen"
    "fifteenth" => "fifteen"
    "sixteenth" => "sixteen"
    "seventeenth" => "seventeen"
    "eighteenth" => "eighteen"
    "nineteenth" => "nineteen"
    "twentieth" => "twenty"
    "thirtieth" => "thirty"
    "fortieth" => "forty"
    "fiftieth" => "fifty"
    "sixtieth" => "sixty"
    "seventieth" => "seventy"
    "eightieth" => "eighty"
    "ninetieth" => "ninety"
    "hundredth" => "hundred"
    "thousandth" => "thousand"
    "millionth" => "million"
    "billionth" => "billion"
    "trillionth" => "trillion"
    _ => w
  }
}

///|
fn word_value(w : String) -> Double {
  match w {
    "one" => 1.0
    "two" => 2.0
    "three" => 3.0
    "four" => 4.0
    "five" => 5.0
    "six" => 6.0
    "seven" => 7.0
    "eight" => 8.0
    "nine" => 9.0
    "ten" => 10.0
    "eleven" => 11.0
    "twelve" => 12.0
    "thirteen" => 13.0
    "fourteen" => 14.0
    "fifteen" => 15.0
    "sixteen" => 16.0
    "seventeen" => 17.0
    "eighteen" => 18.0
    "nineteen" => 19.0
    "twenty" => 20.0
    "thirty" => 30.0
    "forty" => 40.0
    "fifty" => 50.0
    "sixty" => 60.0
    "seventy" => 70.0
    "eighty" => 80.0
    "ninety" => 90.0
    "hundred" => 100.0
    "thousand" => 1000.0
    "million" => 1_000_000.0
    "billion" => 1_000_000_000.0
    "trillion" => 1_000_000_000_000.0
    _ => 0.0
  }
}
