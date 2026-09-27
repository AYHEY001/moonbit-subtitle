///|
/// `info` 的展示逻辑（白盒）。
///
/// 这些函数是包内私有的，所以要放在 `_wbtest.mbt` 里测 ——
/// 黑盒测试文件会被编成独立的包，看不到它们。
/// 只测纯字符串拼装，不去真的跑命令：那部分要读写文件，
/// 已经由 `encoding_wbtest.mbt` 端到端覆盖了。

///|
test "文件头说明只取元数据行" {
  inspect(
    describe_header("WEBVTT\nKind: captions\nLanguage: zh"),
    content="Kind: captions、Language: zh",
  )
  // 只有一行元数据时不出现多余的分隔符
  inspect(describe_header("WEBVTT\nLanguage: zh"), content="Language: zh")
}

///|
test "没有元数据行的文件头不产生说明" {
  // 空串是"没有文件头"在模型里的表示
  inspect(describe_header(""), content="")
  // 光签名行同理
  inspect(describe_header("WEBVTT"), content="")
  // 签名行后面的说明文字不是元数据行，跳过它 —— 每份文件都可能有一句，
  // 报出来只是噪音
  inspect(describe_header("WEBVTT - 中文字幕"), content="")
}

///|
test "文件头说明会去掉每行的首尾空白" {
  inspect(
    describe_header("WEBVTT\n  Language: zh  \n\n"),
    content="Language: zh",
  )
}
