///|
/// 正则相关函数：$match / $contains_regex / $split_regex / $replace_regex
///
/// 依赖 moonbitlang/regexp@0.3.5：compile + Regexp::execute + MatchResult。
fn register_regex_functions(ctx : @value.EvalContext) -> Unit {
  // $match(str, pattern) — 返回首个匹配及捕获组
  register(ctx, "match", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let pattern = value_to_str(args[1])
    let re = @regexp.compile(pattern) catch {
      _ => return @value.JsonataValue::Undefined
    }
    let m = re.execute(s)
    if m.matched() {
      // 构造匹配结果对象：{ match: string, groups: [...] }
      let map : Map[String, Json] = {}
      let matched_str = match m.get(0) {
        Some(s) => s.to_owned()
        None => ""
      }
      map["match"] = Json::string(matched_str)
      let groups : Array[Json] = []
      let results = m.results()
      for i in 1..<results.length() {
        match results[i] {
          Some(g) => groups.push(Json::string(g.to_owned()))
          None => groups.push(Json::null())
        }
      }
      map["groups"] = Json::array(groups)
      @value.JsonataValue::Json(Json::object(map))
    } else {
      @value.JsonataValue::Undefined
    }
  })
  // $contains_regex(str, pattern) — 正则模式包含判断
  register(ctx, "contains_regex", arity=2, invoke=fn(args, _ctx) {
    contains_regex(args)
  })
  // 标准函数名兼容：注册顺序晚于字符串函数，因此覆盖为正则模式版本。
  register(ctx, "contains", arity=2, invoke=fn(args, _ctx) {
    contains_regex(args)
  })
  // $split_regex(str, pattern) — 正则分隔符分割
  register(ctx, "split_regex", arity=2, invoke=fn(args, _ctx) {
    split_regex(args)
  })
  register(ctx, "split", arity=2, invoke=fn(args, _ctx) { split_regex(args) })
  // $replace_regex(str, pattern, replacement) — 正则替换（首个匹配）
  register(ctx, "replace_regex", arity=3, invoke=fn(args, _ctx) {
    replace_regex(args)
  })
  register(ctx, "replace", arity=3, invoke=fn(args, _ctx) {
    replace_regex(args)
  })
}

///|
fn contains_regex(args : Array[@value.JsonataValue]) -> @value.JsonataValue {
  let s = value_to_str(args[0])
  let pattern = value_to_str(args[1])
  let re = @regexp.compile(pattern) catch {
    _ => return @value.JsonataValue::Json(Json::boolean(false))
  }
  let m = re.execute(s)
  @value.JsonataValue::Json(Json::boolean(m.matched()))
}

///|
fn split_regex(args : Array[@value.JsonataValue]) -> @value.JsonataValue {
  let s = value_to_str(args[0])
  let pattern = value_to_str(args[1])
  let re = @regexp.compile(pattern) catch {
    _ => return @value.JsonataValue::Undefined
  }
  let parts : Array[Json] = []
  let mut remaining = s
  let mut any_match = false
  while remaining.length() > 0 {
    let m = re.execute(remaining)
    if m.matched() {
      any_match = true
      parts.push(Json::string(m.before().to_owned()))
      let matched_len = match m.get(0) {
        Some(s) => s.length()
        None => 0
      }
      let after = m.after()
      if matched_len == 0 {
        // 空匹配：前进一个字符避免无限循环
        if after.length() == 0 {
          break
        }
        remaining = after.to_owned()
      } else {
        remaining = after.to_owned()
      }
    } else {
      parts.push(Json::string(remaining))
      break
    }
  }
  if !any_match && parts.length() == 0 {
    parts.push(Json::string(s))
  }
  @value.JsonataValue::Json(Json::array(parts))
}

///|
fn replace_regex(args : Array[@value.JsonataValue]) -> @value.JsonataValue {
  let s = value_to_str(args[0])
  let pattern = value_to_str(args[1])
  let replacement = value_to_str(args[2])
  let re = @regexp.compile(pattern) catch {
    _ => return @value.JsonataValue::Json(Json::string(s))
  }
  let m = re.execute(s)
  if m.matched() {
    let result = m.before().to_owned() + replacement + m.after().to_owned()
    @value.JsonataValue::Json(Json::string(result))
  } else {
    @value.JsonataValue::Json(Json::string(s))
  }
}
