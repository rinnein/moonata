///|
/// Moonata CLI 入口（native 目标）。
///
/// 用法：
///   moonata '<expr>'                    # 对 null 求值
///   moonata '<expr>' --data '<json>'   # 对指定 JSON 数据求值
///   moonata '<expr>' --file '<file>'   # 对指定 JSON 文件求值
///   moonata '<expr>' --no-data         # 对 undefined 上下文求值
///   moonata '<expr>' --max-depth <n>   # 指定最大递归深度（对齐 jsonata-js test runner）
///   moonata --help                      # 显示帮助
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  // 解析参数
  let mut expr = ""
  let mut data_str = ""
  let mut use_undefined = false
  let mut max_depth : Int = -1
  let mut i = 1
  while i < args.length() {
    let arg = args[i]
    match arg {
      "--help" | "-h" => {
        print_usage()
        return
      }
      "--data" => {
        i += 1
        if i < args.length() {
          data_str = args[i]
        }
      }
      "--file" => {
        i += 1
        if i < args.length() {
          let file_path = args[i]
          let file_content = @fs.read_file(file_path) catch {
            _ => {
              println("错误: 无法读取文件 \{file_path}")
              return
            }
          }
          data_str = file_content.text()
        }
      }
      "--no-data" =>
        // 对 undefined 上下文求值（对齐 jsonata-js `dataset: null` → undefined 语义）
        use_undefined = true
      "--max-depth" => {
        i += 1
        if i < args.length() {
          try {
            max_depth = @string.parse_int(args[i])
          } catch {
            _ => {
              println("错误: --max-depth 需要整数参数")
              return
            }
          }
        }
      }
      _ => if expr == "" { expr = arg }
    }
    i += 1
  }
  if expr == "" {
    println("错误: 未提供表达式")
    print_usage()
    return
  }
  // 求值
  try {
    let result = if use_undefined {
      if max_depth > 0 {
        @moonata.evaluate_undefined_with_max_depth(expr, max_depth)
      } else {
        @moonata.evaluate_undefined(expr)
      }
    } else {
      // 获取数据
      let data = if data_str != "" { data_str } else { "null" }
      // 解析 JSON 数据
      let json_data = @json.parse(data) catch {
        _ => {
          println("错误: 无效的 JSON 数据")
          return
        }
      }
      if max_depth > 0 {
        @moonata.evaluate_with_max_depth(expr, json_data, max_depth)
      } else {
        @moonata.evaluate(expr, json_data)
      }
    }
    println(result.stringify(indent=2))
  } catch {
    e => {
      // 提取 JSONata 官方错误码并在消息前缀输出，便于测试集匹配。
      // stdout 第一行输出原始 message（未经 Debug 转义），使 audit 脚本
      // 可对 `error.message` 字段做精确子串匹配——jsonata-js test runner
      // 通过 `deep.contain(testcase.error)` 校验，本 CLI 以等价的子串匹配实现。
      // 第二行附 Debug repr 供人工排查（保留 expected/actual/code 等结构化字段），
      // 同样进入 audit 脚本的 haystack，不破坏以 `错误:` 起始的错误检测约定。
      let code = @error.JsonataError::error_code(e)
      let msg = @error.JsonataError::error_message(e)
      match code {
        Some(c) => println("错误: \{c}: \{msg}")
        None => println("错误: \{msg}")
      }
      println(to_repr(e))
    }
  }
}

///|
fn print_usage() -> Unit {
  println("Moonata - JSONata 查询/转换语言 (MoonBit 实现)")
  println("")
  println("用法:")
  println("  moonata '<expr>'                    对 null 求值表达式")
  println("  moonata '<expr>' --data '<json>'    对指定 JSON 数据求值")
  println("  moonata '<expr>' --file '<file>'    对指定 JSON 文件求值")
  println("  moonata '<expr>' --no-data          对 undefined 上下文求值")
  println("  moonata '<expr>' --max-depth <n>    指定最大递归深度")
  println("  moonata --help                      显示此帮助")
  println("")
  println("示例:")
  println("  moonata '1 + 2'")
  println("  moonata 'name' --data '{\"name\":\"Alice\"}'")
  println(
    "  moonata '$sum($.items.price)' --data '{\"items\":[{\"price\":10},{\"price\":20}]}'",
  )
}
