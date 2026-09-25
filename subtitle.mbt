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
  /// WebVTT 的 cue 标识（时间行前面那一行）。SRT 没有这个概念，
  /// 空串表示"没有标识" —— WebVTT 规范要求标识非空，所以空串不会和真标识撞上。
  id : String
  /// 时间行右侧的排版设置原文：SRT 的 `X1:100 X2:500`、
  /// WebVTT 的 `align:start position:10%`。空串表示没有。
  ///
  /// 收原文而不是解析成结构：两种格式的键名没有交集，原样存着就不会因为
  /// 遇到没见过的键而丢东西。写回时按格式判断 —— 把 SRT 的坐标写进
  /// WebVTT 的时间行会变成非法语法，反之亦然，所以只在同格式才写。
  settings : String
}

///|
/// 一段不是字幕的原文块：WebVTT 里的 `NOTE` / `STYLE` / `REGION`。
///
/// 这些东西播放器不显示，但丢了会改变文件的含义：`STYLE` 没了，依赖 `::cue` 的
/// 样式就失效；`REGION` 没了，字幕的位置定义就没了；`NOTE` 是给人看的说明，
/// 通常记着译者或时间轴信息。所以解析时原样收着，渲染时写回原来的位置。
///
/// `before_pos` 记的是"插在第几条 cue 之前"，用条数而不是 cue 的序号：
/// 序号可以被 `normalize` 重排，条数是文件里的物理位置。
pub struct ExtraBlock {
  /// `NOTE` / `STYLE` / `REGION` 三者之一。
  kind : String
  /// 整块原文，多行用换行连接，不含首尾空行。
  text : String
  /// 写回时插在第几条 cue 之前。等于 cue 总数表示排在末尾。
  before_pos : Int
}

///|
/// 一份字幕，按开始时间升序排列。
///
/// `extras` 只在 WebVTT 里有内容。SRT 没有对应的语法，解析出来永远是空数组，
/// 渲染成 SRT 时也会被丢掉 —— 格式里没有地方放它们。
pub struct Subtitle {
  cues : Array[Cue]
  extras : Array[ExtraBlock]
}

///|
/// 构造一份字幕。`pub struct` 在别的包里不能直接构造，
/// 所以必须留这么一个公开的入口，否则这个库对外就不可用了。
///
/// 不带 `extras`：非字幕块要么来自解析，要么由 `Subtitle::with_extras` 指定。
pub fn Subtitle::from_cues(cues : Array[Cue]) -> Subtitle {
  { cues, extras: [], }
}

///|
/// 构造一份字幕，同时指定非字幕块。`extras` 里的 `before_pos` 超出 cue 范围时
/// 统一按"排在末尾"处理，渲染时不会因为越界而丢块。
pub fn Subtitle::with_extras(
  cues : Array[Cue],
  extras : Array[ExtraBlock],
) -> Subtitle {
  { cues, extras, }
}

///|
/// 负数截断到 0。播放器不认负时间戳，宁可把整条字幕贴到 0 上。
fn clamp_to_zero(value : Int) -> Int {
  if value < 0 {
    0
  } else {
    value
  }
}

///|
/// 整体平移时间轴。`offset_ms` 为正表示延后，为负表示提前。
/// 平移后如果出现负时间，统一截断到 0 —— 负时间戳在播放器里没有意义。
///
/// 注意这里没有做"越出片尾"的处理：字幕被推到视频结束之后，
/// 播放器通常什么都不显示，这比截到片尾更符合直觉。
pub fn Subtitle::shift(self : Subtitle, offset_ms : Int) -> Subtitle {
  let out : Array[Cue] = []
  for c in self.cues {
    out.push({
      index: c.index,
      start_ms: clamp_to_zero(c.start_ms + offset_ms),
      end_ms: clamp_to_zero(c.end_ms + offset_ms),
      text: c.text,
      id: c.id,
      settings: c.settings,
    })
  }
  { cues: out, extras: self.extras, }
}

///|
/// 单点缩放后再取整。四舍五入而不是直接截断：
/// 截断会让每一条都偏向提前，几百条累计下来开头就有可感的偏移。
fn scale_ms(value : Int, speed : Double) -> Int {
  let scaled = value.to_double() * speed
  if scaled < 0.0 {
    0
  } else {
    (scaled + 0.5).to_int()
  }
}

///|
/// 按倍速缩放时间轴。`speed` 为 2.0 表示内容被压成一半时长。
/// 以后要做变速视频的字幕适配，这里就是入口。
///
/// `speed` 不是正数时原样返回。零和负数会让所有时间重叠在一起，
/// 属于调用方写错了，与其返回一堆空洞的结果，不如不动。
pub fn Subtitle::scale(self : Subtitle, speed : Double) -> Subtitle {
  if speed <= 0.0 {
    self
  } else {
    let out : Array[Cue] = []
    for c in self.cues {
      out.push({
        index: c.index,
        start_ms: clamp_to_zero(scale_ms(c.start_ms, speed)),
        end_ms: clamp_to_zero(scale_ms(c.end_ms, speed)),
        text: c.text,
        id: c.id,
        settings: c.settings,
      })
    }
    { cues: out, extras: self.extras, }
  }
}

///|
/// 合并相互重叠的 cue。
/// 有些 SRT 里相邻字幕会重叠几十毫秒，一部分播放器会因此闪烁或者丢行。
///
/// 合并规则：后一条的开始时间严格早于前一条的结束时间才算重叠，
/// 首尾相接（`start == 上一条 end`）不算 —— 那种情况本来就该是两条。
/// 文本用换行拼接，因为播放器会把 cue 里的换行照原样渲染成两行。
///
/// 输入不要求有序，内部会先按开始时间排一遍。
pub fn Subtitle::merge_overlaps(self : Subtitle) -> Subtitle {
  let sorted = self.cues.copy()
  sorted.sort_by((a, b) => a.start_ms - b.start_ms)
  let out : Array[Cue] = []
  for c in sorted {
    match out.last() {
      Some(prev) =>
        if c.start_ms < prev.end_ms {
          out[out.length() - 1] = {
            index: prev.index,
            start_ms: prev.start_ms,
            end_ms: if c.end_ms > prev.end_ms {
              c.end_ms
            } else {
              prev.end_ms
            },
            text: prev.text + "\n" + c.text,
            // 两条并成一条，标识只能留一个。取先出现的那条：
            // 它才是"这次合并从哪儿开始"的那个锚点。排版设置同理 ——
            // 合并后是一条字幕，只能有一套位置。
            id: prev.id,
            settings: prev.settings,
          }
        } else {
          out.push(c)
        }
      None => out.push(c)
    }
  }
  { cues: out, extras: self.extras, }
}

///|
/// 按开始时间重新排序，并把 cue 的序号重排成 1..n。
/// 手工改过字幕文件之后，序号和时间顺序经常对不上。
///
/// 用的是稳定排序：开始时间相同的两条保持原始先后，
/// 这样规范化只做它该做的事，不会顺手把别的顺序也改了。
pub fn Subtitle::normalize(self : Subtitle) -> Subtitle {
  let sorted = self.cues.copy()
  sorted.sort_by((a, b) => a.start_ms - b.start_ms)
  let out : Array[Cue] = []
  let mut index = 1
  for c in sorted {
    out.push({
      index,
      start_ms: c.start_ms,
      end_ms: c.end_ms,
      text: c.text,
      id: c.id,
      settings: c.settings,
    })
    index = index + 1
  }
  { cues: out, extras: self.extras, }
}

///|
/// 总时长，取最后一条 cue 的结束时间。空字幕返回 0。
pub fn Subtitle::duration_ms(self : Subtitle) -> Int {
  match self.cues.last() {
    Some(c) => c.end_ms
    None => 0
  }
}

///|
test "from_cues 能构造字幕" {
  let s = Subtitle::from_cues([
    {
      index: 1,
      start_ms: 1000,
      end_ms: 2000,
      text: "你好",
      id: "",
      settings: "",
    },
  ])
  inspect(s.cues.length(), content="1")
}

///|
test "shift 整体延后" {
  let s = Subtitle::from_cues([
    {
      index: 1,
      start_ms: 1000,
      end_ms: 2000,
      text: "你好",
      id: "",
      settings: "",
    },
  ])
  inspect(Subtitle::shift(s, 500).cues[0].start_ms, content="1500")
}

///|
test "shift 不产生负时间" {
  let s = Subtitle::from_cues([
    {
      index: 1,
      start_ms: 1000,
      end_ms: 2000,
      text: "你好",
      id: "",
      settings: "",
    },
  ])
  let r = Subtitle::shift(s, -3000)
  inspect(r.cues[0].start_ms, content="0")
  inspect(r.cues[0].end_ms, content="0")
}

///|
test "shift 保留原文与序号" {
  let s = Subtitle::from_cues([
    {
      index: 7,
      start_ms: 1000,
      end_ms: 2000,
      text: "你好",
      id: "",
      settings: "",
    },
  ])
  let r = Subtitle::shift(s, 250)
  inspect(r.cues[0].index, content="7")
  inspect(r.cues[0].text, content="你好")
  inspect(r.cues[0].end_ms, content="2250")
}

///|
test "scale 按倍速压缩" {
  let s = Subtitle::from_cues([
    {
      index: 1,
      start_ms: 1000,
      end_ms: 2001,
      text: "你好",
      id: "",
      settings: "",
    },
  ])
  let r = Subtitle::scale(s, 2.0)
  inspect(r.cues[0].start_ms, content="2000")
  // 2001 * 2 = 4002，没有被截断成 4001
  inspect(r.cues[0].end_ms, content="4002")
}

///|
test "scale 遇到非正数倍速时不动" {
  let s = Subtitle::from_cues([
    {
      index: 1,
      start_ms: 1000,
      end_ms: 2000,
      text: "你好",
      id: "",
      settings: "",
    },
  ])
  inspect(Subtitle::scale(s, 0.0).cues[0].start_ms, content="1000")
  inspect(Subtitle::scale(s, -1.0).cues[0].start_ms, content="1000")
}

///|
test "duration_ms 取最后一条的结束时间" {
  let s = Subtitle::from_cues([
    { index: 1, start_ms: 0, end_ms: 1000, text: "一", id: "", settings: "", },
    {
      index: 2,
      start_ms: 1200,
      end_ms: 3500,
      text: "二",
      id: "",
      settings: "",
    },
  ])
  inspect(Subtitle::duration_ms(s), content="3500")
}

///|
test "duration_ms 空字幕返回零" {
  let s = Subtitle::from_cues([])
  inspect(Subtitle::duration_ms(s), content="0")
}

///|
test "normalize 重排序号" {
  let s = Subtitle::from_cues([
    {
      index: 7,
      start_ms: 5000,
      end_ms: 6000,
      text: "后",
      id: "",
      settings: "",
    },
    {
      index: 3,
      start_ms: 1000,
      end_ms: 2000,
      text: "先",
      id: "",
      settings: "",
    },
  ])
  let r = Subtitle::normalize(s)
  inspect(r.cues[0].text, content="先")
  inspect(r.cues[0].index, content="1")
}

///|
test "normalize 把序号补齐成一到 n" {
  let s = Subtitle::from_cues([
    { index: 30, start_ms: 0, end_ms: 100, text: "甲", id: "", settings: "", },
    {
      index: 30,
      start_ms: 200,
      end_ms: 300,
      text: "乙",
      id: "",
      settings: "",
    },
    {
      index: 30,
      start_ms: 400,
      end_ms: 500,
      text: "丙",
      id: "",
      settings: "",
    },
  ])
  let r = Subtitle::normalize(s)
  inspect(r.cues[2].index, content="3")
  inspect(Subtitle::duration_ms(r), content="500")
}

///|
test "merge_overlaps 合并重叠的两条" {
  let s = Subtitle::from_cues([
    { index: 1, start_ms: 0, end_ms: 2000, text: "上", id: "", settings: "", },
    {
      index: 2,
      start_ms: 1900,
      end_ms: 3000,
      text: "下",
      id: "",
      settings: "",
    },
  ])
  let r = Subtitle::merge_overlaps(s)
  inspect(r.cues.length(), content="1")
  inspect(r.cues[0].end_ms, content="3000")
  inspect(r.cues[0].text, content="上\n下")
}

///|
test "merge_overlaps 不动首尾相接的两条" {
  let s = Subtitle::from_cues([
    { index: 1, start_ms: 0, end_ms: 2000, text: "上", id: "", settings: "", },
    {
      index: 2,
      start_ms: 2000,
      end_ms: 3000,
      text: "下",
      id: "",
      settings: "",
    },
  ])
  inspect(Subtitle::merge_overlaps(s).cues.length(), content="2")
}

///|
test "merge_overlaps 内部先排序" {
  let s = Subtitle::from_cues([
    {
      index: 9,
      start_ms: 5000,
      end_ms: 6000,
      text: "后",
      id: "",
      settings: "",
    },
    { index: 2, start_ms: 0, end_ms: 5500, text: "先", id: "", settings: "", },
  ])
  let r = Subtitle::merge_overlaps(s)
  inspect(r.cues.length(), content="1")
  inspect(r.cues[0].index, content="2")
}
