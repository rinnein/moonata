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
        @value.JsonataValue::Json(Json::number(n.round()))
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
