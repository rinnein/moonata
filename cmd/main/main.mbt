///|
/// Moonata CLI 入口（native 目标）。
///
/// 用法：
///   moonata '<expr>'                    # 对 null 求值
///   moonata '<expr>' --data '<json>'   # 对指定 JSON 数据求值
///   moonata '<expr>' --file '<file>'   # 对指定 JSON 文件求值
///   moonata '<expr>' --no-data         # 对 undefined 上下文求值
///   moonata '<expr>' --max-depth <n>   # 指定最大递归深度（对齐 jsonata-js test runner）
///   moonata --expr-file '<file>'       # 从文件读取表达式（WTF-8 解码，保留 lone surrogate）
///   moonata --help                      # 显示帮助
///
/// `--expr-file` 读取文件原始字节并以 WTF-8 解码为 MoonBit 字符串，使
/// `function-encodeUrl/case002` 等 case 中通过 `surrogatepass` 写入的
/// `0xED 0xA0 0x80`（U+D800 的 WTF-8 编码）能被还原为 lone surrogate，
/// 让 `$encodeUrl`/`$encodeUrlComponent` 的 `reject_url_surrogate` 检测生效。
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  // 解析参数
  let mut expr = ""
  let mut expr_from_file = ""
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
      "--expr-file" => {
        i += 1
        if i < args.length() {
          let file_path = args[i]
          let file_content = @fs.read_file(file_path) catch {
            _ => {
              println("错误: 无法读取表达式文件 \{file_path}")
              return
            }
          }
          // 以原始字节读取，使用 WTF-8 解码保留 lone surrogate
          expr_from_file = wtf8_decode(file_content.binary())
        }
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
  // --expr-file 优先于位置参数
  if expr_from_file != "" {
    expr = expr_from_file
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
      //
      // 关键：使用 `println_wtf8` 输出原始 message，保留 lone surrogate
      // （U+D800–U+DFFF）的 WTF-8 字节序列 `0xED 0xA0-0xBF 0x80-0xBF`。
      // MoonBit 标准 `println` 使用严格 UTF-8 编码，会把 lone surrogate
      // 替换/重映射为其他字符，使 `function-encodeUrl/case002` 等 case 中
      // audit 脚本无法在 haystack 中匹配到 `value: "\uD800"` 子串。
      let code = @error.JsonataError::error_code(e)
      let msg = @error.JsonataError::error_message(e)
      match code {
        Some(c) => println_wtf8("错误: \{c}: \{msg}")
        None => println_wtf8("错误: \{msg}")
      }
      // Debug repr 行使用标准 println（人工排查用，不需要保留 surrogate）；
      // `to_repr` 返回 `@debug.Repr`，通过 `@debug.render` 转为字符串后输出
      println(@debug.render(to_repr(e)))
    }
  }
}

///|
/// 打印用法信息。
fn print_usage() -> Unit {
  println("Moonata - JSONata 查询/转换语言 (MoonBit 实现)")
  println("")
  println("用法:")
  println("  moonata '<expr>'                    对 null 求值表达式")
  println("  moonata '<expr>' --data '<json>'    对指定 JSON 数据求值")
  println("  moonata '<expr>' --file '<file>'    对指定 JSON 文件求值")
  println("  moonata '<expr>' --no-data          对 undefined 上下文求值")
  println("  moonata '<expr>' --max-depth <n>    指定最大递归深度")
  println(
    "  moonata --expr-file '<file>'        从文件读取表达式 (WTF-8 解码)",
  )
  println("  moonata --help                      显示此帮助")
  println("")
  println("示例:")
  println("  moonata '1 + 2'")
  println("  moonata 'name' --data '{\"name\":\"Alice\"}'")
  println(
    "  moonata '$sum($.items.price)' --data '{\"items\":[{\"price\":10},{\"price\":20}]}'",
  )
}

///|
/// 将原始字节按 WTF-8 解码为 MoonBit 字符串。
///
/// WTF-8 是 UTF-8 的超集：允许 3 字节序列 `0xED 0xA0-0xBF 0x80-0xBF` 编码
/// Unicode surrogate codepoint（U+D800–U+DFFF），用于在字符串中保留 lone
/// surrogate。MoonBit 运行时的 argv 解码使用严格 UTF-8，会把这些序列替换为
/// U+FFFD；通过 `--expr-file` 读取原始字节并以 WTF-8 解码可恢复 surrogate，
/// 让 `reject_url_surrogate` 在 `function-encodeUrl/case002` 等用例中生效。
///
/// 遇到非法字节序列时，与 `@encoding/utf8.decode_lossy` 一致替换为 U+FFFD。
fn wtf8_decode(bytes : Bytes) -> String {
  let sb = StringBuilder::new()
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i].to_int()
    if b < 0x80 {
      // ASCII
      sb.write_char(Int::unsafe_to_char(b))
      i += 1
    } else if b < 0xC2 {
      // 0x80-0xBF: 孤立 continuation byte；0xC0/0xC1: overlong 2-byte
      sb.write_char('\uFFFD')
      i += 1
    } else if b < 0xE0 {
      // 2-byte sequence
      if i + 1 >= n || (bytes[i + 1].to_int() & 0xC0) != 0x80 {
        sb.write_char('\uFFFD')
        i += 1
      } else {
        let c = ((b & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
        sb.write_char(Int::unsafe_to_char(c))
        i += 2
      }
    } else if b < 0xF0 {
      // 3-byte sequence
      if i + 2 >= n {
        sb.write_char('\uFFFD')
        i += 1
      } else {
        let b1 = bytes[i + 1].to_int()
        let b2 = bytes[i + 2].to_int()
        if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 {
          sb.write_char('\uFFFD')
          i += 1
        } else if b == 0xED && b1 >= 0xA0 && b1 <= 0xBF {
          // WTF-8 surrogate: 0xED 0xA0-0xBF 0x80-0xBF → U+D800-U+DFFF
          // 这是与严格 UTF-8 的关键差异：保留 lone surrogate 而非替换为 U+FFFD
          let c = ((b & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
          sb.write_char(Int::unsafe_to_char(c))
          i += 3
        } else if (b == 0xE0 && b1 < 0xA0) || (b == 0xED && b1 > 0x9F) {
          // 严格 UTF-8: overlong 3-byte (E0 < A0) 或 surrogate (ED > 9F) 非法；
          // WTF-8 中 ED A0-BF 已在上面处理，这里只剩 ED 80-9F（保留为非法）
          sb.write_char('\uFFFD')
          i += 1
        } else {
          let c = ((b & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
          sb.write_char(Int::unsafe_to_char(c))
          i += 3
        }
      }
    } else if b < 0xF5 {
      // 4-byte sequence
      if i + 3 >= n {
        sb.write_char('\uFFFD')
        i += 1
      } else {
        let b1 = bytes[i + 1].to_int()
        let b2 = bytes[i + 2].to_int()
        let b3 = bytes[i + 3].to_int()
        if (b1 & 0xC0) != 0x80 || (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
          sb.write_char('\uFFFD')
          i += 1
        } else if (b == 0xF0 && b1 < 0x90) || (b == 0xF4 && b1 > 0x8F) {
          // overlong 4-byte (F0 < 90) 或 > U+10FFFF (F4 > 8F)
          sb.write_char('\uFFFD')
          i += 1
        } else {
          let c = ((b & 0x07) << 18) |
            ((b1 & 0x3F) << 12) |
            ((b2 & 0x3F) << 6) |
            (b3 & 0x3F)
          sb.write_char(Int::unsafe_to_char(c))
          i += 4
        }
      }
    } else {
      // 0xF5-0xFF: 非法 leading byte
      sb.write_char('\uFFFD')
      i += 1
    }
  }
  sb.to_string()
}

///|
/// 将 MoonBit 字符串按 WTF-8 编码为字节序列。
///
/// 与 `@encoding/utf8.encode` 的差异：lone surrogate（U+D800–U+DFFF）按
/// 3 字节序列 `0xED 0xA0-0xBF 0x80-0xBF` 编码（WTF-8 扩展），而非被
/// 替换为 U+FFFD。这使 `function-encodeUrl/case002` 等 case 中 audit
/// 脚本能在 stdout 字节流中匹配到 `value: "\uD800"` 子串。
fn wtf8_encode(s : String) -> Bytes {
  let buf = @buffer.Buffer()
  for c in s {
    let code = c.to_int()
    if code < 0x80 {
      buf.write_byte(code.to_byte())
    } else if code < 0x800 {
      buf.write_byte((0xC0 | (code >> 6)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    } else if code >= 0xD800 && code <= 0xDFFF {
      // WTF-8 surrogate: 0xED 0xA0-0xBF 0x80-0xBF
      buf.write_byte((0xED).to_byte())
      buf.write_byte((0xA0 | ((code >> 6) & 0x3F)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    } else if code < 0x10000 {
      buf.write_byte((0xE0 | (code >> 12)).to_byte())
      buf.write_byte((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    } else {
      buf.write_byte((0xF0 | (code >> 18)).to_byte())
      buf.write_byte((0x80 | ((code >> 12) & 0x3F)).to_byte())
      buf.write_byte((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    }
  }
  buf.to_bytes()
}

///|
/// 以 WTF-8 编码输出字符串到 stdout，保留 lone surrogate。
async fn println_wtf8(s : String) -> Unit {
  let bytes = wtf8_encode(s)
  // 直接写两次：内容 + 换行，避免 Bytes concat 的额外依赖
  @stdio.stdout.write(bytes)
  @stdio.stdout.write(b"\n")
}
