# 用法示例

这个文件里的代码块由 `moon check` / `moon test` 一起校验，不会和真实代码对不上 ——
改了 API 忘记改文档，`moon test` 会直接失败。

面向人的说明在 [README.md](README.md)。

## 解析、平移、渲染

```mbt check
///|
test "解析、平移、渲染" {
  let text = "1\n00:00:01,000 --> 00:00:04,000\n第一行\n"
  let subtitle = match @moonbit-subtitle.parse_srt(text) {
    Ok(s) => s
    Err(_) => panic()
  }
  // 平移 -500 毫秒：配音比预估短了半秒，字幕整体提前
  let moved = subtitle.shift(-500)
  inspect(moved.cues[0].start_ms, content="500")
  inspect(
    moved.render_srt(),
    content="1\n00:00:00,500 --> 00:00:03,500\n第一行\n",
  )
}
```

## 跨格式转换

WebVTT 的小时可省写法（`02:03.456`），转成 SRT 时会补全成 `00:02:03,456`。

```mbt check
///|
test "跨格式转换" {
  let vtt = "WEBVTT\n\n02:03.456 --> 02:05.000\n小时可以省略\n"
  let subtitle = match @moonbit-subtitle.parse_vtt(vtt) {
    Ok(s) => s
    Err(_) => panic()
  }
  inspect(
    subtitle.render_srt(),
    content="1\n00:02:03,456 --> 00:02:05,000\n小时可以省略\n",
  )
}
```

## 容错解析

前面带 BOM、换行是 CRLF、时间行两边有空格，这些都能吃下去。

```mbt check
///|
test "容错解析" {
  let messy = "\u{FEFF}1\r\n  00:00:01,000  -->  00:00:04,000 X1:100 X2:500  \r\n第一行\r\n\r\n"
  let subtitle = match @moonbit-subtitle.parse_srt(messy) {
    Ok(s) => s
    Err(_) => panic()
  }
  inspect(subtitle.cues.length(), content="1")
  inspect(subtitle.cues[0].end_ms, content="4000")
}
```

## 非字幕块

`NOTE` / `STYLE` / `REGION` 收进 `extras`，渲染时回到原来的位置。

```mbt check
///|
test "非字幕块" {
  let vtt = "WEBVTT\n\nNOTE 记一笔\n\n00:00:01.000 --> 00:00:04.000\n第一行\n"
  let subtitle = match @moonbit-subtitle.parse_vtt(vtt) {
    Ok(s) => s
    Err(_) => panic()
  }
  inspect(subtitle.extras.length(), content="1")
  inspect(subtitle.extras[0].kind, content="NOTE")
  // 落点是"插在第几条 cue 之前"，0 表示排在所有 cue 之前
  inspect(subtitle.extras[0].before_pos, content="0")
  inspect(subtitle.render_vtt(), content=vtt)
}
```

## 时间量解析

命令行里的平移量支持几种写法，也可以在自己代码里直接用。

```mbt check
///|
test "时间量解析" {
  debug_inspect(
    @moonbit-subtitle.parse_duration_ms("1.5s"),
    content="Some(1500)",
  )
  debug_inspect(
    @moonbit-subtitle.parse_duration_ms("-500"),
    content="Some(-500)",
  )
  debug_inspect(
    @moonbit-subtitle.parse_duration_ms("2m"),
    content="Some(120000)",
  )
  debug_inspect(@moonbit-subtitle.parse_duration_ms("一秒"), content="None")
}
```
