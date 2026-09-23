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
/// 把 `00:01:23,456` 或 `00:01:23.456` 解析为毫秒数。
/// 格式不合法时返回 `None`。
///
/// 参数名前面带下划线表示"暂时没用到"。实现的时候把下划线去掉，
/// 编译器就不再认为它是闲置参数了。
pub fn parse_timestamp(_raw : String) -> Int? {
  // TODO(D2)：String::split 切成 [时, 分, 秒毫秒]，
  // 第三段再按 ',' 或 '.' 切成秒和毫秒。
  // 边界条件：毫秒必须恰好三位；时分秒必须是纯数字；空串要拒掉。
  None
}

///|
/// 把毫秒数格式化成 SRT 风格的时间戳 `00:01:23,456`。
/// 负数一律按 0 处理。
pub fn format_timestamp(_ms : Int) -> String {
  // TODO(D2)
  ""
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
