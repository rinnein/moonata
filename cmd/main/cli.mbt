///|
/// Moonata CLI 配置：由 `parse_cli_config` 从 argv 解析得到的类型化配置。
///
/// 仅在 `cmd/main` 可执行包内使用，不属于 facade 公共 API。
/// 参数解析通过 `moonbitlang/core/argparse` 完成，本结构体仅承载 argparse
/// 解析后的强类型字段，供 `main.mbt` 装配调用。
struct CliConfig {
  expr : String
  data : String? // 内联 JSON 字符串
  file : String? // JSON 文件路径
  expr_file : String? // 表达式文件路径（WTF-8 解码，保留 lone surrogate）
  no_data : Bool // 使用 undefined 上下文（对齐 dataset:null → undefined 语义）
  max_depth : Int // -1 表示未设置；>0 时传入求值器限制递归深度
  stack : Int? // guardrails stack 选项（>0 启用 D1011）
  timeout : Int? // guardrails timeout 选项（毫秒，>0 启用 D1012）
  sequence : Int? // guardrails sequence 选项（>0 启用 D2015）
} derive(Eq)

///|
/// 构建 Moonata CLI 的 `@argparse.Command` 声明。
///
/// 命令形状：
/// ```text
/// moonata [options] <expr>
/// ```
///
/// - 位置参数 `<expr>`：JSONata 表达式，启用 `allow_hyphen_values` 以便接受
///   以 `-` 开头的表达式（如 `-1 + 2`）。
/// - `--data <json>`：内联 JSON 数据。
/// - `--file <path>`：JSON 文件路径。
/// - `--expr-file <path>`：表达式文件路径（WTF-8 解码，保留 lone surrogate）。
/// - `--max-depth <n>`：最大递归深度（对齐 jsonata-js test runner 的 maxDepth）。
/// - `--stack <n>`：guardrails stack 选项（超限抛 D1011，对齐 JSONata 官方文档）。
/// - `--timeout <ms>`：guardrails timeout 选项（毫秒，超限抛 D1012）。
/// - `--sequence <n>`：guardrails sequence 选项（超限抛 D2015）。
/// - `--no-data`：使用 undefined 上下文求值。
/// - `--help` / `-h`：由 argparse 内建提供。
fn cli_command() -> @argparse.Command {
  @argparse.Command(
    "moonata",
    about="Moonata - JSONata 查询/转换语言 (MoonBit 实现)",
    options=[
      @argparse.OptionArg(
        "data",
        long="data",
        about="对指定 JSON 数据求值（内联 JSON 字符串）",
      ),
      @argparse.OptionArg(
        "file",
        long="file",
        about="对指定 JSON 文件求值（文件路径）",
      ),
      @argparse.OptionArg(
        "expr-file",
        long="expr-file",
        about="从文件读取表达式（WTF-8 解码，保留 lone surrogate）",
      ),
      @argparse.OptionArg(
        "max-depth",
        long="max-depth",
        about="指定最大递归深度（对齐 jsonata-js test runner）",
      ),
      @argparse.OptionArg(
        "stack",
        long="stack",
        about="guardrails: 最大递归深度（超限抛 D1011）",
      ),
      @argparse.OptionArg(
        "timeout",
        long="timeout",
        about="guardrails: 最大执行时间毫秒（超限抛 D1012）",
      ),
      @argparse.OptionArg(
        "sequence",
        long="sequence",
        about="guardrails: 最大序列长度（超限抛 D2015）",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "no-data",
        long="no-data",
        about="对 undefined 上下文求值（对齐 dataset:null → undefined 语义）",
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "expr",
        about="JSONata 表达式（与 --expr-file 互斥；二者均无时显示帮助）",
        num_args=@argparse.ValueRange::ValueRange(lower=0, upper=1),
        allow_hyphen_values=true,
      ),
    ],
    arg_required_else_help=true,
  )
}

///|
/// 将 argv 解析为 `CliConfig`，直接基于 `@argparse.parse` 完成。
///
/// - 由 argparse 处理 `--help`/`-h`（打印帮助并 exit 0）与参数校验错误
///   （抛出已格式化的 `ArgError`，调用方可 catch 后直接打印）。
/// - `--max-depth` / `--stack` / `--timeout` / `--sequence` 的整型校验由本函数完成，
///   非法值抛出 `Failure`。
fn parse_cli_config(argv : ArrayView[String]) -> CliConfig raise {
  let matches = @argparse.parse(cli_command(), argv~)
  let values : Map[String, Array[String]] = matches.values
  // 位置参数 expr 由 argparse 保证存在（single() + arg_required_else_help）
  let expr = match values.get("expr") {
    Some(arr) if !arr.is_empty() => arr[0]
    _ => ""
  }
  let data = match values.get("data") {
    Some([d, ..]) => Some(d)
    _ => None
  }
  let file = match values.get("file") {
    Some([f, ..]) => Some(f)
    _ => None
  }
  let expr_file = match values.get("expr-file") {
    Some([f, ..]) => Some(f)
    _ => None
  }
  let max_depth = match values.get("max-depth") {
    Some([s, ..]) =>
      @string.parse_int(s) catch {
        _ => fail("--max-depth 需要整数参数")
      }
    _ => -1
  }
  let stack = match values.get("stack") {
    Some([s, ..]) =>
      Some(
        @string.parse_int(s) catch {
          _ => fail("--stack 需要整数参数")
        },
      )
    _ => None
  }
  let timeout = match values.get("timeout") {
    Some([s, ..]) =>
      Some(
        @string.parse_int(s) catch {
          _ => fail("--timeout 需要整数参数")
        },
      )
    _ => None
  }
  let sequence = match values.get("sequence") {
    Some([s, ..]) =>
      Some(
        @string.parse_int(s) catch {
          _ => fail("--sequence 需要整数参数")
        },
      )
    _ => None
  }
  let no_data = matches.flags.get("no-data").unwrap_or(false)
  { expr, data, file, expr_file, no_data, max_depth, stack, timeout, sequence }
}
