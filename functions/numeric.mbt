///|
fn register_numeric_functions(ctx : @value.EvalContext) -> Unit {
  // $sum
  register(ctx, "sum", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Array(arr)) => {
        let mut total = 0.0
        for v in arr {
          match v {
            Json::Number(n) => total += n
            _ => continue
          }
        }
        @value.JsonataValue::Json(Json::number(total))
      }
      @value.JsonataValue::Sequence(arr) => {
        let mut total = 0.0
        for v in arr {
          match v {
            @value.JsonataValue::Json(Json::Number(n)) => total += n
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
  register(ctx, "abs", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n)) =>
        @value.JsonataValue::Json(Json::number(if n < 0.0 { -n } else { n }))
      _ => @value.JsonataValue::Undefined
    }
  })
  // $floor / $ceiling / $round
  register(ctx, "floor", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n)) =>
        @value.JsonataValue::Json(Json::number(n.floor()))
      _ => @value.JsonataValue::Undefined
    }
  })
  register(ctx, "ceiling", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n)) =>
        @value.JsonataValue::Json(Json::number(n.ceil()))
      _ => @value.JsonataValue::Undefined
    }
  })
  register(ctx, "round", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Number(n)) =>
        @value.JsonataValue::Json(Json::number(n.round()))
      _ => @value.JsonataValue::Undefined
    }
  })
  // $power
  register(ctx, "power", arity=2, invoke=fn(args, _ctx) {
    let base = value_to_double(args[0])
    let exp = value_to_double(args[1])
    @value.JsonataValue::Json(Json::number(base.pow(exp)))
  })
  // $random
  register(ctx, "random", arity=0, invoke=fn(_args, _ctx) {
    @value.JsonataValue::Json(Json::number(0.5))
  })
}

///|
fn value_to_double(v : @value.JsonataValue) -> Double {
  match v {
    @value.JsonataValue::Json(Json::Number(n)) => n
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
          Json::Number(n) => result.push(n)
          _ => continue
        }
      }
    @value.JsonataValue::Sequence(arr) =>
      for item in arr {
        match item {
          @value.JsonataValue::Json(Json::Number(n)) => result.push(n)
          _ => continue
        }
      }
    _ => ()
  }
  result
}
