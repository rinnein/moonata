///|
/// HOF 回调的标准参数：`(item, index, source_array)`。
fn hof_callback_args(
  index : Int,
  item : @value.JsonataValue,
  source : @value.JsonataValue,
) -> Array[@value.JsonataValue] {
  [item, @value.JsonataValue::Json(Json::number(index.to_double())), source]
}

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
    let source = json_array_value(items)
    let results : Array[@value.JsonataValue] = []
    for i, item in items {
      let r = (f.invoke)(hof_callback_args(i, item, source), ctx)
      match r {
        @value.JsonataValue::Undefined => continue
        @value.JsonataValue::Sequence(inner) =>
          for inner_item in inner {
            results.push(inner_item)
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
    let source = json_array_value(items)
    let results : Array[@value.JsonataValue] = []
    for i, item in items {
      let r = (f.invoke)(hof_callback_args(i, item, source), ctx)
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
  // $sort(array, comparator?)
  // - arity 1: natural order (number/string/toString)
  // - arity 2: comparator(a,b)→true means a goes after b (a > b), i.e. ascending
  register(ctx, "sort", arity=1, invoke=fn(
    args : Array[@value.JsonataValue],
    _ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let items = args[0].to_array()
    if items.length() <= 1 {
      // $sort always returns a sequence (even for single-element arrays)
      return if items.length() == 0 {
        @value.JsonataValue::Undefined
      } else {
        @value.JsonataValue::Sequence(items)
      }
    }
    if args.length() > 1 {
      // Comparator: function($a, $b) -> boolean
      // comparator(a,b)=true means a > b (a goes after b) → ascending
      let cmp = match args[1] {
        @value.JsonataValue::Func(f) => f
        _ => return @value.JsonataValue::Sequence(items) // no comparator, keep original
      }
      let indexed : Array[(Int, @value.JsonataValue)] = []
      for i = 0; i < items.length(); i = i + 1 {
        indexed.push((i, items[i]))
      }
      // Stable insertion sort using comparator
      for i = 1; i < indexed.length(); i = i + 1 {
        let key = indexed[i]
        let mut j = i
        while j > 0 && item_gt(indexed[j - 1], key, cmp, _ctx) {
          indexed[j] = indexed[j - 1]
          j = j - 1
        }
        indexed[j] = key
      }
      let sorted : Array[@value.JsonataValue] = []
      for kv in indexed {
        let (_, item) = kv
        sorted.push(item)
      }
      return @value.JsonataValue::Sequence(sorted)
    }
    // Natural sort: compare values directly
    let indexed : Array[(Int, @value.JsonataValue)] = []
    for i = 0; i < items.length(); i = i + 1 {
      indexed.push((i, items[i]))
    }
    indexed.sort_by(fn(a, b) {
      let (ia, va) = a
      let (ib, vb) = b
      let cmp = compare_natural(va, vb)
      if cmp != 0 {
        cmp
      } else {
        ia - ib
      }
    })
    let sorted : Array[@value.JsonataValue] = []
    for kv in indexed {
      let (_, item) = kv
      sorted.push(item)
    }
    @value.JsonataValue::Sequence(sorted)
  })
  // $reverse
  register(ctx, "reverse", arity=1, invoke=fn(args, _ctx) {
    let items = args[0].to_array()
    let reversed = items.rev()
    let arr : Array[Json] = []
    for item in reversed {
      arr.push(item.to_json())
    }
    @value.JsonataValue::Json(Json::array(arr))
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
/// 自然排序比较：Number 数值比较，String 字典序（字节序），其他转字符串比较。
fn compare_natural(a : @value.JsonataValue, b : @value.JsonataValue) -> Int {
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
    (@value.JsonataValue::Undefined, _) => 1
    (_, @value.JsonataValue::Undefined) => -1
    _ => {
      let sa = value_to_str(a)
      let sb = value_to_str(b)
      str_cmp(sa, sb)
    }
  }
}

///|
/// 字符串字节序比较，返回 -1/0/1（规避 MoonBit String< 的 collation bug）。
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

///|
/// 用 comparator 判断 a 是否 "大于" b（a 应排在 b 之后）。
/// comparator(a,b)=true ↔ a > b。
fn item_gt(
  a : (Int, @value.JsonataValue),
  b : (Int, @value.JsonataValue),
  cmp : @value.JsonataFunc,
  ctx : @value.EvalContext,
) -> Bool raise @error.JsonataError {
  let (_, va) = a
  let (_, vb) = b
  value_to_bool((cmp.invoke)([va, vb], ctx))
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
