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
  if tokens.length() == 0 { "" } else { tokens[0].to_owned() }
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
/// 解析时间行，返回（开始毫秒，结束毫秒）。
///
/// 时间戳怎么解析由调用方传进来：SRT 用 `parse_timestamp`（必须带小时），
/// WebVTT 用 `parse_vtt_timestamp`（小时可省）。除了这一点，两种格式的时间行
/// 处理完全一样，所以只写一份。
fn parse_time_range(
  line : StringView,
  parse : (String) -> Int?,
) -> Result[(Int, Int), String] {
  let parts = line.split("-->").to_array()
  if parts.length() != 2 {
    return Err("时间行缺少 \"-->\"：" + line.to_owned())
  }
  let right_text = first_token(parts[1])
  match (parse(parts[0].trim().to_owned()), parse(right_text)) {
    (Some(start), Some(end)) =>
      if end < start {
        Err("结束时间早于开始时间：" + line.to_owned())
      } else {
        Ok((start, end))
      }
    (None, _) => Err("开始时间无法解析：" + parts[0].to_owned())
    (_, None) => Err("结束时间无法解析：" + right_text)
  }
}

test "strip_bom 只去掉开头的 BOM" {
  inspect(strip_bom("\u{FEFF}abc"), content="abc")
  inspect(strip_bom("abc"), content="abc")
  inspect(strip_bom("a\u{FEFF}b"), content="a\u{FEFF}b")
}

test "normalize_newlines 把 CRLF 和单独 CR 都归一" {
  inspect(normalize_newlines("a\r\nb\rc\nd"), content="a\nb\nc\nd")
}

test "split_blocks 忽略多余空行" {
  let lines = "a\n\n\nb\n\nc\n".split("\n").to_array()
  inspect(split_blocks(lines).length(), content="3")
}

test "split_blocks 空输入返回零块" {
  inspect(split_blocks("\n\n\n".split("\n").to_array()).length(), content="0")
}

test "first_token 只取第一个词" {
  inspect(first_token(" 00:00:04,000 X1:100 "), content="00:00:04,000")
  inspect(first_token("   "), content="")
}

test "join_body 保留正文换行" {
  let lines = "x\na\nb".split("\n").to_array()
  inspect(join_body(lines, 1), content="a\nb")
}
