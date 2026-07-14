///|
/// 正则相关函数：$match / $contains_regex / $split_regex / $replace_regex
///
/// 依赖 moonbitlang/regexp@0.3.5：compile + Regexp::execute + MatchResult。
fn register_regex_functions(ctx : @value.EvalContext) -> Unit {
  // $match(str, pattern) — 返回首个匹配及捕获组
  register(ctx, "match", arity=2, invoke=fn(args, _ctx) {
    let s = value_to_str(args[0])
    let re = compile_regex_value(args[1]) catch {
      _ => return @value.JsonataValue::Undefined
    }
    let m = re.execute(s)
    if m.matched() {
      // 构造匹配结果对象：{ match: string, groups: [...] }
      let map : Map[String, Json] = Map([])
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
  register(ctx, "contains", arity=2, invoke=(args, _ctx) => {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    // Type validation: first arg must be string, second must be string/regex/function
    match args[0] {
      @value.JsonataValue::Json(Json::String(_)) => ()
      _ =>
        raise @error.runtime_error("T0410: Arguments are not of expected type")
    }
    match args[1] {
      @value.JsonataValue::Json(Json::String(_)) => ()
      @value.JsonataValue::Func(_) => ()
      @value.JsonataValue::Regex(_) => ()
      _ =>
        raise @error.runtime_error("T0410: Arguments are not of expected type")
    }
    contains_regex(args)
  })
  // $split_regex(str, pattern) — 正则分隔符分割
  register(ctx, "split_regex", arity=2, invoke=fn(args, _ctx) {
    split_regex(args)
  })
  register(ctx, "split", arity=2, invoke=(args, _ctx) => {
    if args.length() >= 2 {
      match args[0] {
        @value.JsonataValue::Undefined => return @value.JsonataValue::Undefined
        _ => ()
      }
      match args[0] {
        @value.JsonataValue::Json(Json::String(_)) => ()
        _ =>
          raise @error.runtime_error(
            "T0410: Arguments are not of expected type",
          )
      }
      match args[1] {
        @value.JsonataValue::Json(Json::String(_)) => ()
        @value.JsonataValue::Func(_) => ()
        @value.JsonataValue::Regex(_) => ()
        _ =>
          raise @error.runtime_error(
            "T0410: Arguments are not of expected type",
          )
      }
      if args.length() > 2 {
        match args[2] {
          @value.JsonataValue::Json(Json::Null) =>
            raise @error.runtime_error(
              "T0410: Arguments are not of expected type",
            )
          @value.JsonataValue::Json(Json::Number(n, ..)) =>
            if n < 0.0 {
              raise @error.runtime_error("D3020: Negative limit")
            }
          _ =>
            raise @error.runtime_error(
              "T0410: Arguments are not of expected type",
            )
        }
      }
    }
    split_regex(args)
  })
  // $replace_regex(str, pattern, replacement) — 正则替换（首个匹配）
  register(ctx, "replace_regex", arity=3, invoke=fn(
    args,
    ctx,
  ) -> @value.JsonataValue raise @error.JsonataError {
    replace_regex(args, ctx)
  })
  // $replace(str, pattern, replacement, limit?)
  // JSONata 签名 <s-(sf)(sf)n?:s>：首参字符串，2/3 参为字符串或函数，4 参可选整数。
  // 由于 apply_context_argument 已在 args.length<arity 时前置上下文作为首参，
  // 签名使用 "s(sf)(sf)n?"（不含 `-`）以避免上下文双重替换；
  // 复杂签名启用严格参数数量与类型校验（T0410）。
  // invoke 内额外校验空 pattern (D3010) 与负 limit (D3011)，对齐 JSONata-js。
  register(ctx, "replace", arity=3, signature=Some("s(sf)(sf)n?"), invoke=(
    args,
    ctx,
  ) => {
    if args[0].is_undefined() {
      return @value.JsonataValue::Undefined
    }
    // 空 pattern 校验 (D3010)：仅对字符串 pattern 生效（regex pattern 由 regexp 库处理）
    match args[1] {
      @value.JsonataValue::Json(Json::String(p)) =>
        if p == "" {
          raise @error.runtime_error(
            "D3010: Second argument of replace function cannot be an empty string",
            code=Some("D3010"),
          )
        }
      _ => ()
    }
    // Validate 4th arg (limit): must be number, not null, not negative.
    // 注意：validate_args 会为可选参数 (n?) 在缺省时追加 Undefined，需跳过。
    if args.length() > 3 {
      match args[3] {
        @value.JsonataValue::Undefined => ()
        @value.JsonataValue::Json(Json::Null) =>
          raise @error.runtime_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
        @value.JsonataValue::Json(Json::Number(n, ..)) =>
          if n < 0.0 {
            raise @error.runtime_error(
              "D3011: Fourth argument of replace function must evaluate to a positive number",
              code=Some("D3011"),
            )
          }
        _ =>
          raise @error.runtime_error(
            "T0410: Arguments are not of expected type",
            code=Some("T0410"),
          )
      }
    }
    replace_regex(args, ctx)
  })
}

///|
fn contains_regex(args : Array[@value.JsonataValue]) -> @value.JsonataValue {
  let s = value_to_str(args[0])
  let re = compile_regex_value(args[1]) catch {
    _ => return @value.JsonataValue::Json(Json::boolean(false))
  }
  let m = re.execute(s)
  @value.JsonataValue::Json(Json::boolean(m.matched()))
}

///|
fn split_regex(args : Array[@value.JsonataValue]) -> @value.JsonataValue {
  let s = value_to_str(args[0])
  let limit = if args.length() > 2 { value_to_int(args[2]) } else { -1 }
  if limit == 0 {
    return @value.JsonataValue::Json(Json::array([]))
  }
  match args[1] {
    @value.JsonataValue::Json(Json::String(sep)) =>
      if sep == "" {
        return split_into_characters(s, limit)
      }
    _ => ()
  }
  let re = compile_regex_value(args[1]) catch {
    _ => return @value.JsonataValue::Undefined
  }
  let parts : Array[Json] = []
  let mut remaining = s
  let mut any_match = false
  while remaining.length() > 0 && (limit < 0 || parts.length() < limit) {
    let m = re.execute(remaining)
    if m.matched() {
      if limit >= 0 && parts.length() + 1 > limit {
        break
      }
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
fn split_into_characters(s : String, limit : Int) -> @value.JsonataValue {
  let parts : Array[Json] = []
  for i, c in s.to_array() {
    if limit >= 0 && i >= limit {
      break
    }
    parts.push(Json::string(char_to_string(c)))
  }
  @value.JsonataValue::Json(Json::array(parts))
}

///|
fn char_to_string(c : Char) -> String {
  let out = StringBuilder::new()
  out.write_char(c)
  out.to_string()
}

///|
fn replace_regex(
  args : Array[@value.JsonataValue],
  ctx : @value.EvalContext,
) -> @value.JsonataValue raise @error.JsonataError {
  let s = value_to_str(args[0])
  // 注意：可选参数 (n?) 缺省时 validate_args 会追加 Undefined，需视为未提供（limit=-1）。
  let limit = if args.length() > 3 {
    match args[3] {
      @value.JsonataValue::Undefined => -1
      _ => value_to_int(args[3])
    }
  } else {
    -1
  }
  if limit == 0 {
    return @value.JsonataValue::Json(Json::string(s))
  }
  let re = compile_regex_value(args[1]) catch {
    _ => return @value.JsonataValue::Json(Json::string(s))
  }
  let out = StringBuilder::new()
  let mut remaining = s
  let mut count = 0
  let mut last_remaining = ""
  while remaining.length() > 0 && (limit < 0 || count < limit) {
    let m = re.execute(remaining)
    if !m.matched() {
      break
    }
    out.write_string(m.before().to_owned())
    out.write_string(resolve_replacement(args[2], m, ctx))
    count += 1
    let matched_len = match m.get(0) {
      Some(hit) => hit.length()
      None => 0
    }
    last_remaining = remaining
    remaining = m.after().to_owned()
    // D1004: if match consumed zero length and remaining didn't advance,
    // the next iteration would loop forever
    if matched_len == 0 && remaining == last_remaining {
      raise @error.runtime_error(
        "D1004: Regular expression matches zero length string",
        code=Some("D1004"),
      )
    }
  }
  out.write_string(remaining)
  @value.JsonataValue::Json(Json::string(out.to_string()))
}

///|
fn resolve_replacement(
  replacement : @value.JsonataValue,
  m : @regexp.MatchResult,
  ctx : @value.EvalContext,
) -> String raise @error.JsonataError {
  match replacement {
    @value.JsonataValue::Func(f) => {
      let result = (f.invoke)([@value.JsonataValue::Json(match_object(m))], ctx)
      match result {
        @value.JsonataValue::Json(Json::String(s)) => s
        _ =>
          raise @error.runtime_error(
            "D3012: Replacement function must return a string",
            code=Some("D3012"),
          )
      }
    }
    _ => expand_replacement(value_to_str(replacement), m)
  }
}

///|
fn match_object(m : @regexp.MatchResult) -> Json {
  let map : Map[String, Json] = Map([])
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
  Json::object(map)
}

///|
fn compile_regex_value(
  value : @value.JsonataValue,
) -> @regexp.Regexp raise @regexp.RegexpError {
  match value {
    @value.JsonataValue::Regex(pattern~, flags~) =>
      if flags == "" {
        @regexp.compile(pattern)
      } else {
        @regexp.compile(pattern, flags~)
      }
    _ => @regexp.compile(value_to_str(value))
  }
}

///|
fn expand_replacement(replacement : String, m : @regexp.MatchResult) -> String {
  let out = StringBuilder::new()
  let chars = replacement.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '$' {
      if i + 1 < chars.length() && chars[i + 1] == '$' {
        out.write_char('$')
        i += 2
      } else if i + 1 < chars.length() &&
        chars[i + 1] >= '0' &&
        chars[i + 1] <= '9' {
        let (index, next) = read_replacement_index(
          chars,
          i + 1,
          m.results().length(),
        )
        match m.get(index) {
          Some(group) => out.write_string(group.to_owned())
          None => () // 不存在的或未捕获的 group，输出空字符串
        }
        i = next
      } else {
        out.write_char('$')
        i += 1
      }
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  out.to_string()
}

///|
fn read_replacement_index(
  chars : Array[Char],
  start : Int,
  group_count : Int,
) -> (Int, Int) {
  let first = chars[start].to_int() - '0'.to_int()
  if start + 1 < chars.length() &&
    chars[start + 1] >= '0' &&
    chars[start + 1] <= '9' {
    let two = first * 10 + (chars[start + 1].to_int() - '0'.to_int())
    if two < group_count {
      return (two, start + 2)
    }
  }
  (first, start + 1)
}
