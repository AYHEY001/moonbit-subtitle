///|
/// WebVTT 的解析与渲染。
///
/// 和 SRT 的差别，只列影响解析的几条：
///   - 文件必须以 `WEBVTT` 开头，后面可以跟说明文字，再跟若干元数据行
///     （`Kind: captions` / `Language: zh` 这类）
///   - 每个 cue 前面可以有一个标识行，内容是任意不含箭头的文本
///   - 时间戳的**小时可以省略**：`01:23.456` 就是 `00:01:23.456`
///   - 时间行右侧可以有排版设置：`align:start position:10%`
///   - `NOTE` 开头的块是注释，`STYLE` / `REGION` 开头的块是样式与区域定义，都不是字幕
///
/// 已知取舍，两处都不打算在 MVP 里做：
///   - 正文里的 `<b>` `<c.classname>` 这类标记按原样保留，不剥离。
///     剥离需要在渲染成 SRT 时再补一层清洗，属于另一个功能。
///   - cue 标识解析时读掉但不保存（`Cue` 里没有这个字段），
///     所以带标识的 VTT 转一圈回来标识会消失。渲染出来仍是合法 VTT。

///|
/// 解析 WebVTT 时间戳。两段式（`MM:SS.mmm`）时补一个零小时段，
/// 后面就完全走 SRT 那套逻辑 —— 两种格式的时间戳只差这一个规则。
fn parse_vtt_timestamp(raw : String) -> Int? {
  let trimmed = raw.trim().to_owned()
  if trimmed.split(":").to_array().length() == 2 {
    parse_timestamp("00:" + trimmed)
  } else {
    parse_timestamp(trimmed)
  }
}

///|
/// NOTE / STYLE / REGION 开头的块不是字幕。
///
/// 只认"整行等于这三个词"或者"后面跟一个空格"的写法。
/// 用 `has_prefix("NOTE")` 会误伤 —— 一句以 NOTES 开头的台词会被整块丢掉。
fn is_vtt_special_block(line : StringView) -> Bool {
  let trimmed = line.trim()
  trimmed.equal("NOTE") ||
  trimmed.has_prefix("NOTE ") ||
  trimmed.equal("STYLE") ||
  trimmed.has_prefix("STYLE ") ||
  trimmed.equal("REGION") ||
  trimmed.has_prefix("REGION ")
}

///|
/// 解析 WebVTT 文本。成功返回 `Subtitle`，失败返回错误说明。
///
/// 序号由解析顺序给出（1..n）：WebVTT 本身没有序号，而 `Subtitle` 里每条都要有个编号，
/// 拿到手就编好，后面渲染成 SRT 时直接能用。
pub fn parse_vtt(input : String) -> Result[Subtitle, String] {
  let text = normalize_newlines(strip_bom(input))
  let lines = text.split("\n").to_array()
  if lines.length() == 0 || !lines[0].trim().has_prefix("WEBVTT") {
    return Err("缺少 WEBVTT 头，第一行是：" + lines[0].to_owned())
  }
  let blocks = split_blocks(lines)
  let cues : Array[Cue] = []
  let mut block_no = 0
  for block in blocks {
    block_no = block_no + 1
    let mut content = block
    if block_no == 1 {
      // 第一块是文件头：WEBVTT 行，加上它后面可能有的元数据行。
      // 有些文件头后面不留空行、直接跟第一条 cue，所以只砍到第一个时间行之前。
      let mut head = 0
      while head < block.length() && !is_time_line(block[head]) {
        head = head + 1
      }
      if head >= block.length() {
        continue
      }
      content = tail_from(block, head)
    }
    if is_vtt_special_block(content[0]) {
      continue
    }
    // 标识行可以有也可以没有，时间行的位置因此不固定，得先找出来。
    let mut time_at = 0
    while time_at < content.length() && !is_time_line(content[time_at]) {
      time_at = time_at + 1
    }
    if time_at >= content.length() {
      return Err("第 " + block_no.to_string() + " 块：找不到时间行")
    }
    match parse_time_range(content[time_at], parse_vtt_timestamp) {
      Ok(range) => {
        let (start_ms, end_ms) = range
        cues.push({
          index: cues.length() + 1,
          start_ms,
          end_ms,
          text: join_body(content, time_at + 1),
        })
      }
      Err(msg) => return Err("第 " + block_no.to_string() + " 块：" + msg)
    }
  }
  Ok(Subtitle::from_cues(cues))
}

///|
/// 把毫秒格式化成 WebVTT 的时间戳：毫秒分隔符是句点，不是逗号。
fn format_vtt_timestamp(ms : Int) -> String {
  format_timestamp(ms).replace(old=",", new=".")
}

///|
/// 渲染成 WebVTT 文本。
///
/// 小时固定输出两位，即使整份文件都在一小时以内 —— 规范允许省略，
/// 但补全之后 SRT 和 WebVTT 的时间戳逐字对齐，肉眼比对时省事。
pub fn Subtitle::render_vtt(self : Subtitle) -> String {
  let blocks : Array[String] = []
  for c in self.cues {
    blocks.push(
      format_vtt_timestamp(c.start_ms) +
      " --> " +
      format_vtt_timestamp(c.end_ms) +
      "\n" +
      c.text,
    )
  }
  // 只剩头也是合法的 WebVTT（空字幕文件），别输出成空串
  if blocks.length() == 0 {
    "WEBVTT\n"
  } else {
    "WEBVTT\n\n" + blocks.join("\n\n") + "\n"
  }
}

///|
/// 一段标准的 WebVTT，用来做往返测试。
let sample_vtt : String =
  "WEBVTT\n\n00:00:01.000 --> 00:00:04.000\n第一行\n\n00:00:05.000 --> 00:00:08.000\n第二行\n"

test "parse_vtt 解析出两条字幕" {
  let s = match parse_vtt(sample_vtt) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues.length(), content="2")
  inspect(s.cues[0].start_ms, content="1000")
  inspect(s.cues[1].text, content="第二行")
}

test "parse_vtt 序号按顺序编好" {
  let s = match parse_vtt(sample_vtt) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[1].index, content="2")
}

test "parse_vtt 容忍 BOM 与 CRLF" {
  let text = "\u{FEFF}WEBVTT\r\n\r\n00:00:01.000 --> 00:00:04.000\r\n第一行\r\n\r\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues.length(), content="1")
  inspect(s.cues[0].text, content="第一行")
}

test "parse_vtt 允许省略小时" {
  let text = "WEBVTT\n\n01:23.456 --> 01:25.000\n一分钟处\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].start_ms, content="83456")
  inspect(s.cues[0].end_ms, content="85000")
}

test "parse_vtt 忽略 cue 标识行" {
  let text = "WEBVTT\n\nintro\n00:00:01.000 --> 00:00:04.000\n第一行\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues.length(), content="1")
  inspect(s.cues[0].text, content="第一行")
}

test "parse_vtt 忽略时间行右侧的排版设置" {
  let text = "WEBVTT\n\n00:00:01.000 --> 00:00:04.000 align:start position:10%\n第一行\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].end_ms, content="4000")
}

test "parse_vtt 跳过注释与样式块" {
  let text = (
    #|WEBVTT
    #|
    #|NOTE 这一条是注释
    #|
    #|STYLE
    #|::cue { color: yellow }
    #|
    #|00:00:01.000 --> 00:00:04.000
    #|第一行
    #|
  )
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues.length(), content="1")
  inspect(s.cues[0].start_ms, content="1000")
}

test "parse_vtt 不误伤以 NOTES 开头的台词" {
  let text = "WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nNOTES 这行是台词\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].text, content="NOTES 这行是台词")
}

test "parse_vtt 接受头之后不留空行的文件" {
  let text = "WEBVTT\n00:00:01.000 --> 00:00:04.000\n第一行\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues.length(), content="1")
  inspect(s.cues[0].start_ms, content="1000")
}

test "parse_vtt 跳过文件头里的元数据" {
  let text = "WEBVTT\nKind: captions\nLanguage: zh\n\n00:00:01.000 --> 00:00:04.000\n第一行\n"
  let s = match parse_vtt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues.length(), content="1")
}

test "parse_vtt 拒绝没有 WEBVTT 头的文件" {
  let ok = match parse_vtt("1\n00:00:01,000 --> 00:00:04,000\n第一行\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

test "parse_vtt 拒绝找不到时间行的块" {
  let ok = match parse_vtt("WEBVTT\n\n这是一段没头没尾的话\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

test "render_vtt 输出能被打回原形" {
  let rendered = match parse_vtt(sample_vtt) {
    Ok(s) => s.render_vtt()
    Err(_) => ""
  }
  inspect(rendered, content=sample_vtt)
}

test "render_vtt 把省略的小时补回来" {
  let s = match parse_vtt("WEBVTT\n\n01:23.456 --> 01:25.000\n一分钟处\n") {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.render_vtt(), content="WEBVTT\n\n00:01:23.456 --> 00:01:25.000\n一分钟处\n")
}

test "空的 WebVTT 渲染出来只剩头" {
  inspect(Subtitle::from_cues([]).render_vtt(), content="WEBVTT\n")
}

test "WebVTT 可以转成 SRT" {
  let s = match parse_vtt(sample_vtt) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(
    s.render_srt(),
    content="1\n00:00:01,000 --> 00:00:04,000\n第一行\n\n2\n00:00:05,000 --> 00:00:08,000\n第二行\n",
  )
}

test "SRT 可以转成 WebVTT" {
  let s = match parse_srt("1\n00:00:01,000 --> 00:00:04,000\n第一行\n") {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.render_vtt(), content="WEBVTT\n\n00:00:01.000 --> 00:00:04.000\n第一行\n")
}
