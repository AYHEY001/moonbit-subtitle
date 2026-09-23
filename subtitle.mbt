///|
/// 字幕的数据模型与时间轴变换。
///
/// 时间统一用毫秒整数表示。浮点的秒数在做平移和缩放的时候会产生累积误差，
/// 到最后一行字幕往下漂几百毫秒 —— 这是真实会撞上的问题。

///|
/// 一条字幕。
///
/// 这里用 `pub struct` 而不是 `pub(all) struct`：
/// 别的包（比如 cmd/main）可以读字段、可以模式匹配，但不能凭空构造。
/// 想要一条 Cue，得走解析函数 —— 这样"时间是否合法"只有一个出口。
pub struct Cue {
  index : Int
  start_ms : Int
  end_ms : Int
  text : String
}

///|
/// 一份字幕，按开始时间升序排列。
pub struct Subtitle {
  cues : Array[Cue]
}

///|
/// 构造一份字幕。`pub struct` 在别的包里不能直接构造，
/// 所以必须留这么一个公开的入口，否则这个库对外就不可用了。
pub fn Subtitle::from_cues(cues : Array[Cue]) -> Subtitle {
  { cues }
}

///|
/// 整体平移时间轴。`offset_ms` 为正表示延后，为负表示提前。
/// 平移后如果出现负时间，统一截断到 0 —— 负时间戳在播放器里没有意义。
pub fn Subtitle::shift(self : Subtitle, _offset_ms : Int) -> Subtitle {
  // TODO(D5)
  self
}

///|
/// 按倍速缩放时间轴。`speed` 为 2.0 表示内容被压成一半时长。
/// 以后要做变速视频的字幕适配，这里就是入口。
pub fn Subtitle::scale(self : Subtitle, _speed : Double) -> Subtitle {
  // TODO(D5，做不完可以砍)
  self
}

///|
/// 合并相互重叠的 cue。
/// 有些 SRT 里相邻字幕会重叠几十毫秒，一部分播放器会因此闪烁或者丢行。
pub fn Subtitle::merge_overlaps(self : Subtitle) -> Subtitle {
  // TODO(D5，做不完可以砍)
  self
}

///|
/// 按开始时间重新排序，并把 cue 的序号重排成 1..n。
/// 手工改过字幕文件之后，序号和时间顺序经常对不上。
pub fn Subtitle::normalize(self : Subtitle) -> Subtitle {
  // TODO(D5)
  self
}

///|
/// 总时长，取最后一条 cue 的结束时间。空字幕返回 0。
pub fn Subtitle::duration_ms(self : Subtitle) -> Int {
  // TODO(D5)
  match self.cues.last() {
    Some(c) => c.end_ms
    None => 0
  }
}

test "from_cues 能构造字幕" {
  let s = Subtitle::from_cues([{ index: 1, start_ms: 1000, end_ms: 2000, text: "你好" }])
  inspect(s.cues.len(), content="1")
}

test "shift 整体延后" {
  let s = Subtitle::from_cues([{ index: 1, start_ms: 1000, end_ms: 2000, text: "你好" }])
  inspect(Subtitle::shift(s, 500).cues[0].start_ms, content="1500")
}

test "shift 不产生负时间" {
  let s = Subtitle::from_cues([{ index: 1, start_ms: 1000, end_ms: 2000, text: "你好" }])
  let r = Subtitle::shift(s, -3000)
  inspect(r.cues[0].start_ms, content="0")
  inspect(r.cues[0].end_ms, content="0")
}

test "duration_ms 取最后一条的结束时间" {
  let s = Subtitle::from_cues([
    { index: 1, start_ms: 0, end_ms: 1000, text: "一" },
    { index: 2, start_ms: 1200, end_ms: 3500, text: "二" },
  ])
  inspect(Subtitle::duration_ms(s), content="3500")
}

test "duration_ms 空字幕返回零" {
  let s = Subtitle::from_cues([])
  inspect(Subtitle::duration_ms(s), content="0")
}

test "normalize 重排序号" {
  let s = Subtitle::from_cues([
    { index: 7, start_ms: 5000, end_ms: 6000, text: "后" },
    { index: 3, start_ms: 1000, end_ms: 2000, text: "先" },
  ])
  let r = Subtitle::normalize(s)
  inspect(r.cues[0].text, content="先")
  inspect(r.cues[0].index, content="1")
}
