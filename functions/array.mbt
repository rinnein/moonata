///|
fn register_array_functions(ctx : @value.EvalContext) -> Unit {
  // $map
  register(ctx, "map", arity=2, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let items = args[0].to_array()
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    let results : Array[@value.JsonataValue] = []
    for item in items {
      let r = (f.invoke)([item], ctx)
      match r {
        @value.JsonataValue::Undefined => continue
        @value.JsonataValue::Sequence(inner) =>
          for i in inner {
            results.push(i)
          }
        _ => results.push(r)
      }
    }
    @value.JsonataValue::sequence(results)
  })
  // $filter
  register(ctx, "filter", arity=2, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let items = args[0].to_array()
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    let results : Array[@value.JsonataValue] = []
    for item in items {
      let r = (f.invoke)([item], ctx)
      if value_to_bool(r) {
        results.push(item)
      }
    }
    @value.JsonataValue::sequence(results)
  })
  // $reduce(array, func, init?) — 初始值可选
  register(ctx, "reduce", arity=2, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let items = args[0].to_array()
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    if items.length() == 0 {
      return @value.JsonataValue::Undefined
    }
    let mut acc = if args.length() > 2 { args[2] } else { items[0] }
    let start = if args.length() > 2 { 0 } else { 1 }
    for i in start..<items.length() {
      acc = (f.invoke)([acc, items[i]], ctx)
    }
    acc
  })
  // $count
  register(ctx, "count", arity=1, invoke=fn(args, _ctx) {
    let count = match args[0] {
      @value.JsonataValue::Json(Json::Array(arr)) => arr.length()
      @value.JsonataValue::Sequence(arr) => arr.length()
      @value.JsonataValue::Undefined => 0
      _ => 1
    }
    @value.JsonataValue::Json(Json::number(count.to_double()))
  })
  // $append
  register(ctx, "append", arity=2, invoke=fn(args, _ctx) {
    let a = args[0].to_array()
    let b = args[1].to_array()
    let results : Array[@value.JsonataValue] = []
    for item in a {
      results.push(item)
    }
    for item in b {
      results.push(item)
    }
    @value.JsonataValue::sequence(results)
  })
  // $flatten
  register(ctx, "flatten", arity=1, invoke=fn(args, _ctx) {
    @value.JsonataValue::sequence(args[0].to_array())
  })
  // $sort
  register(ctx, "sort", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    // 简化排序：按数字值
    let keyed : Array[(Double, @value.JsonataValue)] = []
    for item in items {
      keyed.push((value_to_double(item), item))
    }
    keyed.sort_by(fn(a, b) {
      let (na, _) = a
      let (nb, _) = b
      Double::compare(na, nb)
    })
    let sorted : Array[@value.JsonataValue] = []
    for kv in keyed {
      let (_, item) = kv
      sorted.push(item)
    }
    @value.JsonataValue::sequence(sorted)
  })
  // $reverse
  register(ctx, "reverse", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let reversed = items.rev()
    @value.JsonataValue::sequence(reversed)
  })
  // $shuffle
  register(ctx, "shuffle", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let shuffled = shuffle_items(items)
    let arr : Array[Json] = []
    for item in shuffled {
      arr.push(item.to_json())
    }
    @value.JsonataValue::Json(Json::array(arr))
  })
  // $join
  register(ctx, "join", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let sep = if args.length() > 1 { value_to_str(args[1]) } else { "" }
    let parts : Array[String] = []
    for item in items {
      parts.push(value_to_str(item))
    }
    @value.JsonataValue::Json(Json::string(parts.join(sep)))
  })
  // $distinct — 去重（按 JSON 表示）
  register(ctx, "distinct", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let seen : Array[String] = []
    let results : Array[@value.JsonataValue] = []
    for item in items {
      let key = item.to_json().stringify()
      if !seen.contains(key) {
        seen.push(key)
        results.push(item)
      }
    }
    @value.JsonataValue::sequence(results)
  })
  // $single — 返回序列中唯一元素，0 或 >1 个时报错
  register(ctx, "single", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let items = args[0].to_array()
    let candidates = if args.length() > 1 {
      let f = match args[1] {
        @value.JsonataValue::Func(f) => f
        _ => return @value.JsonataValue::Undefined
      }
      filter_single_candidates(items, f, ctx)
    } else {
      items
    }
    match candidates.length() {
      0 => @value.JsonataValue::Undefined
      1 => candidates[0]
      _ => raise @error.runtime_error("$single: 序列包含多个元素")
    }
  })
  // $partition — 将序列按谓词分为 [match, non-match]
  register(ctx, "partition", arity=2, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let items = args[0].to_array()
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    let matched : Array[@value.JsonataValue] = []
    let unmatched : Array[@value.JsonataValue] = []
    for item in items {
      let r = (f.invoke)([item], ctx)
      if value_to_bool(r) {
        matched.push(item)
      } else {
        unmatched.push(item)
      }
    }
    let arr : Array[Json] = [
      @value.JsonataValue::sequence(matched).to_json(),
      @value.JsonataValue::sequence(unmatched).to_json(),
    ]
    @value.JsonataValue::Json(Json::array(arr))
  })
  // $zip — 将一个或多个序列按位置配对
  register(ctx, "zip", arity=1, invoke=fn(args, _ctx) {
    let columns : Array[Array[@value.JsonataValue]] = []
    let mut len = 0
    for i in 0..<args.length() {
      let items = args[i].to_array()
      if i == 0 {
        len = items.length()
      } else {
        len = len.min(items.length())
      }
      columns.push(items)
    }
    let arr : Array[Json] = []
    for row in 0..<len {
      let tuple : Array[Json] = []
      for col in columns {
        tuple.push(col[row].to_json())
      }
      arr.push(Json::array(tuple))
    }
    @value.JsonataValue::Json(Json::array(arr))
  })
}

///|
fn value_to_bool(v : @value.JsonataValue) -> Bool {
  match v {
    @value.JsonataValue::Json(Json::True) => true
    @value.JsonataValue::Json(Json::False) => false
    @value.JsonataValue::Json(Json::Number(n, ..)) => n != 0.0
    @value.JsonataValue::Json(Json::String(s)) => s.length() > 0
    @value.JsonataValue::Json(Json::Null) => false
    @value.JsonataValue::Json(Json::Array(arr)) => {
      let mut any = false
      for item in arr {
        if value_to_bool(@value.JsonataValue::Json(item)) {
          any = true
          break
        }
      }
      any
    }
    @value.JsonataValue::Json(Json::Object(map)) => map.length() > 0
    @value.JsonataValue::Undefined => false
    @value.JsonataValue::Sequence(arr) => arr.length() > 0
    @value.JsonataValue::Func(_) => false
    @value.JsonataValue::Regex(_) => false
  }
}

///|
fn shuffle_items(
  items : Array[@value.JsonataValue],
) -> Array[@value.JsonataValue] {
  let out : Array[@value.JsonataValue] = []
  for item in items {
    out.push(item)
  }
  let mut i = out.length()
  while i > 1 {
    i -= 1
    let j = random_index(i + 1)
    let tmp = out[i]
    out[i] = out[j]
    out[j] = tmp
  }
  out
}

///|
fn filter_single_candidates(
  items : Array[@value.JsonataValue],
  f : @value.JsonataFunc,
  ctx : @value.EvalContext,
) -> Array[@value.JsonataValue] raise @error.JsonataError {
  let source = json_array_value(items)
  let results : Array[@value.JsonataValue] = []
  for i, item in items {
    let r = (f.invoke)(
      [item, @value.JsonataValue::Json(Json::number(i.to_double())), source],
      ctx,
    )
    if value_to_bool(r) {
      results.push(item)
    }
  }
  results
}

///|
fn json_array_value(items : Array[@value.JsonataValue]) -> @value.JsonataValue {
  let arr : Array[Json] = []
  for item in items {
    arr.push(item.to_json())
  }
  @value.JsonataValue::Json(Json::array(arr))
}

///|
fn random_index(limit : Int) -> Int {
  let now = @env.now()
  let seed = (now % 1_000_000).to_double()
  let mixed = @math.sin(seed * 12.9898) * 43758.5453
  let fraction = mixed - mixed.floor()
  (fraction * limit.to_double()).floor().to_int().min(limit - 1).max(0)
}
