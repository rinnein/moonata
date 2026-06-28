///|
fn register_array_functions(ctx : @value.EvalContext) -> Unit {
  // $map
  register(ctx, "map", arity=2, invoke=fn(args, ctx) {
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
  register(ctx, "filter", arity=2, invoke=fn(args, ctx) {
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
  // $reduce
  register(ctx, "reduce", arity=3, invoke=fn(args, ctx) {
    let items = args[0].to_array()
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    let mut acc = args[2]
    for item in items {
      acc = (f.invoke)([acc, item], ctx)
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
  register(ctx, "sort", arity=1, invoke=fn(args, ctx) {
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
  // $join
  register(ctx, "join", arity=2, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let sep = value_to_str(args[1])
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
      if not(seen.contains(key)) {
        seen.push(key)
        results.push(item)
      }
    }
    @value.JsonataValue::sequence(results)
  })
  // $single — 返回序列中唯一元素，0 或 >1 个时报错
  register(ctx, "single", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    match items.length() {
      0 => @value.JsonataValue::Undefined
      1 => items[0]
      _ => raise @error.runtime_error("$single: 序列包含多个元素")
    }
  })
  // $partition — 将序列按谓词分为 [match, non-match]
  register(ctx, "partition", arity=2, invoke=fn(args, ctx) {
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
  // $zip — 将两个序列按位置配对
  register(ctx, "zip", arity=2, invoke=fn(args, _ctx) {
    let a = args[0].to_array()
    let b = args[1].to_array()
    let len = a.length().min(b.length())
    let arr : Array[Json] = []
    for i in 0..<len {
      let pair : Array[Json] = [a[i].to_json(), b[i].to_json()]
      arr.push(Json::array(pair))
    }
    @value.JsonataValue::Json(Json::array(arr))
  })
}

///|
fn value_to_bool(v : @value.JsonataValue) -> Bool {
  match v {
    @value.JsonataValue::Json(Json::True) => true
    @value.JsonataValue::Json(Json::False) => false
    @value.JsonataValue::Json(Json::Number(n)) => n != 0.0
    @value.JsonataValue::Json(Json::String(s)) => s.length() > 0
    @value.JsonataValue::Json(Json::Null) => false
    @value.JsonataValue::Undefined => false
    @value.JsonataValue::Sequence(arr) => arr.length() > 0
    _ => true
  }
}
