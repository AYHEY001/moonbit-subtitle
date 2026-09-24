///|
/// 命令行入口。
///
/// 这个工具只做本地处理：不联网、不上传文件。字幕本身经常涉及未公开的素材，
/// 在线转换站点得把文件传上去，这是不用的理由。
///
/// 子命令的实现在 commands.mbt 里，这里只管两件事：定义命令、分发。

///|
/// 取命令行参数，去掉 argv[0]。
///
/// `@env.args()` 在 wasm / native / js 三个目标上都会把可执行文件自己放在首位
/// （实测 wasm 下是 main.wasm 的绝对路径），而 argparse 要的是程序名之后的那一段。
fn cli_args() -> Array[String] {
  let raw = @env.args()
  let out : Array[String] = []
  let mut i = 1
  while i < raw.length() {
    out.push(raw[i])
    i = i + 1
  }
  out
}

///|
/// 命令与参数定义。
fn build_command() -> @argparse.Command {
  @argparse.Command(
    "moonbit-subtitle",
    about="本地处理 SRT / WebVTT 字幕：查看信息、平移时间轴、规范化、格式转换、剥标记",
    version="0.1.0",
    subcommands=[
      @argparse.Command(
        "info",
        about="打印条数、总时长与首末时间",
        positionals=[@argparse.PositionArg("file", about="输入字幕文件")],
      ),
      @argparse.Command(
        "shift",
        about="整体平移时间轴，例：shift a.srt -1.5s",
        positionals=[
          @argparse.PositionArg("file", about="输入字幕文件"),
          // allow_hyphen_values：平移量以减号开头（-500），
          // 不打开这个开关，argparse 会把它当成未知选项直接报错
          @argparse.PositionArg(
            "offset",
            about="平移量：-500 是毫秒，也可以写 1.5s / 2m",
            allow_hyphen_values=true,
          ),
        ],
        options=[
          @argparse.OptionArg(
            "output",
            short='o',
            long="output",
            about="输出文件；不给就打到标准输出",
          ),
        ],
      ),
      @argparse.Command(
        "normalize",
        about="按开始时间排序、序号重排、合并重叠",
        positionals=[@argparse.PositionArg("file", about="输入字幕文件")],
        options=[
          @argparse.OptionArg(
            "output",
            short='o',
            long="output",
            about="输出文件；不给就打到标准输出",
          ),
        ],
      ),
      @argparse.Command(
        "convert",
        about="格式转换，例：convert a.srt --to vtt",
        positionals=[@argparse.PositionArg("file", about="输入字幕文件")],
        options=[
          @argparse.OptionArg(
            "to",
            long="to",
            about="目标格式：srt 或 vtt",
            required=true,
          ),
          @argparse.OptionArg(
            "output",
            short='o',
            long="output",
            about="输出文件；不给就打到标准输出",
          ),
        ],
      ),
      @argparse.Command(
        "strip",
        about="剥掉正文里的排版标记，例：strip a.vtt",
        positionals=[@argparse.PositionArg("file", about="输入字幕文件")],
        options=[
          @argparse.OptionArg(
            "output",
            short='o',
            long="output",
            about="输出文件；不给就打到标准输出",
          ),
        ],
      ),
    ],
  )
}

///|
fn main {
  let command = build_command()
  try {
    let matches = command.parse(argv=cli_args(), env=Map([]))
    match matches.subcommand {
      Some((name, sub)) => run(name, sub)
      // 没给子命令不算错误，直接把用法打出来：clap 那一类工具都是这个惯例
      None => println(command.render_help())
    }
  } catch {
    err => {
      eprintln(err)
      // 用法错误用 2，跟 grep / diff 这些老工具保持一致，
      // 好让脚本里能区分"参数写错了"和"文件处理不了"
      @sys.exit(2)
    }
  }
}
