///|
/// SRT 的解析与渲染。
///
/// SRT 的格式很朴素：一条字幕由三部分组成 —— 序号、时间行、正文，
/// 块与块之间用空行隔开。
///
///     1
///     00:00:01,000 --> 00:00:04,000
///     第一行
///
/// 看着简单，但是真实文件里会混进这些东西，这是这个库存在的理由：
///   - 文件开头的 UTF-8 BOM（`\u{FEFF}`）
///   - Windows 的 CRLF 换行
///   - 正文里有空行（有些字幕组这么排版）
///   - 序号跳号、乱序，甚至有重复的
///   - 时间行两边多余的空格，箭头写成 `-->` 或 `-  ->`
///
/// 解析的宽容度是这里最重要的设计决定：能救回来的就救，救不回来的报错。

///|
/// 解析 SRT 文本。成功返回 `Subtitle`，失败返回错误说明。
pub fn parse_srt(_input : String) -> Result[Subtitle, String] {
  // TODO(D3)：先去掉 BOM，把 CRLF 归一成 LF，
  // 然后按空行切块，每块再取序号、时间行、正文三部分。
  // 时间行按 "-->" 切成左右两半，各自丢给 parse_timestamp。
  Err("not implemented")
}

///|
/// 渲染成 SRT 文本。输出用 LF 换行，序号从 1 开始。
pub fn render_srt(_self : Subtitle) -> String {
  // TODO(D4)
  ""
}

///|
/// 测试用的一小段 SRT，包含两条字幕。
let sample_srt : String =
  "1\n00:00:01,000 --> 00:00:04,000\n第一行\n\n2\n00:00:05,000 --> 00:00:08,000\n第二行\n"

test "parse_srt 解析出两条字幕" {
  let r = parse_srt(sample_srt)
  let ok = match r {
    Ok(s) => s.cues.len() == 2
    Err(_) => false
  }
  inspect(ok, content="true")
}

test "parse_srt 丢掉文件开头的 BOM" {
  let with_bom = "\u{FEFF}" + sample_srt
  let ok = match parse_srt(with_bom) {
    Ok(s) => s.cues.len() == 2
    Err(_) => false
  }
  inspect(ok, content="true")
}

test "parse_srt 能吃下 CRLF 换行" {
  let crlf = "1\r\n00:00:01,000 --> 00:00:04,000\r\n第一行\r\n\r\n"
  let ok = match parse_srt(crlf) {
    Ok(s) => s.cues.len() == 1
    Err(_) => false
  }
  inspect(ok, content="true")
}

test "parse_srt 对残缺的块报错" {
  let ok = match parse_srt("1\n坏掉的时间行\n正文\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

test "render_srt 输出能被打回原形" {
  let rendered = match parse_srt(sample_srt) {
    Ok(s) => render_srt(s)
    Err(_) => ""
  }
  inspect(rendered, content=sample_srt)
}
