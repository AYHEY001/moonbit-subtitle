///|
/// 把字幕正文里的标记剥掉，得到纯文本。
///
/// 什么时候需要这个：字幕要喂给下游系统时 —— 翻译、语音合成、全文检索 ——
/// 那些系统要的是"人读到的字"，而不是 `<b>` `<c.red>` 这类排版指令。
/// 播放器那边不需要，它们本来就认识这些标记。
///
/// 默认解析**不剥离**标记，只有显式调 `Subtitle::strip_markup` 才剥。
/// 理由是反向的：剥掉之后就还原不回来了，而信息一旦在解析阶段丢掉，
/// 连"要不要剥"这个选择都没了。

///|
/// 标签的起始字符：字母、数字，或者闭合标签的斜杠。
///
/// 加这条判断是为了不误伤把尖括号当比较符用的正文。
/// `3 < 5` 里的 `<` 后面跟的是空格，按这条规则不算标签起始，
/// 于是原样保留 —— 严格按规范，正文里的尖括号该写成 `&lt;`，
/// 但真实文件里直接写的不在少数，能少删一个字就少删一个。
fn is_tag_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '/'
}

///|
/// 删掉 `<...>` 形式的标签。
///
/// 覆盖的写法：`<b>` `</b>` `<i>` `<u>` `<c.red>` `<v 张三>` `<lang en>`
/// `<ruby>` `<rt>`，以及 WebVTT 的时间戳标签 `<00:00:01.000>`。
///
/// 不删的情况：找不到配对的 `>`、中间又夹了一个 `<`、或者 `<` 后面不是标签起始字符。
/// 这些都不是标签，是正文。
fn strip_tags(text : String) -> String {
  let src : Array[Char] = []
  for c in text.iter() {
    src.push(c)
  }
  let out : Array[Char] = []
  let mut i = 0
  while i < src.length() {
    let c = src[i]
    if c == '<' && i + 1 < src.length() && is_tag_start(src[i + 1]) {
      // 往后找配对的 '>'。中途撞到 '<' 就说明前一个不是标签的开头，
      // 停在这里把当前这个 '<' 当正文留下。
      let mut j = i + 1
      let mut closed = -1
      while j < src.length() {
        if src[j] == '<' {
          break
        }
        if src[j] == '>' {
          closed = j
          break
        }
        j = j + 1
      }
      if closed >= 0 {
        i = closed + 1
      } else {
        out.push(c)
        i = i + 1
      }
    } else {
      out.push(c)
      i = i + 1
    }
  }
  String::from_iter(out.iter())
}

///|
/// 解掉正文里的字符实体。
///
/// `&amp;` 一定要放在**最后**替换：先换它的话，`&amp;lt;` 会先变成 `&lt;`，
/// 再被下一条规则变成 `<` —— 那是解了两次，而原文想显示的正是字面的 `&lt;`。
fn decode_entities(text : String) -> String {
  text
  .replace_all(old="&lt;", new="<")
  .replace_all(old="&gt;", new=">")
  .replace_all(old="&lrm;", new="")
  .replace_all(old="&rlm;", new="")
  .replace_all(old="&nbsp;", new=" ")
  .replace_all(old="&amp;", new="&")
}

///|
/// 把每条字幕的正文转成纯文本：先删标签，再解实体。
///
/// 只动 `text`，时间、序号、标识、排版设置原样保留 —— 剥标记是为了拿文本，
/// 不是为了让时间轴和字幕位置也变样。
///
/// `extras` 也不动。`STYLE` 块里装的是 CSS，里面有 `::cue` 这样的选择器、
/// 也可能有 `>` 子选择器和 `&` 之类的字符，按正文那套规则洗一遍只会把样式弄坏。
pub fn Subtitle::strip_markup(self : Subtitle) -> Subtitle {
  let out : Array[Cue] = []
  for c in self.cues {
    out.push({
      index: c.index,
      start_ms: c.start_ms,
      end_ms: c.end_ms,
      text: decode_entities(strip_tags(c.text)),
      id: c.id,
      settings: c.settings,
    })
  }
  { cues: out, extras: self.extras, }
}

///|
test "strip_tags 删掉常见的排版标签" {
  inspect(strip_tags("<b>加粗</b>"), content="加粗")
  inspect(strip_tags("<i>斜体</i>"), content="斜体")
  inspect(strip_tags("<c.red>变红</c>"), content="变红")
  inspect(strip_tags("<v 张三>说话的人</v>"), content="说话的人")
}

///|
test "strip_tags 删掉 WebVTT 的时间戳标签" {
  inspect(strip_tags("<00:00:01.000>卡拉OK"), content="卡拉OK")
}

///|
test "strip_tags 不碰不配对的尖括号" {
  inspect(strip_tags("3 < 5"), content="3 < 5")
  inspect(strip_tags("a <b 少了右括号"), content="a <b 少了右括号")
}

///|
test "strip_tags 保留夹在中间的正文" {
  inspect(strip_tags("<b>前</b>中间<i>后</i>"), content="前中间后")
}

///|
test "strip_tags 对空串和纯文本不动" {
  inspect(strip_tags(""), content="")
  inspect(strip_tags("没有标记的一行"), content="没有标记的一行")
}

///|
test "decode_entities 解掉常见实体" {
  inspect(decode_entities("A &amp; B"), content="A & B")
  inspect(decode_entities("&lt;标签&gt;"), content="<标签>")
  inspect(decode_entities("不留痕迹&lrm;"), content="不留痕迹")
}

///|
test "decode_entities 不把 &amp;lt; 解成尖括号" {
  // 原文写的是 &amp;lt;，读者该看到的是字面的 "&lt;"
  inspect(decode_entities("&amp;lt;"), content="&lt;")
}

///|
test "strip_markup 只改正文" {
  let s = Subtitle::from_cues([
    {
      index: 5,
      start_ms: 1000,
      end_ms: 4000,
      text: "<b>加粗</b> &amp; 普通",
      id: "intro",
      settings: "align:start",
    },
  ])
  let r = Subtitle::strip_markup(s)
  inspect(r.cues[0].text, content="加粗 & 普通")
  inspect(r.cues[0].index, content="5")
  inspect(r.cues[0].start_ms, content="1000")
  inspect(r.cues[0].end_ms, content="4000")
  inspect(r.cues[0].id, content="intro")
  // 剥标记只该动正文，位置设置要原样留着
  inspect(r.cues[0].settings, content="align:start")
}

///|
test "strip_markup 之后渲染出的 SRT 是纯文本" {
  let s = Subtitle::from_cues([
    {
      index: 1,
      start_ms: 1000,
      end_ms: 2000,
      text: "<i>斜体</i>",
      id: "",
      settings: "",
    },
  ])
  inspect(
    Subtitle::strip_markup(s).render_srt(),
    content="1\n00:00:01,000 --> 00:00:02,000\n斜体\n",
  )
}
