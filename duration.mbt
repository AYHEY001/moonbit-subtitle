///|
/// 人类可读的时间量解析，主要给命令行用。
///
/// 用户在命令行里写平移量，写 `-500` 是毫秒，写 `1.5s` 是秒 ——
/// 两种都得认。写错一律返回 `None`，不做"能读多少算多少"的猜测。
///
/// 支持的写法：
///   - `500` / `-500` / `+250`   毫秒，整数
///   - `500ms`                   毫秒，整数
///   - `1.5s` / `2s`             秒，允许小数
///   - `2m`                      分钟，允许小数
///
/// 毫秒不接受小数：`1.5ms` 会被拒绝。毫秒已经是字幕的最小精度，
/// 再往下切没有意义，而静默截断成 1 毫秒更糟。
///
/// 数值超出 `Int` 能表示的范围时返回 `None`，不回绕。具体表现为：
/// 毫秒可以用满 32 位（约 24.8 天），秒和分钟因为要走小数路径，
/// 中间量放在千分之一单位里，上界被压低到约 35 分钟 —— 这个差距是刻意的，
/// 不是漏判。两条路径的分工见 `parse_duration_ms` 的注释。

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
///
/// 最后一次运算是 `whole * 1000 + frac`，两者都可能很大，所以要在**算完之后**
/// 判断：只卡 `whole` 是不够的 —— `2147483.999` 的整数部分合规，
/// 但乘加之后是 `2147483999`，照样回绕成负数。
///
/// 这个函数只服务**秒和分钟**这类需要小数的单位，它的上界是"千分之一单位"
/// 的上界（约 214 万），换算成秒约 35 分钟。毫秒不需要小数，走 `parse_duration_ms`
/// 里另一条不经过千分之一的路径，那条的上界是 `Int` 上界本身。
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
  // 上界拆成 2147483 * 1000 + 647，先比整数部分、相等再比小数部分，
  // 全程不越过 Int 上界，所以这个比较本身是安全的
  if whole > 2147483 || (whole == 2147483 && frac > 647) {
    return None
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
/// 解析时间量，统一返回毫秒。解析不出来、或者数值超出可表示范围，都返回 `None`。
///
/// 溢出挡在最外层，判的是**最终毫秒值**能不能放下，而不是中间量。
///
/// 毫秒（带 `ms` 后缀或裸数字）和秒/分钟走两条路：
///
///   - 毫秒：结果就是数字本身。直接从字符串读整数，不经过"千分之一单位"。
///     绕那一道的代价是可达范围被砍 1000 倍 —— `2147483647ms` 明明正好在上界上，
///     却会被拒。毫秒不需要小数，这条路本来就不该有中间单位。
///   - 秒/分钟：需要小数（`1.5s`），所以走千分之一再乘回去。系数里能约掉 1000 的
///     部分先约掉（秒 → 1、分 → 60），乘法放最后一步，这样中间量不会比结果大，
///     上界也就不用按系数分档。
///
/// 为什么值得专门判：命令行上的溢出表现是"输出一个合法但完全错误的时间"——
/// `shift a.srt 99999999999999` 会得到 26 分钟，不报错、退出码 0。
/// 一条被平移错的字幕在成片里不会引起任何异常，只能靠人眼盯出来。
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
  let millis = if body.has_suffix("ms") {
    // 毫秒路径：数字本身就是结果，无小数可言
    let number = drop_suffix(body, "ms")
    if !is_all_digits(number) {
      return None
    }
    match digits_to_int(number) {
      Some(v) => v
      None => return None
    }
  } else if body.has_suffix("s") {
    let thousandths = match parse_thousandths(drop_suffix(body, "s")) {
      Some(v) => v
      None => return None
    }
    // 秒：千分之一单位 ×1000÷1000，约掉就是它自己
    thousandths
  } else if body.has_suffix("m") {
    let thousandths = match parse_thousandths(drop_suffix(body, "m")) {
      Some(v) => v
      None => return None
    }
    // 分：千分之一单位 ×60000÷1000 = ×60，乘法放最后，先判上界
    if thousandths > 2147483647 / 60 {
      return None
    } else {
      thousandths * 60
    }
  } else {
    // 裸数字：按毫秒处理，和带 `ms` 后缀同一条路
    if !is_all_digits(body) {
      return None
    }
    match digits_to_int(body) {
      Some(v) => v
      None => return None
    }
  }
  if negative {
    Some(-millis)
  } else {
    Some(millis)
  }
}

///|
test "parse_duration_ms 收下裸数字毫秒" {
  debug_inspect(parse_duration_ms("500"), content="Some(500)")
  debug_inspect(parse_duration_ms("-500"), content="Some(-500)")
  debug_inspect(parse_duration_ms("+250"), content="Some(250)")
  debug_inspect(parse_duration_ms("0"), content="Some(0)")
}

///|
test "parse_duration_ms 收下毫秒与秒" {
  debug_inspect(parse_duration_ms("500ms"), content="Some(500)")
  debug_inspect(parse_duration_ms("2s"), content="Some(2000)")
  debug_inspect(parse_duration_ms("1.5s"), content="Some(1500)")
  debug_inspect(parse_duration_ms("0.25s"), content="Some(250)")
  debug_inspect(parse_duration_ms("-1.5s"), content="Some(-1500)")
}

///|
test "parse_duration_ms 收下分钟" {
  debug_inspect(parse_duration_ms("2m"), content="Some(120000)")
  debug_inspect(parse_duration_ms("1.5m"), content="Some(90000)")
}

///|
test "parse_duration_ms 忽略两端空白" {
  debug_inspect(parse_duration_ms("  1.5s  "), content="Some(1500)")
}

///|
test "parse_duration_ms 对写错的输入返回 None" {
  debug_inspect(parse_duration_ms(""), content="None")
  debug_inspect(parse_duration_ms("abc"), content="None")
  debug_inspect(parse_duration_ms("1.2.3"), content="None")
  debug_inspect(parse_duration_ms("12x"), content="None")
  debug_inspect(parse_duration_ms("s"), content="None")
  debug_inspect(parse_duration_ms("1.s"), content="None")
}

///|
/// 毫秒不带小数。裸数字按毫秒处理，所以 `1.5` 和 `1.5ms` 都是 `None` ——
/// "1.5 毫秒"不是一个能写出来的时间量，宁可拒绝。
///
/// 这里原本是 `Some(1)`：走千分之一单位再整除回来，小数被静默抹掉。
/// 顺手改掉是因为它和溢出是同一类毛病 —— 输入越界却给一个正常的返回值，
/// 调用方没有任何办法察觉自己写错了。
test "parse_duration_ms 毫秒不接受小数" {
  debug_inspect(parse_duration_ms("1.5"), content="None")
  debug_inspect(parse_duration_ms("1.5ms"), content="None")
  debug_inspect(parse_duration_ms("1.0"), content="None")
}

///|
/// 毫秒路径不经过千分之一单位，所以能一直用到 `Int` 上界。
/// 秒和分钟要走小数，上界被千分之一单位压到约 35 分钟 —— 这个差距是刻意的，
/// 不是漏判：`35791m × 60000` 已经逼近上界，再大就真的放不下了。
test "parse_duration_ms 毫秒能用满 Int 范围" {
  debug_inspect(parse_duration_ms("2147483647ms"), content="Some(2147483647)")
  debug_inspect(parse_duration_ms("2147483647"), content="Some(2147483647)")
  debug_inspect(parse_duration_ms("2147483648ms"), content="None")
  // 秒和分钟的上界低 1000 倍
  debug_inspect(parse_duration_ms("2147483s"), content="Some(2147483000)")
  debug_inspect(parse_duration_ms("2147484s"), content="None")
}

///|
test "parse_thousandths 小数位截断到三位" {
  debug_inspect(parse_thousandths("1"), content="Some(1000)")
  debug_inspect(parse_thousandths("1.5"), content="Some(1500)")
  debug_inspect(parse_thousandths("1.0009"), content="Some(1000)")
  debug_inspect(parse_thousandths(".5"), content="None")
}

///|
/// 上界要连小数部分一起算。`2147483.999` 的整数部分看着合规，
/// 但 `×1000` 之后连小数一起越界，实测回绕成 `-2147483297`。
test "parse_thousandths 上界连小数位一起判" {
  debug_inspect(parse_thousandths("2147483"), content="Some(2147483000)")
  debug_inspect(parse_thousandths("2147483.647"), content="Some(2147483647)")
  debug_inspect(parse_thousandths("2147483.648"), content="None")
  debug_inspect(parse_thousandths("2147483.999"), content="None")
  debug_inspect(parse_thousandths("2147484"), content="None")
}

///|
/// 这里的所有输入都曾经回绕成过合法数字：
/// `2147483647` 给 `Some(-1)`、`99999999999999` 给 `Some(1569324)`、
/// `16777216m` 给 `Some(-128000)`。三个都不报错、退出码 0。
test "parse_duration_ms 超出范围返回 None" {
  debug_inspect(parse_duration_ms("2147483647"), content="Some(2147483647)")
  debug_inspect(parse_duration_ms("2147483648"), content="None")
  debug_inspect(parse_duration_ms("99999999999999"), content="None")
  debug_inspect(parse_duration_ms("9999999999s"), content="None")
  // 分钟系数是 60000，上界低得多，先撞线的应该是它
  debug_inspect(parse_duration_ms("35791m"), content="Some(2147460000)")
  debug_inspect(parse_duration_ms("35792m"), content="None")
  debug_inspect(parse_duration_ms("16777216m"), content="None")
}

///|
/// 负数走同一条上界判断：符号在最后一步才加回去，
/// 所以 `-2147483647` 合法，但绝对值超了照样拒绝。
test "parse_duration_ms 负数的上界判断一致" {
  debug_inspect(parse_duration_ms("-2147483647"), content="Some(-2147483647)")
  debug_inspect(parse_duration_ms("-2147483648"), content="None")
  debug_inspect(parse_duration_ms("-35792m"), content="None")
}
