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
///   - 序号跳号、乱序，甚至有重复的
///   - 时间行两边多余的空格，或者时间后面跟着排版坐标
///
/// 解析的宽容度是这里最重要的设计决定：能救回来的就救，救不回来的报错。
/// 一句话概括：**形状对不上的块一律报错，不做静默猜测**。
///
/// 早先这里还有一条"块首行不是序号行就并进上一条正文"的容错，
/// 理由是想救"正文里打了空行"的文件。实测 636 份真实字幕、62 万条字幕里
/// 一次都没有出现过这种写法（同一句要分两行，认的是块内换行），
/// 所以那条规则只留下了坏处：把一条坏掉的字幕悄悄并进上一条，比直接报错更难查。

///|
/// 解析 SRT 文本。成功返回 `Subtitle`，失败返回错误说明。
///
/// 块是不是"一条新字幕"，只看头两行：第一行是纯数字序号、第二行带 `-->`。
/// 两条都满足就是新字幕，否则按块号报错 —— 不做"接回上一条"的猜测。
/// 同一句要分两行，写在同一块里换行即可，不需要打空行。
pub fn parse_srt(input : String) -> Result[Subtitle, String] {
  let text = normalize_newlines(strip_bom(input))
  let blocks = split_blocks(text.split("\n").to_array())
  let cues : Array[Cue] = []
  let mut block_no = 0
  for block in blocks {
    block_no = block_no + 1
    if is_index_line(block[0]) {
      if block.length() < 2 {
        return Err(
          "第 " +
          block_no.to_string() +
          " 块：序号行后面没有时间行",
        )
      }
      if !is_time_line(block[1]) {
        return Err(
          "第 " +
          block_no.to_string() +
          " 块：第二行不是时间行：" +
          block[1].to_owned(),
        )
      }
      match parse_time_range(block[1], parse_timestamp) {
        Ok(range) => {
          let (start_ms, end_ms, settings) = range
          // 序号照原样留着，不做重新编号 —— 那件事归 normalize
          let index = match digits_to_int(block[0].trim()) {
            Some(v) => v
            None => block_no
          }
          // SRT 没有 cue 标识这个概念，统一给空串。
          // 从 WebVTT 转过来的文件在这一步会丢掉标识，这是格式本身决定的 ——
          // SRT 里没有地方放它，不是实现偷懒。
          cues.push({
            index,
            start_ms,
            end_ms,
            text: join_body(block, 2),
            id: "",
            settings,
          })
        }
        Err(msg) => return Err("第 " + block_no.to_string() + " 块：" + msg)
      }
    } else {
      // 块的首行既不是序号行，就没有别的解释可给了。
      // 早先这里是"并进上一条正文"，看着宽容，实际是把结构错误悄悄抹平：
      // info 报的条数会少一块、strip 会给这段做实体解码、
      // 转成 WebVTT 之后这段会变成上一条 cue 的第二行被播放器当台词显示出来。
      return Err(
        "第 " +
        block_no.to_string() +
        " 块：第一行不是序号行：" +
        block[0].to_owned() +
        "。SRT 每条字幕都以序号行开头，空行是块分隔符而不是正文换行 —— " +
        "如果这几行本该接在上一条后面，把中间的空行删掉",
      )
    }
  }
  Ok(Subtitle::from_cues(cues))
}

///|
/// 渲染成 SRT 文本。输出用 LF 换行，序号从 1 开始。
///
/// 每条字幕自己不带结尾空行，块之间用空行连接，最后补一个换行 ——
/// 这样输出和常见的 SRT 文件逐字节一致，往返测试才能直接比字符串。
///
/// 排版设置写回时间行右侧，但只写 SRT 自己的坐标语法。
/// 从 WebVTT 转过来的 cue 带的是 `align:start` 这类设置，写进 SRT 的时间行
/// 会让播放器读不懂整行 —— 那种情况丢掉，格式限制不是实现漏做。
///
/// 定义为 `Subtitle::render_srt` 而不是自由函数：跟 shift / normalize 一样挂在类型上，
/// 调用处写 `s.render_srt()` 更顺。
pub fn Subtitle::render_srt(self : Subtitle) -> String {
  if self.cues.is_empty() {
    return ""
  }
  let blocks : Array[String] = []
  let mut index = 1
  for c in self.cues {
    let tail = if c.settings.is_empty() || is_vtt_settings(c.settings) {
      ""
    } else {
      " " + c.settings
    }
    blocks.push(
      index.to_string() +
      "\n" +
      format_timestamp(c.start_ms) +
      " --> " +
      format_timestamp(c.end_ms) +
      tail +
      "\n" +
      c.text,
    )
    index = index + 1
  }
  blocks.join("\n\n") + "\n"
}

///|
/// 测试用的一小段 SRT，包含两条字幕。
let sample_srt : String = "1\n00:00:01,000 --> 00:00:04,000\n第一行\n\n2\n00:00:05,000 --> 00:00:08,000\n第二行\n"

///|
test "parse_srt 解析出两条字幕" {
  let r = parse_srt(sample_srt)
  let ok = match r {
    Ok(s) => s.cues.length() == 2
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
test "parse_srt 丢掉文件开头的 BOM" {
  let with_bom = "\u{FEFF}" + sample_srt
  let ok = match parse_srt(with_bom) {
    Ok(s) => s.cues.length() == 2
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
test "parse_srt 能吃下 CRLF 换行" {
  let crlf = "1\r\n00:00:01,000 --> 00:00:04,000\r\n第一行\r\n\r\n"
  let ok = match parse_srt(crlf) {
    Ok(s) => s.cues.length() == 1
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
test "parse_srt 对残缺的块报错" {
  let ok = match parse_srt("1\n坏掉的时间行\n正文\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

///|
test "render_srt 输出能被打回原形" {
  let rendered = match parse_srt(sample_srt) {
    Ok(s) => s.render_srt()
    Err(_) => ""
  }
  inspect(rendered, content=sample_srt)
}

///|
test "parse_srt 取到时间与正文" {
  let s = match parse_srt(sample_srt) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].start_ms, content="1000")
  inspect(s.cues[0].end_ms, content="4000")
  inspect(s.cues[0].text, content="第一行")
  inspect(s.cues[1].index, content="2")
}

///|
/// 同一句要分两行，写在同一块里换行就行。
/// 这是真实字幕的通行写法，也是"空行分隔一律报错"之后留给用户的正确出路 ——
/// 实测 636 份真实字幕里 33% 的 cue 是两行，用的全是这种写法。
test "parse_srt 保留多行正文" {
  let text = "1\n00:00:01,000 --> 00:00:04,000\n第一行\n第二行\n"
  let s = match parse_srt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].text, content="第一行\n第二行")
  inspect(s.render_srt(), content=text)
}

///|
test "parse_srt 容忍时间行多余空格并留下排版坐标" {
  let text = "1\n  00:00:01,000  -->  00:00:04,000 X1:100 X2:500  \n第一行\n"
  let s = match parse_srt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].start_ms, content="1000")
  inspect(s.cues[0].end_ms, content="4000")
  // 坐标与时间戳之间连着几个空格，收进来时压成一个；行尾空白不留
  inspect(s.cues[0].settings, content="X1:100 X2:500")
}

///|
test "带坐标的 SRT 转一圈逐字不变" {
  let text = "1\n00:00:01,000 --> 00:00:04,000 X1:100 X2:500 Y1:20 Y2:60\n第一行\n"
  let rendered = match parse_srt(text) {
    Ok(s) => s.render_srt()
    Err(_) => ""
  }
  inspect(rendered, content=text)
}

///|
test "坐标跟着 shift 与 normalize 走" {
  let text = "1\n00:00:05,000 --> 00:00:06,000 X1:100\n后\n\n2\n00:00:01,000 --> 00:00:02,000 X1:200\n先\n"
  let s = match parse_srt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(Subtitle::shift(s, 500).cues[0].settings, content="X1:100")
  let r = Subtitle::normalize(s)
  inspect(r.cues[0].settings, content="X1:200")
  inspect(r.cues[1].settings, content="X1:100")
}

///|
test "parse_srt 原样保留跳号与乱序的序号" {
  let text = "7\n00:00:05,000 --> 00:00:06,000\n后\n\n3\n00:00:01,000 --> 00:00:02,000\n先\n"
  let s = match parse_srt(text) {
    Ok(s) => s
    Err(_) => Subtitle::from_cues([])
  }
  inspect(s.cues[0].index, content="7")
  inspect(s.cues[1].index, content="3")
}

///|
test "render_srt 重新编号并保持 LF" {
  let text = "7\r\n00:00:05,000 --> 00:00:06,000\r\n后\r\n\r\n3\r\n00:00:01,000 --> 00:00:02,000\r\n先\r\n"
  let rendered = match parse_srt(text) {
    Ok(s) => Subtitle::normalize(s).render_srt()
    Err(_) => ""
  }
  inspect(
    rendered,
    content="1\n00:00:01,000 --> 00:00:02,000\n先\n\n2\n00:00:05,000 --> 00:00:06,000\n后\n",
  )
}

///|
/// 空行是 SRT 的块分隔符。夹在两条字幕之间、前后都被空行隔开的块，
/// 只能按块号报错。
///
/// 早先这里会静默并进上一条的正文，而且**逐字往返还是绿的** ——
/// 并进去时补了一个空行，渲染出来跟原文一模一样。看不出问题，但对下游全是错的：
/// `info` 报的条数少一块、`strip` 会给这段自由文本做实体解码、
/// 转成 WebVTT 之后这段会变成上一条 cue 的第二行，被播放器当台词显示。
test "parse_srt 拒绝被空行隔开的独立块" {
  let text = "1\n00:00:01,000 --> 00:00:04,000\n前半句\n\n自由文本块\n\n2\n00:00:05,000 --> 00:00:06,000\n第二条\n"
  let msg = match parse_srt(text) {
    Ok(_) => ""
    Err(msg) => msg
  }
  inspect(msg.contains("第 2 块"), content="true")
  inspect(msg.contains("不是序号行"), content="true")
  // 光说错在哪不够，还得说怎么办 —— 这句是用户唯一能照着改的线索
  inspect(msg.contains("把中间的空行删掉"), content="true")
}

///|
/// 只有一条 cue、后面跟着被空行隔开的续行，同样报错。
///
/// 形状上它很像"同一句的第二行"，但 SRT 里没有语法能表达它：
/// 播放器读到没有序号行的块会整块丢掉，本库跟着丢掉这个猜测才是一致的。
test "parse_srt 拒绝只有一条 cue 时的空行续行" {
  let ok = match
    parse_srt("1\n00:00:01,000 --> 00:00:04,000\n第一行\n\n第二行\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

///|
test "parse_srt 空文件返回零条" {
  let ok = match parse_srt("") {
    Ok(s) => s.cues.length() == 0
    Err(_) => false
  }
  inspect(ok, content="true")
}

///|
test "parse_srt 拒绝结束早于开始的时间行" {
  let ok = match parse_srt("1\n00:00:05,000 --> 00:00:01,000\n反了\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

///|
test "parse_srt 拒绝开头的空块之后直接是正文" {
  let ok = match
    parse_srt("这不是序号行\n00:00:01,000 --> 00:00:02,000\n") {
    Ok(_) => false
    Err(_) => true
  }
  inspect(ok, content="true")
}

///|
test "空字幕渲染成空串" {
  inspect(Subtitle::from_cues([]).render_srt(), content="")
}

///|
test "错误信息里带块号" {
  let msg = match
    parse_srt("1\n00:00:01,000 --> 00:00:04,000\n甲\n\n2\n没有箭头\n") {
    Ok(_) => ""
    Err(msg) => msg
  }
  inspect(msg.contains("第 2 块"), content="true")
}
