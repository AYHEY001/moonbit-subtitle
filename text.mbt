///|
/// 文本预处理与分块，SRT 和 WebVTT 两套解析共用。
///
/// 这里放的都是"跟具体格式无关"的东西：清 BOM、统一换行、判断行类型、
/// 按空行切块、拼正文。格式各自的规则（时间戳长什么样、哪些块要跳过）
/// 留在 srt.mbt 和 vtt.mbt 里。

///|
/// 去掉开头的 UTF-8 BOM。BOM 是文件写入方留下的，
/// 不清掉的话第一条字幕的序号行会变成 `\u{FEFF}1`，数字校验就过不了。
fn strip_bom(input : String) -> String {
  match input.strip_prefix("\u{FEFF}") {
    Some(rest) => rest.to_owned()
    None => input
  }
}

///|
/// 换行统一成 LF。
/// 顺序不能反：先处理 `\r\n`，否则后面那条规则会把 `\r\n` 拆成两个 `\n`，
/// 每条字幕之间会多出一个空块。
fn normalize_newlines(input : String) -> String {
  input.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// 空行，或者只有空格和制表符的行。
fn is_blank_line(line : StringView) -> Bool {
  line.trim().is_empty()
}

///|
/// 序号行：去掉两端空白之后只剩数字，且不能为空。
/// 只认 ASCII 数字，全角数字和罗马数字都不算 —— 那些是正文。
fn is_index_line(line : StringView) -> Bool {
  let trimmed = line.trim()
  if trimmed.is_empty() {
    false
  } else {
    let mut ok = true
    for c in trimmed.iter() {
      if !c.is_ascii_digit() {
        ok = false
      }
    }
    ok
  }
}

///|
/// 时间行：必须带箭头。SRT 和 WebVTT 用的是同一个箭头。
fn is_time_line(line : StringView) -> Bool {
  line.contains("-->")
}

///|
/// 按空行把整份文件切成块。返回的每一块都是非空行组成的数组。
fn split_blocks(lines : Array[StringView]) -> Array[Array[StringView]] {
  let blocks : Array[Array[StringView]] = []
  let mut current : Array[StringView] = []
  for line in lines {
    if is_blank_line(line) {
      if current.length() > 0 {
        blocks.push(current)
        current = []
      }
    } else {
      current.push(line)
    }
  }
  if current.length() > 0 {
    blocks.push(current)
  }
  blocks
}

///|
/// 取从 `start` 开始的后半段。
/// 不用 `items[start:]` 这种切片写法：数组切片的语法在这版工具链上还没稳定，
/// 手写循环虽然多几行，但不依赖语言细节。
fn tail_from(items : Array[StringView], start : Int) -> Array[StringView] {
  let out : Array[StringView] = []
  let mut i = start
  while i < items.length() {
    out.push(items[i])
    i = i + 1
  }
  out
}

///|
/// 取第一个词。
/// 时间后面有时会跟着别的东西 —— SRT 的排版坐标 `X1:100 X2:500`，
/// WebVTT 的 `align:start position:10%` —— 真正的结束时间只是第一个词。
fn first_token(part : StringView) -> String {
  let tokens = part.trim().split(" ").to_array()
  if tokens.length() == 0 {
    ""
  } else {
    tokens[0].to_owned()
  }
}

///|
/// 取第一个词之后剩下的部分。
///
/// 时间行右侧的排版设置靠这个抓出来：`00:00:04,000 X1:100 X2:500`
/// 拿掉时间戳之后就是 `X1:100 X2:500`。
/// 中间连续的空白压成一个空格 —— 设置项之间本来也只该有一个空格。
fn rest_after_first_token(part : StringView) -> String {
  let tokens = part.trim().split(" ").to_array()
  if tokens.length() <= 1 {
    return ""
  }
  let out : Array[String] = []
  let mut i = 1
  while i < tokens.length() {
    if !tokens[i].trim().is_empty() {
      out.push(tokens[i].to_owned())
    }
    i = i + 1
  }
  out.join(" ").trim().to_owned()
}

///|
/// 把若干行正文拼成一条字幕的文本，行之间用换行连接。
/// 不从 `block[2:]` 这种切片写法入手，理由同 `tail_from`。
fn join_body(block : Array[StringView], from : Int) -> String {
  let mut body = ""
  let mut i = from
  while i < block.length() {
    if i > from {
      body = body + "\n"
    }
    body = body + block[i].to_owned()
    i = i + 1
  }
  body
}

///|
/// 解析时间行，返回（开始毫秒，结束毫秒，右侧排版设置原文）。
///
/// 时间戳怎么解析由调用方传进来：SRT 用 `parse_timestamp`（必须带小时），
/// WebVTT 用 `parse_vtt_timestamp`（小时可省）。除了这一点，两种格式的时间行
/// 处理完全一样，所以只写一份。
///
/// 第三个值是时间行右侧的原文 —— SRT 的 `X1:100 X2:500`、WebVTT 的
/// `align:start position:10%`，没有就是空串。这一版开始收着它，
/// 之前是读完就丢，转换一圈回来字幕位置会掉回播放器默认值。
fn parse_time_range(
  line : StringView,
  parse : (String) -> Int?,
) -> Result[(Int, Int, String), String] {
  let parts = line.split("-->").to_array()
  if parts.length() != 2 {
    return Err("时间行缺少 \"-->\"：" + line.to_owned())
  }
  let right_text = first_token(parts[1])
  let settings = rest_after_first_token(parts[1])
  match (parse(parts[0].trim().to_owned()), parse(right_text)) {
    (Some(start), Some(end)) =>
      if end < start {
        Err("结束时间早于开始时间：" + line.to_owned())
      } else {
        Ok((start, end, settings))
      }
    (None, _) => Err("开始时间无法解析：" + parts[0].to_owned())
    (_, None) => Err("结束时间无法解析：" + right_text)
  }
}

///|
/// 取设置里的键名：`align:start position:10%` → `["align", "position"]`。
/// 没有冒号的片段不算设置项，跳过 —— 时间行后面偶尔会跟一些自由文本。
fn setting_keys(settings : String) -> Array[String] {
  let keys : Array[String] = []
  for token in settings.split(" ").to_array() {
    let parts = token.split(":").to_array()
    if parts.length() >= 2 && !parts[0].trim().is_empty() {
      keys.push(parts[0].trim().to_owned())
    }
  }
  keys
}

///|
/// 这段设置的键名是不是全都落在一个白名单里，空设置不算。
fn all_keys_in(settings : String, allowed : Array[String]) -> Bool {
  let keys = setting_keys(settings)
  if keys.is_empty() {
    false
  } else {
    let mut ok = true
    for k in keys {
      let mut hit = false
      for a in allowed {
        if k == a {
          hit = true
        }
      }
      if !hit {
        ok = false
      }
    }
    ok
  }
}

///|
/// 这段设置是不是 WebVTT 的语法。
///
/// WebVTT 的 cue 设置键由规范固定，一共六个：`align` / `line` / `position` /
/// `region` / `size` / `vertical`。集合小且封闭，认起来可靠。
fn is_vtt_settings(settings : String) -> Bool {
  all_keys_in(settings, [
    "align", "line", "position", "region", "size", "vertical",
  ])
}

///|
/// 这段设置是不是 SRT 的坐标语法：`X1:100 Y1:20 X2:500 Y2:600`。
///
/// SRT 没有官方规范，这几个键是社区通行的写法（`SubRip` 里叫坐标）。
/// 与 WebVTT 的六个键完全没有交集，所以两种格式能靠键名区分开。
fn is_srt_settings(settings : String) -> Bool {
  all_keys_in(settings, ["X1", "X2", "Y1", "Y2"])
}

///|
test "strip_bom 只去掉开头的 BOM" {
  inspect(strip_bom("\u{FEFF}abc"), content="abc")
  inspect(strip_bom("abc"), content="abc")
  inspect(strip_bom("a\u{FEFF}b"), content="a\u{FEFF}b")
}

///|
test "normalize_newlines 把 CRLF 和单独 CR 都归一" {
  inspect(normalize_newlines("a\r\nb\rc\nd"), content="a\nb\nc\nd")
}

///|
test "split_blocks 忽略多余空行" {
  let lines = "a\n\n\nb\n\nc\n".split("\n").to_array()
  inspect(split_blocks(lines).length(), content="3")
}

///|
test "split_blocks 空输入返回零块" {
  inspect(split_blocks("\n\n\n".split("\n").to_array()).length(), content="0")
}

///|
test "first_token 只取第一个词" {
  inspect(first_token(" 00:00:04,000 X1:100 "), content="00:00:04,000")
  inspect(first_token("   "), content="")
}

///|
test "join_body 保留正文换行" {
  let lines = "x\na\nb".split("\n").to_array()
  inspect(join_body(lines, 1), content="a\nb")
}

///|
test "rest_after_first_token 取走时间戳之后的设置" {
  inspect(
    rest_after_first_token(" 00:00:04,000 X1:100 X2:500 "),
    content="X1:100 X2:500",
  )
  inspect(rest_after_first_token(" 00:00:04,000 "), content="")
  // 时间戳后面跟了不止一个空格，收完要压成一个
  inspect(rest_after_first_token(" 00:00:04,000  X1:100 "), content="X1:100")
}

///|
test "is_vtt_settings 认 WebVTT 的六个键" {
  inspect(is_vtt_settings("align:start"), content="true")
  inspect(is_vtt_settings("align:start position:10% line:0"), content="true")
  inspect(is_vtt_settings("X1:100"), content="false")
  // 空设置不算任何一种语法，交给调用方按"没有设置"处理
  inspect(is_vtt_settings(""), content="false")
  // 掺了一个不认识的键，就不是纯 WebVTT 语法了
  inspect(is_vtt_settings("align:start foo:1"), content="false")
}

///|
test "is_srt_settings 认坐标的四个键" {
  inspect(is_srt_settings("X1:100 X2:500"), content="true")
  inspect(is_srt_settings("X1:100 Y1:20 X2:500 Y2:600"), content="true")
  inspect(is_srt_settings("align:start"), content="false")
  inspect(is_srt_settings(""), content="false")
}
