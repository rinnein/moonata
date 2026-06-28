///|
fn register_object_functions(ctx : @value.EvalContext) -> Unit {
  // $keys
  register(ctx, "keys", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) => {
        let keys : Array[Json] = []
        for k, _ in map {
          keys.push(Json::string(k))
        }
        @value.JsonataValue::Json(Json::array(keys))
      }
      _ => @value.JsonataValue::Undefined
    }
  })
  // $values
  register(ctx, "values", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) => {
        let vals : Array[Json] = []
        for _, v in map {
          vals.push(v)
        }
        @value.JsonataValue::Json(Json::array(vals))
      }
      _ => @value.JsonataValue::Undefined
    }
  })
  // $merge
  register(ctx, "merge", arity=1, invoke=fn(args, _ctx) {
    let result : Map[String, Json] = {}
    match args[0] {
      @value.JsonataValue::Json(Json::Array(arr)) =>
        for item in arr {
          match item {
            Json::Object(map) =>
              for k, v in map {
                result[k] = v
              }
            _ => continue
          }
        }
      @value.JsonataValue::Sequence(arr) =>
        for item in arr {
          match item {
            @value.JsonataValue::Json(Json::Object(map)) =>
              for k, v in map {
                result[k] = v
              }
            _ => continue
          }
        }
      _ => ()
    }
    @value.JsonataValue::Json(Json::object(result))
  })
  // $spread
  register(ctx, "spread", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) => {
        let items : Array[Json] = []
        for k, v in map {
          let m : Map[String, Json] = {}
          m[k] = v
          items.push(Json::object(m))
        }
        @value.JsonataValue::Json(Json::array(items))
      }
      _ => @value.JsonataValue::Undefined
    }
  })
  // $lookup
  register(ctx, "lookup", arity=2, invoke=fn(args, _ctx) {
    let key = value_to_str(args[1])
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) =>
        match map.get(key) {
          Some(v) => @value.JsonataValue::Json(v)
          None => @value.JsonataValue::Undefined
        }
      _ => @value.JsonataValue::Undefined
    }
  })
  // $each
  register(ctx, "each", arity=2, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) => {
        let results : Array[@value.JsonataValue] = []
        for k, v in map {
          let r = (f.invoke)(
            [
              @value.JsonataValue::Json(v),
              @value.JsonataValue::Json(Json::string(k)),
            ],
            ctx,
          )
          match r {
            @value.JsonataValue::Undefined => continue
            _ => results.push(r)
          }
        }
        @value.JsonataValue::sequence(results)
      }
      _ => @value.JsonataValue::Undefined
    }
  })
  // $sift
  register(ctx, "sift", arity=2, invoke=fn(
    args : Array[@value.JsonataValue],
    ctx : @value.EvalContext,
  ) -> @value.JsonataValue raise @error.JsonataError {
    let f = match args[1] {
      @value.JsonataValue::Func(f) => f
      _ => return @value.JsonataValue::Undefined
    }
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) => {
        let result : Map[String, Json] = {}
        for k, v in map {
          let r = (f.invoke)(
            [
              @value.JsonataValue::Json(v),
              @value.JsonataValue::Json(Json::string(k)),
            ],
            ctx,
          )
          if value_to_bool(r) {
            result[k] = v
          }
        }
        @value.JsonataValue::Json(Json::object(result))
      }
      _ => @value.JsonataValue::Undefined
    }
  })
  // $shallow — 浅拷贝对象/数组
  register(ctx, "shallow", arity=1, invoke=fn(args, _ctx) {
    match args[0] {
      @value.JsonataValue::Json(Json::Object(map)) => {
        let result : Map[String, Json] = {}
        for k, v in map {
          result[k] = v
        }
        @value.JsonataValue::Json(Json::object(result))
      }
      @value.JsonataValue::Json(Json::Array(arr)) => {
        let result : Array[Json] = []
        for v in arr {
          result.push(v)
        }
        @value.JsonataValue::Json(Json::array(result))
      }
      _ => args[0]
    }
  })
  // $deep — 深拷贝（JSON 序列化/反序列化）
  register(ctx, "deep", arity=1, invoke=fn(args, _ctx) {
    let s = args[0].to_json().stringify()
    let parsed = @json.parse(s) catch { _ => Json::null() }
    @value.JsonataValue::Json(parsed)
  })
}
