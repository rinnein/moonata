///|
/// Moonata CLI 配置：由 `parse_cli_config` 从 argv 解析得到的类型化配置。
///
/// 遵循 `moonbitlang/moonbit-docs` 的 cli-quickstart 模式——将参数解析与
/// 业务逻辑放在库包中，保持 `cmd/main` 仅做装配。
pub struct CliConfig {
  expr : String
  data : String? // 内联 JSON 字符串
  file : String? // JSON 文件路径
  no_data : Bool // 使用 undefined 上下文（对齐 dataset:null → undefined 语义）
  max_depth : Int // -1 表示未设置；>0 时传入求值器限制递归深度
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
/// - `--max-depth <n>`：最大递归深度（对齐 jsonata-js test runner 的 maxDepth）。
/// - `--no-data`：使用 undefined 上下文求值。
/// - `--help` / `-h`：由 argparse 内建提供。
pub fn cli_command() -> @argparse.Command {
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
        "max-depth",
        long="max-depth",
        about="指定最大递归深度（对齐 jsonata-js test runner）",
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
        about="JSONata 表达式",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
    ],
    arg_required_else_help=true,
  )
}

///|
/// 将 argv 解析为 `CliConfig`。
///
/// - 由 argparse 处理 `--help`/`-h`（打印帮助并 exit 0）与参数校验错误
///   （抛出已格式化的 `ArgError`，调用方可 catch 后直接打印）。
/// - `--max-depth` 的整型校验由本函数完成，非法值抛出 `Failure`。
pub fn parse_cli_config(argv : ArrayView[String]) -> CliConfig raise {
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
  let max_depth = match values.get("max-depth") {
    Some([s, ..]) =>
      @string.parse_int(s) catch {
        _ => fail("--max-depth 需要整数参数")
      }
    _ => -1
  }
  let no_data = matches.flags.get("no-data").unwrap_or(false)
  { expr, data, file, no_data, max_depth }
}
