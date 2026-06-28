///|
/// Moonata CLI 入口（native 目标）。
///
/// 用法：
///   moonata '<expr>'                    # 对 null 求值
///   moonata '<expr>' --data '<json>'   # 对指定 JSON 数据求值
///   moonata --help                      # 显示帮助
fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  // 解析参数
  let mut expr = ""
  let mut data_str = ""
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
      _ => if expr == "" { expr = arg }
    }
    i += 1
  }
  if expr == "" {
    println("错误: 未提供表达式")
    print_usage()
    return
  }
  // 获取数据
  let data = if data_str != "" { data_str } else { "null" }
  // 解析 JSON 数据
  let json_data = @json.parse(data) catch {
    _ => {
      println("错误: 无效的 JSON 数据")
      return
    }
  }
  // 求值
  try {
    let result = @moonata.evaluate(expr, json_data)
    println(result.stringify(indent=2))
  } catch {
    e => println("错误: \{to_repr(e)}")
  }
}

///|
fn print_usage() -> Unit {
  println("Moonata - JSONata 查询/转换语言 (MoonBit 实现)")
  println("")
  println("用法:")
  println("  moonata '<expr>'                    对 null 求值表达式")
  println("  moonata '<expr>' --data '<json>'    对指定 JSON 数据求值")
  println("  moonata --help                      显示此帮助")
  println("")
  println("示例:")
  println("  moonata '1 + 2'")
  println("  moonata 'name' --data '{\"name\":\"Alice\"}'")
  println(
    "  moonata '$sum($.items.price)' --data '{\"items\":[{\"price\":10},{\"price\":20}]}'",
  )
}
