///|
test "JsonataValue 与 JSON 互转" {
  let v = JsonataValue::from_json(Json::number(42.0))
  assert_true(v.to_json() == Json::number(42.0))
  assert_true(v is Json(_))
}

///|
test "Undefined 序列化为 null" {
  assert_true(JsonataValue::Undefined.to_json() == Json::null())
  assert_true(JsonataValue::Undefined.is_undefined())
}

///|
test "序列展平与单例提升" {
  let seq = JsonataValue::sequence([
    JsonataValue::from_json(Json::number(1.0)),
    JsonataValue::from_json(Json::number(2.0)),
  ])
  assert_true(seq is Sequence(_))
  let single = JsonataValue::sequence([
    JsonataValue::from_json(Json::number(1.0)),
  ])
  assert_true(single is Json(_))
  let empty = JsonataValue::sequence([])
  assert_true(empty is Undefined)
}

///|
test "序列展平过滤 Undefined 与嵌套" {
  let flat = JsonataValue::sequence([
    JsonataValue::from_json(Json::number(1.0)),
    JsonataValue::Undefined,
    JsonataValue::Sequence([
      JsonataValue::from_json(Json::number(2.0)),
      JsonataValue::Sequence([JsonataValue::from_json(Json::number(3.0))]),
    ]),
  ])
  match flat {
    Sequence(arr) => assert_eq(arr.length(), 3)
    _ => fail("应为 Sequence")
  }
}

///|
test "lift_singleton 单例提升" {
  let seq = JsonataValue::Sequence([JsonataValue::from_json(Json::number(1.0))])
  let lifted = seq.lift_singleton()
  assert_true(lifted is Json(_))
  let multi = JsonataValue::Sequence([
    JsonataValue::from_json(Json::number(1.0)),
    JsonataValue::from_json(Json::number(2.0)),
  ])
  assert_true(multi.lift_singleton() is Sequence(_))
}

///|
test "Func 值构造与 Debug 输出" {
  let f = JsonataFunc::new(arity=1, invoke=fn(_args, _ctx) {
    JsonataValue::Undefined
  })
  let v = JsonataValue::Func(f)
  assert_true(v is Func(_))
  debug_inspect(
    v,
    content=(
      #|Func("#<func arity=1>")
    ),
  )
}

///|
test "JsonataValue.equal 结构比较" {
  let a = JsonataValue::from_json(Json::number(1.0))
  let b = JsonataValue::from_json(Json::number(1.0))
  assert_true(a.equal(b))
  assert_true(JsonataValue::Undefined.equal(JsonataValue::Undefined))
  let f1 = JsonataValue::Func(
    JsonataFunc::new(arity=1, invoke=fn(_, _) { JsonataValue::Undefined }),
  )
  let f2 = JsonataValue::Func(
    JsonataFunc::new(arity=1, invoke=fn(_, _) { JsonataValue::Undefined }),
  )
  assert_true(f1.equal(f2))
}

///|
test "EvalContext 绑定与查找" {
  let ctx = EvalContext::new(JsonataValue::from_json(Json::number(1.0)))
  ctx.bind("x", JsonataValue::from_json(Json::number(2.0)))
  assert_true(ctx.lookup("x") is Some(Json(_)))
  assert_true(ctx.lookup("y") is None)
  assert_true(ctx.root() is Json(_))
}

///|
test "递归深度护栏触发" {
  let ctx = EvalContext::new_with_limits(
    JsonataValue::Undefined,
    max_depth=3,
    max_steps=1000,
  )
  // 前 3 次成功（depth 1..3）
  ctx.enter()
  ctx.enter()
  ctx.enter()
  // 第 4 次应触发护栏
  let triggered = try {
    ctx.enter()
    false
  } catch {
    _ => true
  }
  assert_true(triggered)
}

///|
test "求值步数护栏触发" {
  let ctx = EvalContext::new_with_limits(
    JsonataValue::Undefined,
    max_depth=1000,
    max_steps=3,
  )
  // 前 3 次成功
  ctx.tick()
  ctx.tick()
  ctx.tick()
  // 第 4 次应触发护栏
  let triggered = try {
    ctx.tick()
    false
  } catch {
    _ => true
  }
  assert_true(triggered)
}

///|
test "with_depth 自动 enter/exit" {
  let ctx = EvalContext::new_with_limits(
    JsonataValue::Undefined,
    max_depth=2,
    max_steps=1000,
  )
  let result : Int = ctx.with_depth(() => ctx.with_depth(() => 42))
  assert_eq(result, 42)
  // 嵌套超过限制应抛错
  let triggered = try {
    ignore(ctx.with_depth(() => ctx.with_depth(() => ctx.with_depth(() => 1))))
    false
  } catch {
    _ => true
  }
  assert_true(triggered)
}
