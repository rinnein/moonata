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
        Some(s) => s.to_string()
        None => ""
      }
      map["match"] = Json::string(matched_str)
      let groups : Array[Json] = []
      let results = m.results()
      for i in 1..<results.length() {
        match results[i] {
          Some(g) => groups.push(Json::string(g.to_string()))
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
    let s = value_to_str(args[0])
    let pattern = value_to_str(args[1])
    let re = @regexp.compile(pattern) catch {
      _ => return @value.JsonataValue::Json(Json::boolean(false))
    }
    let m = re.execute(s)
    @value.JsonataValue::Json(Json::boolean(m.matched()))
  })
  // $split_regex(str, pattern) — 正则分隔符分割
  register(ctx, "split_regex", arity=2, invoke=fn(args, _ctx) {
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
        parts.push(Json::string(m.before().to_string()))
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
          remaining = after.to_string()
        } else {
          remaining = after.to_string()
        }
      } else {
        parts.push(Json::string(remaining))
        break
      }
    }
    if not(any_match) && parts.length() == 0 {
      parts.push(Json::string(s))
    }
    @value.JsonataValue::Json(Json::array(parts))
  })
  // $replace_regex(str, pattern, replacement) — 正则替换（首个匹配）
  register(ctx, "replace_regex", arity=3, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let pattern = value_to_str(args[1])
    let replacement = value_to_str(args[2])
    let re = @regexp.compile(pattern) catch {
      _ => return @value.JsonataValue::Json(Json::string(s))
    }
    let m = re.execute(s)
    if m.matched() {
      let result = m.before().to_string() + replacement + m.after().to_string()
      @value.JsonataValue::Json(Json::string(result))
    } else {
      @value.JsonataValue::Json(Json::string(s))
    }
  })
}
