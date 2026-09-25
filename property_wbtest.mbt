///|
/// 属性测试（白盒）。
///
/// 前面那些表驱动的用例只能覆盖想得到的情况。往返一致性这类性质更适合用随机输入跑：
/// 解析和渲染两边只要有一处对不上，几百组随机输入里总能撞出来。
///
/// 用的是核心库自带的 quickcheck，不引入额外依赖。
///
/// 文件名用 `_wbtest.mbt`（白盒测试），不用 `_test.mbt`（黑盒测试）：
/// 能构造 `Cue`。黑盒测试文件（`*_test.mbt`）会被编成独立的包，拿不到包内类型。

///|
/// 两条字幕的条数、时间、正文、标识、排版设置是否完全一致。
///
/// `Cue` 没有 derive `Eq`：时间合法性由解析函数把关，多一套相等语义没有用。
/// 测试里手动比一遍反而更清楚在比什么。
fn same_subtitle(a : Subtitle, b : Subtitle) -> Bool {
  if a.cues.length() != b.cues.length() {
    false
  } else {
    let mut ok = true
    let mut i = 0
    while i < a.cues.length() {
      let x = a.cues[i]
      let y = b.cues[i]
      if x.start_ms != y.start_ms ||
        x.end_ms != y.end_ms ||
        x.text != y.text ||
        x.id != y.id ||
        x.settings != y.settings {
        ok = false
      }
      i = i + 1
    }
    ok
  }
}

///|
/// 取绝对值。
fn positive(v : Int) -> Int {
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
/// 把一串随机整数拼成一份字幕。
///
/// 时间取非负、结束不早于开始、正文非空且不含换行 —— 这几条是 SRT 本身的要求。
/// 不满足的话那已经不是"合法输入"，随机输入测出来的失败也就没有意义。
fn subtitle_of(seed_values : Array[Int]) -> Subtitle {
  let cues : Array[Cue] = []
  let mut i = 0
  while i < seed_values.length() {
    // 先取模再取绝对值：直接对 Int 最小值取相反数会溢出
    let start = positive(seed_values[i] % 3600000)
    let span = positive(seed_values[i] % 4000)
    cues.push({
      index: i + 1,
      start_ms: start,
      end_ms: start + span,
      text: "行" + (i + 1).to_string(),
      id: "",
      settings: "",
    })
    i = i + 1
  }
  Subtitle::from_cues(cues)
}

///|
/// 带 cue 标识的一份字幕，专供 WebVTT 往返测试。
///
/// 标识用 `c1` 这种短名字，因为规范禁止标识里出现换行和 `-->` ——
/// 随机内容里混进箭头会把标识行变成时间行，那已经不是合法输入，
/// 拿它去测解析器没有意义。
fn subtitle_with_ids_of(seed_values : Array[Int]) -> Subtitle {
  let cues : Array[Cue] = []
  let mut i = 0
  while i < seed_values.length() {
    let start = positive(seed_values[i] % 3600000)
    let span = positive(seed_values[i] % 4000)
    cues.push({
      index: i + 1,
      start_ms: start,
      end_ms: start + span,
      text: "行" + (i + 1).to_string(),
      id: "c" + (i + 1).to_string(),
      settings: "",
    })
    i = i + 1
  }
  Subtitle::from_cues(cues)
}

///|
/// 带 WebVTT 排版设置的一份字幕，专供设置往返测试。
///
/// 用 `align` 与 `position` 两个键：`position` 的取值带 `%`，
/// 正好也能验出"设置原文里除了空格还有别的符号"这种情况没被切坏。
fn subtitle_with_vtt_settings_of(seed_values : Array[Int]) -> Subtitle {
  let cues : Array[Cue] = []
  let mut i = 0
  while i < seed_values.length() {
    let start = positive(seed_values[i] % 3600000)
    let span = positive(seed_values[i] % 4000)
    cues.push({
      index: i + 1,
      start_ms: start,
      end_ms: start + span,
      text: "行" + (i + 1).to_string(),
      id: "",
      settings: "align:start position:" + (i * 10 + 10).to_string() + "%",
    })
    i = i + 1
  }
  Subtitle::from_cues(cues)
}

///|
/// 带 SRT 排版坐标的一份字幕，专供 SRT 往返测试。
///
/// 坐标用 `X1` / `Y1` / `X2` / `Y2` 四个键 —— SRT 没有官方规范，
/// 这几个是社区通行的写法，也正是 `is_srt_settings` 认的那一组。
fn subtitle_with_coords_of(seed_values : Array[Int]) -> Subtitle {
  let cues : Array[Cue] = []
  let mut i = 0
  while i < seed_values.length() {
    let start = positive(seed_values[i] % 3600000)
    let span = positive(seed_values[i] % 4000)
    cues.push({
      index: i + 1,
      start_ms: start,
      end_ms: start + span,
      text: "行" + (i + 1).to_string(),
      id: "",
      settings: "X1:" +
      (i * 10).to_string() +
      " Y1:20 X2:" +
      (i * 10 + 100).to_string() +
      " Y2:60",
    })
    i = i + 1
  }
  Subtitle::from_cues(cues)
}

///|
/// 每条字幕前面挂一个 NOTE 块。落点按"前面有几条 cue"给，
/// 从 0 到 n-1，正好覆盖首条之前到末条之前这一段。
fn subtitle_with_extras_of(seed_values : Array[Int]) -> Subtitle {
  let cues : Array[Cue] = []
  let extras : Array[ExtraBlock] = []
  let mut i = 0
  while i < seed_values.length() {
    let start = positive(seed_values[i] % 3600000)
    let span = positive(seed_values[i] % 4000)
    cues.push({
      index: i + 1,
      start_ms: start,
      end_ms: start + span,
      text: "行" + (i + 1).to_string(),
      id: "",
      settings: "",
    })
    extras.push({
      kind: "NOTE",
      text: "NOTE 第" + (i + 1).to_string() + "条之前",
      before_pos: i,
    })
    i = i + 1
  }
  Subtitle::with_extras(cues, extras)
}

///|
/// 两块非字幕内容是否一致：类型、原文、落点都要对上。
fn same_extras(a : Subtitle, b : Subtitle) -> Bool {
  if a.extras.length() != b.extras.length() {
    false
  } else {
    let mut ok = true
    let mut i = 0
    while i < a.extras.length() {
      let x = a.extras[i]
      let y = b.extras[i]
      if x.kind != y.kind || x.text != y.text || x.before_pos != y.before_pos {
        ok = false
      }
      i = i + 1
    }
    ok
  }
}

///|
/// 走一圈 WebVTT，再走一圈 SRT，回到起点。
///
/// 传进来的字幕不能带标识：SRT 里没有放标识的地方，带了必然丢，
/// 那属于格式限制而不是缺陷。拿它当失败信号只会得到一个永远红的测试，
/// 所以这一条用不带标识的 `subtitle_of`。
fn roundtrip_vtt_then_srt(s : Subtitle) -> Bool {
  match parse_vtt(s.render_vtt()) {
    Ok(as_vtt) =>
      match parse_srt(as_vtt.render_srt()) {
        Ok(back) => same_subtitle(s, back)
        Err(_) => false
      }
    Err(_) => false
  }
}

///|
test "SRT 渲染再解析是恒等变换" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_of(seed_values)
      match parse_srt(s.render_srt()) {
        Ok(back) => same_subtitle(s, back)
        Err(_) => false
      }
    },
    count=200,
    seed=20260924,
  )
}

///|
test "WebVTT 渲染再解析是恒等变换" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_of(seed_values)
      match parse_vtt(s.render_vtt()) {
        Ok(back) => same_subtitle(s, back)
        Err(_) => false
      }
    },
    count=200,
    seed=20260925,
  )
}

///|
test "带标识的 WebVTT 渲染再解析也是恒等变换" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_with_ids_of(seed_values)
      match parse_vtt(s.render_vtt()) {
        Ok(back) => same_subtitle(s, back)
        Err(_) => false
      }
    },
    count=200,
    seed=20260927,
  )
}

///|
test "带排版设置的 WebVTT 渲染再解析不丢" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_with_vtt_settings_of(seed_values)
      match parse_vtt(s.render_vtt()) {
        Ok(back) => same_subtitle(s, back)
        Err(_) => false
      }
    },
    count=200,
    seed=20260929,
  )
}

///|
test "带排版坐标的 SRT 渲染再解析不丢" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_with_coords_of(seed_values)
      match parse_srt(s.render_srt()) {
        Ok(back) => same_subtitle(s, back)
        Err(_) => false
      }
    },
    count=200,
    seed=20260930,
  )
}

///|
test "非字幕块渲染再解析不丢" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_with_extras_of(seed_values)
      match parse_vtt(s.render_vtt()) {
        Ok(back) => same_subtitle(s, back) && same_extras(s, back)
        Err(_) => false
      }
    },
    count=200,
    seed=20260928,
  )
}

///|
test "SRT 与 WebVTT 之间来回转换不丢时间" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      roundtrip_vtt_then_srt(subtitle_of(seed_values))
    },
    count=200,
    seed=20260926,
  )
}

///|
test "shift 对非负平移量只改时间不改正文" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let s = subtitle_of(seed_values)
      let moved = Subtitle::shift(s, 1234)
      let mut ok = true
      let mut i = 0
      while i < s.cues.length() {
        if moved.cues[i].start_ms != s.cues[i].start_ms + 1234 {
          ok = false
        }
        if moved.cues[i].end_ms != s.cues[i].end_ms + 1234 {
          ok = false
        }
        if moved.cues[i].text != s.cues[i].text {
          ok = false
        }
        i = i + 1
      }
      ok
    },
    count=200,
    seed=7,
  )
}

///|
test "normalize 幂等，序号连续，开始时间不倒退" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let once = Subtitle::normalize(subtitle_of(seed_values))
      let twice = Subtitle::normalize(once)
      let mut ok = same_subtitle(once, twice)
      let mut i = 0
      while i < once.cues.length() {
        if once.cues[i].index != i + 1 {
          ok = false
        }
        if i > 0 && once.cues[i].start_ms < once.cues[i - 1].start_ms {
          ok = false
        }
        i = i + 1
      }
      ok
    },
    count=200,
    seed=11,
  )
}

///|
test "merge_overlaps 之后两两不再重叠" {
  @quickcheck.check(
    (seed_values : Array[Int]) => {
      let merged = Subtitle::normalize(subtitle_of(seed_values)).merge_overlaps()
      let mut ok = true
      let mut i = 1
      while i < merged.cues.length() {
        if merged.cues[i].start_ms < merged.cues[i - 1].end_ms {
          ok = false
        }
        i = i + 1
      }
      ok
    },
    count=200,
    seed=13,
  )
}

///|
test "时间戳解析再格式化是恒等变换" {
  @quickcheck.check(
    (raw : Int) => {
      let ms = positive(raw % 36000000)
      match parse_timestamp(format_timestamp(ms)) {
        Some(back) => back == ms
        None => false
      }
    },
    count=300,
    seed=19,
  )
}
