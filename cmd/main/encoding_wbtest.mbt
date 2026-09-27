///|
/// `cmd/main` 的白盒测试：读文件的编码校验。
///
/// 这些函数（`read_text` / `load`）是包内私有的，所以测试文件用 `_wbtest.mbt`
/// 后缀 —— 黑盒测试拿不到它们。
///
/// 测试要真的读写文件，所以在项目根下开一个临时目录。`moon test` 的工作目录
/// 是项目根（不是包目录），所以这个相对路径在本地和 CI 上都一样。

///|
/// 临时目录名。测试之间共用，文件名各自取，避免撞车。
const TMP_DIR : String = "_test_tmp"

///|
/// 确保临时目录存在。已经存在时 `create_dir` 会报错，忽略即可。
fn ensure_tmp_dir() -> Unit {
  if !@fs.path_exists(TMP_DIR) {
    let _ = @fs.create_dir(TMP_DIR) catch { @fs.IOError(_) => () }
  }
}

///|
/// 写测试文件，失败时把原因交给调用方。
///
/// 不在这里断言：这个函数没有 raise 上下文。调用方拿到 `Err` 立刻 `fail`，
/// 避免"文件根本没写上"被后面的断言当成通过。
fn write_file(path : String, bytes : Bytes) -> Result[Unit, String] {
  Ok(@fs.write_bytes_to_file(path, bytes)) catch {
    @fs.IOError(msg) => Err(msg)
  }
}

///|
/// 删掉临时文件。删不掉不影响断言结果，忽略。
fn cleanup(path : String) -> Unit {
  let _ = @fs.remove_file(path) catch { @fs.IOError(_) => () }
}

///|
/// 准备一个测试文件，写不成就让测试直接红。
fn prepare(path : String, bytes : Bytes) -> Unit raise {
  match write_file(path, bytes) {
    Ok(_) => ()
    Err(msg) =>
      fail("准备测试文件失败，写不了 " + path + "：" + msg)
  }
}

///|
test "read_text 收下合法 UTF-8" {
  ensure_tmp_dir()
  let path = TMP_DIR + "/ok_utf8.srt"
  prepare(path, b"1\n00:00:01,000 --> 00:00:04,000\n你好\n")
  match read_text(path) {
    Ok(text) => assert_true(text.contains("你好"))
    Err(msg) => fail("合法 UTF-8 不该失败：" + msg)
  }
  cleanup(path)
}

///|
/// 这条是 Issue #6 的核心。修之前 `read_file_to_string(encoding="utf8")`
/// 会让非法字节**静默通过**，退出码 0，而字节在读取时就已被改写。
/// `C4 E3 BA C3` 是 GBK 的「你好」，不是合法 UTF-8。
test "read_text 拒绝非法 UTF-8 并说明原因" {
  ensure_tmp_dir()
  let path = TMP_DIR + "/bad_gbk.srt"
  prepare(path, b"1\n00:00:01,000 --> 00:00:04,000\n\xC4\xE3\xBA\xC3\n")
  match read_text(path) {
    Ok(_) => fail("非法 UTF-8 必须被拒绝，不能静默通过")
    Err(msg) => {
      assert_true(msg.contains(path))
      assert_true(msg.contains("不是合法的 UTF-8"))
    }
  }
  cleanup(path)
}

///|
/// BOM 要原样保留成 U+FEFF：`load` 里判断 WebVTT 靠的就是
/// `has_prefix("\u{FEFF}WEBVTT")`，这里吞掉 BOM 会让那条分支失效。
test "read_text 保留 BOM" {
  ensure_tmp_dir()
  let path = TMP_DIR + "/bom.srt"
  prepare(path, b"\xEF\xBB\xBF1\n00:00:01,000 --> 00:00:04,000\n你好\n")
  match read_text(path) {
    Ok(text) => assert_true(text.has_prefix("\u{FEFF}"))
    Err(msg) => fail("带 BOM 的合法 UTF-8 不该失败：" + msg)
  }
  cleanup(path)
}

///|
/// 纯 ASCII 是 UTF-8 的子集，不能被误判。
test "read_text 收下纯 ASCII" {
  ensure_tmp_dir()
  let path = TMP_DIR + "/ascii.srt"
  prepare(path, b"1\n00:00:01,000 --> 00:00:04,000\nhello\n")
  match read_text(path) {
    Ok(text) => assert_true(text.contains("hello"))
    Err(msg) => fail("纯 ASCII 不该失败：" + msg)
  }
  cleanup(path)
}

///|
/// 端到端：`load` 是各子命令读文件的唯一入口，
/// 它必须在解析之前就挡下编码问题 —— 否则解析器会对着乱码干活。
test "load 对 GBK 文件整体失败" {
  ensure_tmp_dir()
  let path = TMP_DIR + "/bad_gbk.vtt"
  prepare(path, b"WEBVTT\n\n00:00:01.000 --> 00:00:04.000\n\xC4\xE3\xBA\xC3\n")
  match load(path) {
    Ok(_) => fail("GBK 文件必须被拒绝")
    Err(msg) => assert_true(msg.contains("不是合法的 UTF-8"))
  }
  cleanup(path)
}
