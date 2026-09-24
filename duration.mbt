///|
/// 人类可读的时间量解析，主要给命令行用。
///
/// 用户在命令行里写平移量，写 `-500` 是毫秒，写 `1.5s` 是秒 ——
/// 两种都得认。写错一律返回 `None`，不做"能读多少算多少"的猜测。
///
/// 支持的写法：
///   - `500` / `-500` / `+250`   毫秒
///   - `500ms`                   毫秒
///   - `1.5s` / `2s`             秒，允许小数
///   - `2m`                      分钟

///|
/// 字符串里是不是全是数字。空串不算。
fn is_all_digits(text : StringView) -> Bool {
  if text.is_empty() {
    false
  } else {
    let mut ok = true
    for c in text.iter() {
      if !c.is_ascii_digit() {
        ok = false
      }
    }
    ok
  }
}

///|
/// 把 `12`、`1.5`、`2.75` 这类写法换算成千分之一单位。
///
/// 小数位多于三位就截断，不足三位补零：毫秒已经是字幕能表达的最小精度，
/// 再往下没有意义。核心库没有字符串转浮点，所以整数部分和小数部分分开算。
fn parse_thousandths(text : StringView) -> Int? {
  let parts = text.split(".").to_array()
  if parts.length() > 2 {
    return None
  }
  let whole = match digits_to_int(parts[0]) {
    Some(v) => v
    None => return None
  }
  let mut frac = 0
  if parts.length() == 2 {
    let digits = parts[1]
    if !is_all_digits(digits) {
      return None
    }
    let mut taken = 0
    for c in digits.iter() {
      if taken < 3 {
        frac = frac * 10 + (c.to_int() - 48)
        taken = taken + 1
      }
    }
    while taken < 3 {
      frac = frac * 10
      taken = taken + 1
    }
  }
  Some(whole * 1000 + frac)
}

///|
/// 去掉后缀，没这个后缀就原样返回。
fn drop_suffix(text : String, suffix : StringView) -> String {
  match text.strip_suffix(suffix) {
    Some(rest) => rest.to_owned()
    None => text
  }
}

///|
/// 解析时间量，统一返回毫秒。解析不出来返回 `None`。
pub fn parse_duration_ms(raw : String) -> Int? {
  let text = raw.trim().to_owned()
  if text.is_empty() {
    return None
  }
  // 符号先摘掉，剩下正数部分单独处理
  let negative = text.has_prefix("-")
  let body = match text.strip_prefix("-") {
    Some(rest) => rest.to_owned()
    None =>
      match text.strip_prefix("+") {
        Some(rest) => rest.to_owned()
        None => text
      }
  }
  // 单位：毫秒是基准。先判 ms 再判 s，不然 `500ms` 会被当成秒
  let (factor, number) = if body.has_suffix("ms") {
    (1, drop_suffix(body, "ms"))
  } else if body.has_suffix("s") {
    (1000, drop_suffix(body, "s"))
  } else if body.has_suffix("m") {
    (60000, drop_suffix(body, "m"))
  } else {
    (1, body)
  }
  let thousandths = match parse_thousandths(number) {
    Some(v) => v
    None => return None
  }
  let millis = thousandths * factor / 1000
  if negative { Some(-millis) } else { Some(millis) }
}

test "parse_duration_ms 收下裸数字毫秒" {
  debug_inspect(parse_duration_ms("500"), content="Some(500)")
  debug_inspect(parse_duration_ms("-500"), content="Some(-500)")
  debug_inspect(parse_duration_ms("+250"), content="Some(250)")
  debug_inspect(parse_duration_ms("0"), content="Some(0)")
}

test "parse_duration_ms 收下毫秒与秒" {
  debug_inspect(parse_duration_ms("500ms"), content="Some(500)")
  debug_inspect(parse_duration_ms("2s"), content="Some(2000)")
  debug_inspect(parse_duration_ms("1.5s"), content="Some(1500)")
  debug_inspect(parse_duration_ms("0.25s"), content="Some(250)")
  debug_inspect(parse_duration_ms("-1.5s"), content="Some(-1500)")
}

test "parse_duration_ms 收下分钟" {
  debug_inspect(parse_duration_ms("2m"), content="Some(120000)")
  debug_inspect(parse_duration_ms("1.5m"), content="Some(90000)")
}

test "parse_duration_ms 忽略两端空白" {
  debug_inspect(parse_duration_ms("  1.5s  "), content="Some(1500)")
}

test "parse_duration_ms 对写错的输入返回 None" {
  debug_inspect(parse_duration_ms(""), content="None")
  debug_inspect(parse_duration_ms("abc"), content="None")
  debug_inspect(parse_duration_ms("1.2.3"), content="None")
  debug_inspect(parse_duration_ms("12x"), content="None")
  debug_inspect(parse_duration_ms("s"), content="None")
  debug_inspect(parse_duration_ms("1.s"), content="None")
}

test "parse_thousandths 小数位截断到三位" {
  debug_inspect(parse_thousandths("1"), content="Some(1000)")
  debug_inspect(parse_thousandths("1.5"), content="Some(1500)")
  debug_inspect(parse_thousandths("1.0009"), content="Some(1000)")
  debug_inspect(parse_thousandths(".5"), content="None")
}
