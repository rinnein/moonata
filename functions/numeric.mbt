///|
fn register_numeric_functions(ctx : @value.EvalContext) -> Unit {
  // $sum
  register(ctx, "sum", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Array(arr)) => {
        let mut total = 0.0
        for v in arr {
          match v {
            Json::Number(n, ..) => total += n
            _ => continue
          }
        }
        @value.JsonataValue::Json(Json::number(total))
      }
      @value.JsonataValue::Sequence(arr) => {
        let mut total = 0.0
        for v in arr {
          match v {
            @value.JsonataValue::Json(Json::Number(n, ..)) => total += n
            _ => continue
          }
        }
        @value.JsonataValue::Json(Json::number(total))
      }
      @value.JsonataValue::Undefined => @value.JsonataValue::Undefined
      _ => @value.JsonataValue::Undefined
    }
  })
  // $max / $min
  register(ctx, "max", arity=1, invoke=fn(args, _ctx) {
    let nums = value_to_num_array(args[0])
    if nums.length() == 0 {
      return @value.JsonataValue::Undefined
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
    let nums = value_to_num_array(args[0])
    if nums.length() == 0 {
      return @value.JsonataValue::Undefined
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
  // $formatBase(number, radix)
  register(ctx, "formatBase", arity=2, invoke=fn(args, _ctx) {
    let n = value_to_int(args[0])
    let radix = value_to_int(args[1])
    if radix < 2 || radix > 36 {
      return @value.JsonataValue::Undefined
    }
    let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    let mut num = if n < 0 { -n } else { n }
    if num == 0 {
      return @value.JsonataValue::Json(Json::string("0"))
    }
    let chars : Array[Char] = []
    while num > 0 {
      let d = num % radix
      match digits.get_char(d) {
        Some(c) => chars.push(c)
        None => ()
      }
      num = num / radix
    }
    let reversed = chars.rev()
    let buf = StringBuilder::new()
    if n < 0 {
      buf.write_char('-')
    }
    for c in reversed {
      buf.write_char(c)
    }
    @value.JsonataValue::Json(Json::string(buf.to_string()))
  })
  // $formatInteger(number, picture)
  register(ctx, "formatInteger", arity=2, invoke=fn(args, _ctx) {
    let n = value_to_int(args[0])
    let picture = value_to_str(args[1])
    @value.JsonataValue::Json(Json::string(format_integer(n, picture)))
  })
  // $parseInteger(string, picture)
  register(ctx, "parseInteger", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let picture = value_to_str(args[1])
    @value.JsonataValue::Json(
      Json::number(parse_integer(s, picture).to_double()),
    )
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
fn format_integer(n : Int, picture : String) -> String {
  let ordinal = picture.contains(";o")
  let pic = base_picture(picture)
  if pic == "I" || pic == "i" {
    let r = to_roman(n)
    if pic == "i" {
      r.to_lower()
    } else {
      r
    }
  } else if pic.contains("w") || pic.contains("W") {
    let words = number_to_words(n)
    if pic == "W" {
      words.to_upper()
    } else if pic == "Ww" {
      title_words(words)
    } else {
      words
    }
  } else {
    let mut digits = int_abs(n).to_string()
    let min_width = min_integer_width(pic)
    while digits.length() < min_width {
      digits = "0" + digits
    }
    digits = apply_grouping(digits, pic)
    digits = translate_digits(digits, pic)
    if n < 0 {
      digits = "-" + digits
    }
    if ordinal {
      digits + ordinal_suffix(n)
    } else {
      digits
    }
  }
}

///|
fn parse_integer(s : String, picture : String) -> Int {
  let pic = base_picture(picture)
  if pic == "I" || pic == "i" {
    return from_roman(s)
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
    _ => 0
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
  while pos > 0 {
    let (size, sep) = if group_index < groups.length() {
      groups[group_index]
    } else {
      groups[groups.length() - 1]
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
fn number_to_words(n : Int) -> String {
  if n == 0 {
    return "zero"
  }
  let scales = [
    (1_000_000_000, "billion"),
    (1_000_000, "million"),
    (1000, "thousand"),
  ]
  let parts : Array[String] = []
  let mut rest = n
  for scale in scales {
    let (value, name) = scale
    if rest >= value {
      parts.push(number_under_thousand(rest / value) + " " + name)
      rest = rest % value
    }
  }
  if rest > 0 {
    parts.push(number_under_thousand(rest))
  }
  parts.join(", ")
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
fn words_to_number(s : String) -> Int {
  let cleaned = s
    .to_lower()
    .replace_all(old=",", new="")
    .replace_all(old="-", new=" ")
  let mut total = 0
  let mut current = 0
  for part in cleaned.split(" ") {
    let w = part.to_owned()
    if w == "" || w == "and" {
      continue
    }
    let value = word_value(w)
    if value == 100 {
      current *= 100
    } else if value >= 1000 {
      total += current * value
      current = 0
    } else {
      current += value
    }
  }
  total + current
}

///|
fn word_value(w : String) -> Int {
  match w {
    "one" => 1
    "two" => 2
    "three" => 3
    "four" => 4
    "five" => 5
    "six" => 6
    "seven" => 7
    "eight" => 8
    "nine" => 9
    "ten" => 10
    "eleven" => 11
    "twelve" => 12
    "thirteen" => 13
    "fourteen" => 14
    "fifteen" => 15
    "sixteen" => 16
    "seventeen" => 17
    "eighteen" => 18
    "nineteen" => 19
    "twenty" => 20
    "thirty" => 30
    "forty" => 40
    "fifty" => 50
    "sixty" => 60
    "seventy" => 70
    "eighty" => 80
    "ninety" => 90
    "hundred" => 100
    "thousand" => 1000
    "million" => 1_000_000
    "billion" => 1_000_000_000
    _ => 0
  }
}
