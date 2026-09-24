///|
/// 子命令的实现，加上文件读写与几处路径检查。
///
/// 一条原则：**报错必须带上下文**。命令行工具一次只处理一个文件，
/// 出错时是"哪个文件的哪一块不对"，比错误类型本身有用得多。
/// 库那层抛上来的错误信息里已经有块号，这里补上文件名。

///|
/// 子命令的产出：要写出去的文本，加目标路径（`None` 表示打到标准输出）。
struct Output {
  text : String
  path : String?
}

///|
/// 读进来的一份字幕，附带它原本是哪种格式。
/// shift / normalize 按原格式写回 —— 拿 WebVTT 进去、吐 SRT 出来会很意外。
struct Loaded {
  subtitle : @lib.Subtitle
  format : String
}

///|
/// 分发子命令。用法错误（exit 2）在 main 里处理，
/// 这里的失败都是"文件本身有问题"（exit 1）。
fn run(name : String, sub : @argparse.Matches) -> Unit {
  let result = match name {
    "info" => cmd_info(sub)
    "shift" => cmd_shift(sub)
    "normalize" => cmd_normalize(sub)
    "convert" => cmd_convert(sub)
    _ => Err("未知子命令：" + name)
  }
  match result {
    Ok(output) =>
      match emit(output) {
        Ok(_) => ()
        Err(msg) => {
          eprintln("错误：" + msg)
          @sys.exit(1)
        }
      }
    Err(msg) => {
      eprintln("错误：" + msg)
      @sys.exit(1)
    }
  }
}

///|
/// 取参数值。位置参数和选项在 argparse 里都存在 `values`，
/// 键名就是声明时用的名字。
fn value_of(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some(values) => if values.length() > 0 { Some(values[0]) } else { None }
    None => None
  }
}

///|
/// 取必填参数。argparse 只管选项标了 `required` 的情况，
/// 位置参数缺了要自己拦。
fn need_value(matches : @argparse.Matches, name : String) -> Result[String, String] {
  match value_of(matches, name) {
    Some(v) => Ok(v)
    None => Err("缺少参数：" + name)
  }
}

///|
/// 按扩展名判断格式，认不出来返回 `None`。
fn format_from_path(path : String) -> String? {
  let lower = path.to_lower()
  if lower.has_suffix(".vtt") {
    Some("vtt")
  } else if lower.has_suffix(".srt") {
    Some("srt")
  } else {
    None
  }
}

///|
/// 目标格式的写法宽容一点：`webvtt` 和 `subrip` 都收。
fn target_format(text : String) -> String? {
  let lower = text.to_lower()
  if lower == "vtt" || lower == "webvtt" {
    Some("vtt")
  } else if lower == "srt" || lower == "subrip" {
    Some("srt")
  } else {
    None
  }
}

///|
/// 路径比较用的规范形式：Windows 上大小写不敏感，反斜杠和正斜杠两种写法都认。
fn normalize_path(path : String) -> String {
  path.replace_all(old="\\", new="/").to_lower()
}

///|
/// 两个路径是不是同一个文件。
fn same_path(a : String, b : String) -> Bool {
  normalize_path(a) == normalize_path(b)
}

///|
/// 读文件。编码显式写出来，让"读进来乱码"这类问题有一个明确的说法，
/// 而不是靠平台默认值碰运气。
///
/// 注意这里写的是 `utf8` 而不是 `utf-8`：`moonbitlang/x/fs` 只认前者，
/// 写成 `utf-8` 会直接抛 `Unsupported encoding`。
fn read_text(path : String) -> Result[String, String] {
  try {
    Ok(@fs.read_file_to_string(path, encoding="utf8"))
  } catch {
    @fs.IOError(msg) => Err("读不了 " + path + "：" + msg)
  }
}

///|
/// 读文件、判断格式、解析。三步里任何一步失败都带上文件名。
fn load(path : String) -> Result[Loaded, String] {
  let text = match read_text(path) {
    Ok(t) => t
    Err(msg) => return Err(msg)
  }
  let format = match format_from_path(path) {
    Some(f) => f
    None =>
      // 扩展名不认识（比如 .txt）就看内容：WebVTT 强制要求文件头
      if text.has_prefix("WEBVTT") || text.has_prefix("\u{FEFF}WEBVTT") {
        "vtt"
      } else {
        "srt"
      }
  }
  let subtitle = if format == "vtt" {
    match @lib.parse_vtt(text) {
      Ok(s) => s
      Err(msg) => return Err(path + "：" + msg)
    }
  } else {
    match @lib.parse_srt(text) {
      Ok(s) => s
      Err(msg) => return Err(path + "：" + msg)
    }
  }
  Ok({ subtitle, format, })
}

///|
/// 按格式渲染。
fn render_as(subtitle : @lib.Subtitle, format : String) -> String {
  if format == "vtt" {
    subtitle.render_vtt()
  } else {
    subtitle.render_srt()
  }
}

///|
/// 首末时间：取最小的开始与最大的结束。
///
/// 不直接看第一条和最后一条：手工改过的字幕文件里顺序经常是乱的，
/// 报出来的总时长必须是真正的最大结束时间，否则比不报还坏。
fn span_of(cues : Array[@lib.Cue]) -> (Int, Int) {
  let mut min_start = 0
  let mut max_end = 0
  if cues.length() > 0 {
    min_start = cues[0].start_ms
    max_end = cues[0].end_ms
    let mut i = 1
    while i < cues.length() {
      if cues[i].start_ms < min_start {
        min_start = cues[i].start_ms
      }
      if cues[i].end_ms > max_end {
        max_end = cues[i].end_ms
      }
      i = i + 1
    }
  }
  (min_start, max_end)
}

///|
/// 组一个输出，顺手拦掉"输出到输入文件本身"。
/// 那等于把原文件覆盖掉，而这一步之前没有任何备份。
fn make_output(input : String, text : String, path : String?) -> Result[Output, String] {
  match path {
    Some(p) =>
      if same_path(p, input) {
        Err("输出文件跟输入文件是同一个（" + p + "）。换个路径写，或者写到别处再替换")
      } else {
        Ok({ text, path: Some(p), })
      }
    None => Ok({ text, path: None, })
  }
}

///|
/// 输出。给了 `-o` 就写文件，否则打到标准输出。
///
/// 标准输出这条路要把结尾的换行去掉再交给 println，
/// 不然会多出一个空行 —— 重定向到文件时尤其明显。
fn emit(output : Output) -> Result[Unit, String] {
  match output.path {
    Some(path) =>
      try {
        @fs.write_string_to_file(path, output.text, encoding="utf8")
        Ok(())
      } catch {
        @fs.IOError(msg) => Err("写不了 " + path + "：" + msg)
      }
    None => {
      match output.text.strip_suffix("\n") {
        Some(trimmed) => println(trimmed.to_owned())
        None => println(output.text)
      }
      Ok(())
    }
  }
}

///|
/// 看信息：条数、总时长、首末时间。
fn cmd_info(sub : @argparse.Matches) -> Result[Output, String] {
  let file = match need_value(sub, "file") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let loaded = match load(file) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let cues = loaded.subtitle.cues
  let (min_start, max_end) = span_of(cues)
  let text = "文件：" +
    file +
    "\n" +
    "格式：" +
    (if loaded.format == "vtt" { "WebVTT" } else { "SRT" }) +
    "\n" +
    "条数：" +
    cues.length().to_string() +
    "\n" +
    "总时长：" +
    (if cues.length() == 0 {
      "—"
    } else {
      @lib.format_timestamp(max_end - min_start)
    }) +
    "\n" +
    "首条：" +
    (if cues.length() == 0 {
      "—"
    } else {
      @lib.format_timestamp(min_start)
    }) +
    "\n" +
    "末条：" +
    (if cues.length() == 0 {
      "—"
    } else {
      @lib.format_timestamp(max_end)
    }) +
    "\n"
  Ok({ text, path: None, })
}

///|
/// 平移时间轴。
fn cmd_shift(sub : @argparse.Matches) -> Result[Output, String] {
  let file = match need_value(sub, "file") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let offset_text = match need_value(sub, "offset") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let offset = match @lib.parse_duration_ms(offset_text) {
    Some(v) => v
    None =>
      return Err(
        "平移量看不懂：" + offset_text + "。写 -500 表示毫秒，也可以写 -1.5s、2m",
      )
  }
  let loaded = match load(file) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  make_output(
    file,
    render_as(loaded.subtitle.shift(offset), loaded.format),
    value_of(sub, "output"),
  )
}

///|
/// 规范化：排序、合并重叠、序号重排。
fn cmd_normalize(sub : @argparse.Matches) -> Result[Output, String] {
  let file = match need_value(sub, "file") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let loaded = match load(file) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  // 合并之后条数变少、序号会断开，所以合成完再规范化一次，把序号接上
  let normalized = loaded.subtitle.normalize().merge_overlaps().normalize()
  make_output(
    file,
    render_as(normalized, loaded.format),
    value_of(sub, "output"),
  )
}

///|
/// 格式转换。
fn cmd_convert(sub : @argparse.Matches) -> Result[Output, String] {
  let file = match need_value(sub, "file") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let to_text = match need_value(sub, "to") {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  let target = match target_format(to_text) {
    Some(v) => v
    None => return Err("--to 只认 srt 或 vtt，收到的是：" + to_text)
  }
  let loaded = match load(file) {
    Ok(v) => v
    Err(msg) => return Err(msg)
  }
  make_output(
    file,
    render_as(loaded.subtitle, target),
    value_of(sub, "output"),
  )
}

test "format_from_path 认得出两种扩展名" {
  debug_inspect(format_from_path("a.srt"), content="Some(\"srt\")")
  debug_inspect(format_from_path("a.VTT"), content="Some(\"vtt\")")
  debug_inspect(format_from_path("D:\\sub\\b.vtt"), content="Some(\"vtt\")")
  debug_inspect(format_from_path("a.txt"), content="None")
}

test "target_format 宽容常见的几种写法" {
  debug_inspect(target_format("vtt"), content="Some(\"vtt\")")
  debug_inspect(target_format("WebVTT"), content="Some(\"vtt\")")
  debug_inspect(target_format("srt"), content="Some(\"srt\")")
  debug_inspect(target_format("SubRip"), content="Some(\"srt\")")
  debug_inspect(target_format("ass"), content="None")
}

test "same_path 忽略大小写与斜杠方向" {
  inspect(same_path("D:\\sub\\a.srt", "d:/sub/A.SRT"), content="true")
  inspect(same_path("a.srt", "b.srt"), content="false")
}

test "normalize_path 统一斜杠与大小写" {
  inspect(normalize_path("D:\\Sub\\A.SRT"), content="d:/sub/a.srt")
}
