///|
/// 时间戳的解析与格式化。
///
/// SRT 的时间戳长这样：`00:01:23,456`
/// WebVTT 的时间戳长这样：`00:01:23.456`
///
/// 两者只差毫秒的分隔符，所以走同一套逻辑：拆成时、分、秒、毫秒四段，
/// 统一换算成毫秒整数。全程用整数，不用浮点，避免累积误差。
///
/// 注意：这里手写字符串切分，不要去找正则库。
/// MoonBit 核心库没有内置正则，`moonbitlang/regexp` 目前还是 alpha 状态。

///|
/// 把纯数字串换算成整数。空串，或者含有非数字字符，都返回 `None`。
///
/// 核心库没有字符串转整数的接口（`strconv` 包是空的），所以自己按位累加。
/// 这里不做负数、正号、前导空白这些处理：时间戳的每一段都只可能是数字。
fn digits_to_int(v : StringView) -> Int? {
  if v.is_empty() {
    None
  } else {
    let mut acc = 0
    let mut ok = true
    for c in v.iter() {
      if c.is_ascii_digit() {
        acc = acc * 10 + (c.to_int() - 48)
      } else {
        ok = false
      }
    }
    if ok { Some(acc) } else { None }
  }
}

///|
/// 把 `00:01:23,456` 或 `00:01:23.456` 解析为毫秒数。
/// 格式不合法时返回 `None`。
///
/// 宽容的地方：两端空白、毫秒分隔符用逗号还是句点、小时超过两位。
/// 不放宽的地方：毫秒必须恰好三位，分和秒必须小于 60。
pub fn parse_timestamp(raw : String) -> Int? {
  // 先把毫秒分隔符统一成句点，省得分两套逻辑
  let normalized = raw.trim().to_owned().replace_all(old=",", new=".")
  let parts = normalized.split(":").to_array()
  if parts.length() != 3 {
    return None
  }
  // 第三段是「秒.毫秒」
  let sec_parts = parts[2].split(".").to_array()
  if sec_parts.length() != 2 {
    return None
  }
  let millis_text = sec_parts[1]
  if millis_text.char_length() != 3 {
    return None
  }
  match (
    digits_to_int(parts[0]),
    digits_to_int(parts[1]),
    digits_to_int(sec_parts[0]),
    digits_to_int(millis_text),
  ) {
    (Some(h), Some(m), Some(s), Some(ms)) =>
      if m < 60 && s < 60 {
        Some(h * 3600000 + m * 60000 + s * 1000 + ms)
      } else {
        None
      }
    _ => None
  }
}

///|
/// 左侧补零到指定宽度。
fn pad_left(value : Int, width : Int) -> String {
  let mut out = value.to_string()
  while out.length() < width {
    out = "0" + out
  }
  out
}

///|
/// 把毫秒数格式化成 SRT 风格的时间戳 `00:01:23,456`。
/// 负数一律按 0 处理。
pub fn format_timestamp(ms : Int) -> String {
  let total = if ms < 0 { 0 } else { ms }
  let hours = total / 3600000
  let minutes = total % 3600000 / 60000
  let seconds = total % 60000 / 1000
  let millis = total % 1000
  pad_left(hours, 2) +
  ":" +
  pad_left(minutes, 2) +
  ":" +
  pad_left(seconds, 2) +
  "," +
  pad_left(millis, 3)
}

///|
/// 下面这些测试现在全是红的，实现完上面两个函数之后应该全绿。
/// `test { }` 块和源代码在同一个包里，可以直接访问包内私有成员。

test "parse_timestamp 解析正常输入" {
  inspect(parse_timestamp("00:01:23,456"), content="Some(83456)")
}

test "parse_timestamp 兼容 VTT 的句点分隔" {
  inspect(parse_timestamp("00:01:23.456"), content="Some(83456)")
}

test "parse_timestamp 允许小时超过两位" {
  inspect(parse_timestamp("100:00:00,000"), content="Some(360000000)")
}

test "parse_timestamp 拒绝格式不合法的输入" {
  inspect(parse_timestamp("1:2,3"), content="None")
  inspect(parse_timestamp(""), content="None")
  inspect(parse_timestamp("00:00:00,45"), content="None")
  inspect(parse_timestamp("aa:bb:cc,ddd"), content="None")
}

test "format_timestamp 毫秒补足三位" {
  inspect(format_timestamp(83456), content="00:01:23,456")
  inspect(format_timestamp(0), content="00:00:00,000")
  inspect(format_timestamp(4), content="00:00:00,004")
}

test "format_timestamp 负数按零处理" {
  inspect(format_timestamp(-1), content="00:00:00,000")
}

test "解析和格式化互为逆运算" {
  let original = "01:02:03,004"
  let ms = match parse_timestamp(original) {
    Some(v) => v
    None => -1
  }
  inspect(ms, content="3723004")
  inspect(format_timestamp(ms), content="01:02:03,004")
}
