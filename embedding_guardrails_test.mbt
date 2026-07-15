// 嵌入与扩展（embedding-extending）+ 护栏（guardrails）回归测试
// 对齐 JSONata 官方文档：
//   - https://docs.jsonata.org/embedding-extending
//   - https://docs.jsonata.org/guardrails

// ============ embedding-extending: bindings ============

///|
test "embedding: evaluate_with_bindings 注入数值变量" {
  let result = evaluate_with_bindings(
    "$a + $b",
    Json::null(),
    Map([("a", Json::number(4.0)), ("b", Json::number(7.0))]),
  )
  assert_true(result == Json::number(11.0))
}

///|
test "embedding: evaluate_with_bindings 覆盖变量为表达式一部分" {
  // 绑定变量到常量后，表达式引用该变量
  let result = evaluate_with_bindings(
    "$base * 2",
    Json::null(),
    Map([("base", Json::number(21.0))]),
  )
  assert_true(result == Json::number(42.0))
}

///|
test "embedding: evaluate_with_bindings 字符串变量与路径" {
  let data = @json.parse("{\"name\":\"World\"}") catch { _ => Json::null() }
  let result = evaluate_with_bindings(
    "$greeting & ', ' & name",
    data,
    Map([("greeting", Json::string("Hello"))]),
  )
  assert_true(result == Json::string("Hello, World"))
}

// ============ embedding-extending: Compiled.assign ============

///|
test "embedding: Compiled::assign 永久绑定数值" {
  let expr = compile("$a + $b") catch { _ => abort("compile failed") }
  expr.assign("a", Json::number(4.0))
  expr.assign("b", Json::number(1.0))
  let result = expr.run(Json::null()) catch { _ => abort("run failed") }
  assert_true(result == Json::number(5.0))
}

///|
test "embedding: Compiled::assign 跨多次 run 持久" {
  let expr = compile("$a * 2") catch { _ => abort("compile failed") }
  expr.assign("a", Json::number(21.0))
  let r1 = expr.run(Json::null()) catch { _ => abort("run failed") }
  // 第二次 run 仍然携带绑定
  let r2 = expr.run(Json::null()) catch { _ => abort("run failed") }
  assert_true(r1 == Json::number(42.0))
  assert_true(r2 == Json::number(42.0))
}

///|
test "embedding: Compiled::run_with_bindings 临时覆盖 assign" {
  // 对齐 JSONata 文档："the bindings argument in the expression.evaluate()
  // call clobbers these values"
  let expr = compile("$a") catch { _ => abort("compile failed") }
  expr.assign("a", Json::number(4.0))
  let r1 = expr.run(Json::null()) catch { _ => abort("run failed") }
  let r2 = expr.run_with_bindings(
    Json::null(),
    Map([("a", Json::number(109.0))]),
  ) catch {
    _ => abort("run failed")
  }
  assert_true(r1 == Json::number(4.0))
  assert_true(r2 == Json::number(109.0))
  // 临时绑定不影响后续 run
  let r3 = expr.run(Json::null()) catch { _ => abort("run failed") }
  assert_true(r3 == Json::number(4.0))
}

// ============ embedding-extending: Compiled.register_function ============

///|
test "embedding: Compiled::register_function 注册无签名函数" {
  let expr = compile("$greet()") catch { _ => abort("compile failed") }
  expr.register_function("greet", arity=0, signature=None, invoke=fn(
    _args,
    _ctx,
  ) {
    Json::string("Hello world")
  })
  let result = expr.run(Json::null()) catch { _ => abort("run failed") }
  assert_true(result == Json::string("Hello world"))
}

///|
test "embedding: Compiled::register_function 注册带签名函数" {
  // 对齐 JSONata 文档示例：$add(61, 10005) with signature <nn:n>
  let expr = compile("$add(61, 10005)") catch { _ => abort("compile failed") }
  expr.register_function("add", arity=2, signature=Some("<nn:n>"), invoke=fn(
    args,
    _ctx,
  ) {
    match args[0] {
      Json::Number(a, ..) =>
        match args[1] {
          Json::Number(b, ..) => Json::number(a + b)
          _ => Json::null()
        }
      _ => Json::null()
    }
  })
  let result = expr.run(Json::null()) catch { _ => abort("run failed") }
  assert_true(result == Json::number(10066.0))
}

///|
test "embedding: Compiled::register_function 签名类型校验失败抛 T0410" {
  let expr = compile("$add(61, 'hello')") catch { _ => abort("compile failed") }
  expr.register_function("add", arity=2, signature=Some("<nn:n>"), invoke=fn(
    args,
    _ctx,
  ) {
    match args[0] {
      Json::Number(a, ..) =>
        match args[1] {
          Json::Number(b, ..) => Json::number(a + b)
          _ => Json::null()
        }
      _ => Json::null()
    }
  })
  // 第二个参数是字符串，签名要求 number，应抛 T0410
  let raised = try {
    ignore(expr.run(Json::null()))
    false
  } catch {
    @error.JsonataError::SignatureError(message=m, ..) => m.contains("T0410")
    @error.JsonataError::TypeError(message=m, ..) => m.contains("T0410")
    _ => false
  }
  assert_true(raised)
}

///|
test "embedding: register_function 高阶函数（接收数组返回数组）" {
  let expr = compile("$doubler([1, 2, 3])") catch {
    _ => abort("compile failed")
  }
  expr.register_function("doubler", arity=1, signature=Some("<a<n>:a<n>>"), invoke=fn(
    args,
    _ctx,
  ) {
    match args[0] {
      Json::Array(arr) => {
        let out : Array[Json] = []
        for item in arr {
          match item {
            Json::Number(n, ..) => out.push(Json::number(n * 2.0))
            _ => out.push(item)
          }
        }
        Json::array(out)
      }
      _ => Json::null()
    }
  })
  let result = expr.run(Json::null()) catch { _ => abort("run failed") }
  let expected = @json.parse("[2, 4, 6]") catch { _ => Json::null() }
  assert_true(result == expected)
}

// ============ guardrails: stack (D1011) ============

///|
test "guardrails: stack 选项超限抛 D1011" {
  // Ackermann 函数：递归深度爆炸
  let expr = "(  $ack := function($m, $n) {    $m = 0 ? $n + 1 :    $n = 0 ? $ack($m - 1, 1) :    $ack($m - 1, $ack($m, $n - 1))  };  $ack(3, 4)  ) "
  let options = EvalOptions::new(stack=Some(100))
  let raised = try {
    ignore(evaluate_with_options(expr, Json::null(), options))
    false
  } catch {
    @error.JsonataError::GuardrailError(code=Some(c), ..) => c == "D1011"
    _ => false
  }
  assert_true(raised)
}

///|
test "guardrails: stack 选项足够大时正常返回" {
  let expr = "(  $ack := function($m, $n) {    $m = 0 ? $n + 1 :    $n = 0 ? $ack($m - 1, 1) :    $ack($m - 1, $ack($m, $n - 1))  };  $ack(2, 3)  ) "
  let options = EvalOptions::new(stack=Some(2000))
  let result = evaluate_with_options(expr, Json::null(), options) catch {
    _ => abort("unexpected error")
  }
  assert_true(result == Json::number(9.0))
}

// ============ guardrails: sequence (D2015) ============

///|
test "guardrails: sequence 选项超限抛 D2015" {
  // range 操作产生 100 个元素的序列，限制为 10 应触发 D2015
  let expr = "[1..100]"
  let options = EvalOptions::new(sequence=Some(10))
  let raised = try {
    ignore(evaluate_with_options(expr, Json::null(), options))
    false
  } catch {
    @error.JsonataError::GuardrailError(code=Some(c), ..) => c == "D2015"
    _ => false
  }
  assert_true(raised)
}

///|
test "guardrails: sequence 选项足够大时正常返回" {
  let expr = "[1..10]"
  let options = EvalOptions::new(sequence=Some(100))
  let result = evaluate_with_options(expr, Json::null(), options) catch {
    _ => abort("unexpected error")
  }
  // [1..10] → JSON array of 1..10
  match result {
    Json::Array(arr) => assert_eq(arr.length(), 10)
    _ => fail("expected array result")
  }
}

///|
test "guardrails: sequence 限制在 map 步骤中拦截爆炸序列" {
  // 使用 $append 构造大数组，在 map 步骤中展平后超限
  // [1..10].($append([1..10], [1..10])) 会产生 10 * 20 = 200 个元素
  // top_is_construct=false 时 access_map 会展平内部数组
  let expr = "[1..10].($append([1..10], [1..10]))"
  let options = EvalOptions::new(sequence=Some(50))
  let raised = try {
    ignore(evaluate_with_options(expr, Json::null(), options))
    false
  } catch {
    @error.JsonataError::GuardrailError(code=Some(c), ..) => c == "D2015"
    _ => false
  }
  assert_true(raised)
}

///|
test "guardrails: 默认行为不限制序列长度" {
  // 不启用 sequence 选项时，默认 max_sequence = -1（不限制）
  let expr = "[1..100]"
  let result = evaluate(expr, Json::null()) catch {
    _ => abort("unexpected error")
  }
  match result {
    Json::Array(arr) => assert_eq(arr.length(), 100)
    _ => fail("expected array result")
  }
}

// ============ guardrails: 旧路径保持 U1001 兼容 ============

///|
test "guardrails: evaluate_with_max_depth 超限仍抛 U1001（向后兼容）" {
  // tail-recursion case002 期望 U1001（对齐 jsonata-js test runner）
  // 非尾递归 factorial(100) 在 max_depth=50 下必然超限
  let expr = "(  $factorial := function($n) {    $n <= 1 ? 1 : $n * $factorial($n - 1)  };  $factorial(100)  ) "
  let raised = try {
    ignore(evaluate_with_max_depth(expr, Json::null(), 50))
    false
  } catch {
    @error.JsonataError::GuardrailError(code=Some(c), ..) => c == "U1001"
    _ => false
  }
  assert_true(raised)
}

// ============ guardrails: EvalOptions 组合 ============

///|
test "guardrails: EvalOptions 默认不启用任何护栏" {
  let opts = EvalOptions::default()
  assert_true(opts.stack == None)
  assert_true(opts.timeout == None)
  assert_true(opts.sequence == None)
  assert_true(opts.max_steps == None)
}

///|
test "guardrails: EvalOptions::new 接收所有参数" {
  let opts = EvalOptions::new(
    stack=Some(500),
    timeout=Some(1000),
    sequence=Some(1000000),
  )
  assert_true(opts.stack == Some(500))
  assert_true(opts.timeout == Some(1000))
  assert_true(opts.sequence == Some(1000000))
}

///|
test "guardrails: stack + sequence 组合同时启用" {
  // stack=2000 足够大，sequence=5 触发 D2015
  let expr = "[1..10]"
  let options = EvalOptions::new(stack=Some(2000), sequence=Some(5))
  let raised = try {
    ignore(evaluate_with_options(expr, Json::null(), options))
    false
  } catch {
    @error.JsonataError::GuardrailError(code=Some(c), ..) => c == "D2015"
    _ => false
  }
  assert_true(raised)
}

// ============ guardrails: Compiled.run_with_options ============

///|
test "guardrails: Compiled::run_with_options 应用护栏" {
  let expr = compile("[1..100]") catch { _ => abort("compile failed") }
  let options = EvalOptions::new(sequence=Some(10))
  let raised = try {
    ignore(expr.run_with_options(Json::null(), options))
    false
  } catch {
    @error.JsonataError::GuardrailError(code=Some(c), ..) => c == "D2015"
    _ => false
  }
  assert_true(raised)
}

///|
test "guardrails: Compiled::register_function + run_with_options 协同" {
  // 注册自定义函数 + 应用 guardrails
  let expr = compile("$doubler([1, 2, 3])") catch {
    _ => abort("compile failed")
  }
  expr.register_function("doubler", arity=1, signature=Some("<a<n>:a<n>>"), invoke=fn(
    args,
    _ctx,
  ) {
    match args[0] {
      Json::Array(arr) => {
        let out : Array[Json] = []
        for item in arr {
          match item {
            Json::Number(n, ..) => out.push(Json::number(n * 2.0))
            _ => out.push(item)
          }
        }
        Json::array(out)
      }
      _ => Json::null()
    }
  })
  // sequence=10 足够大，正常返回 [2, 4, 6]
  let options = EvalOptions::new(sequence=Some(10))
  let result = expr.run_with_options(Json::null(), options) catch {
    _ => abort("unexpected error")
  }
  let expected = @json.parse("[2, 4, 6]") catch { _ => Json::null() }
  assert_true(result == expected)
}
