# moonbit-subtitle

纯 MoonBit 实现的字幕处理库：解析、变换、渲染 SRT 与 WebVTT，附一个命令行工具。

为 2026 MoonBit 九月黑客松而建。API 仍在 0.1.x，会变。

## 这个库解决什么问题

SRT 看着简单，实际从字幕组、剪辑软件、在线平台导出的文件里常混着这些东西：

- 文件开头的 UTF-8 BOM
- Windows 的 CRLF 换行
- 序号跳号、乱序、重复
- 相邻字幕时间重叠几十毫秒，部分播放器会闪烁或丢行
- 时间行两侧多余空格，或者时间后面跟着排版坐标 `X1:100 X2:500`
- 正文里的空行（有些字幕组这么排版）

现成的字幕工具大多假设输入是干净的，遇到这些要么报错，要么静默丢字幕 ——
后者更麻烦，往往到成片导出之后才发现少了几行。

这个库的取舍是：**能救回来的救回来，救不回来的按块号明确报错。**

## 状态

| 模块 | 状态 |
|---|---|
| `time.mbt` 时间戳解析与格式化 | 完成 |
| `text.mbt` 两种格式共用的文本处理 | 完成 |
| `subtitle.mbt` 数据模型与时间轴变换 | 完成 |
| `srt.mbt` SRT 解析与渲染 | 完成 |
| `vtt.mbt` WebVTT 解析与渲染 | 完成 |
| `markup.mbt` 标记剥离与实体解码 | 完成 |
| `duration.mbt` 时间量解析（`1.5s` / `500ms`） | 完成 |
| `cmd/main` 命令行工具 | 完成 |
| `property_wbtest.mbt` 属性测试 | 完成 |

`moon test` 全部通过：97 项，其中 8 项是 quickcheck 属性测试，
覆盖往返一致性与时间轴不变量（详见 [property_wbtest.mbt](property_wbtest.mbt)）。

## 构建与测试

需要 MoonBit 工具链（https://www.moonbitlang.com/download/）。

```
moon check          # 类型检查
moon build          # 构建
moon test           # 跑测试
moon run cmd/main   # 运行命令行程序
```

库的用法示例在 [README.mbt.md](README.mbt.md)，那些代码块由 `moon test` 校验。

## 命令行的用法

`shift`、`normalize`、`convert`、`strip` 都按输入格式写回：VTT 进去还是 VTT 出来，
要换格式显式写 `convert`。不给 `-o` 就打到标准输出。

`examples/messy.srt` 是一份故意做脏的文件：带 BOM、CRLF、跳号、
重叠、时间行多余空格和排版坐标。下面是它的真实输出。

```
$ moon run cmd/main -- info examples/messy.srt
文件：examples/messy.srt
格式：SRT
条数：4
总时长：00:00:11,000
首条：00:00:01,000
末条：00:00:12,000
```

`normalize` 做三件事：按开始时间排序、合并重叠、序号重排成一到 n。

```
$ moon run cmd/main -- normalize examples/messy.srt
1
00:00:01,000 --> 00:00:07,000
这一行是普通的字幕
序号比上一条小，但时间靠前
而且时间行两边有多余空格
序号跳到了 5，而且和上一条重叠

2
00:00:09,000 --> 00:00:12,000
这一条时间最晚
```

平移量写 `-500` 是毫秒，也可以写 `-1.5s`、`2m`。平移后出现负时间的条目会贴到 0。

```
$ moon run cmd/main -- shift examples/sample.vtt -1.5s
WEBVTT

00:00:00.000 --> 00:00:02.500
这一行是 WebVTT
```

```
$ moon run cmd/main -- convert examples/messy.srt --to vtt -o out.vtt
```

`strip` 把正文里的排版标记剥掉，序号、时间轴、cue 标识都留着，
这个形态适合喂给翻译、语音合成、全文检索。
`examples/marked.vtt` 里塞了四种写法：`<b>` 加粗、`<c.yellow>` 类选择器、
`<v 张三>` 说话人、`<00:00:09.000>` 卡拉OK 时间戳标签，外加 `&amp;` 实体。

```
$ moon run cmd/main -- strip examples/marked.vtt
WEBVTT

intro
00:00:01.000 --> 00:00:04.000
欢迎收看今晚的节目

speaker
00:00:05.000 --> 00:00:08.000
这句由张三说
A & B 中间还有一个字面的 &lt; 实体
```

注意最后那行：原文写的是 `&amp;lt;`，解出来是字面的 `&lt;` 而不是 `<`。
`&amp;` 放在最后一步替换就是为了这个 —— 顺序反了会解两次。

退出码：`0` 正常，`1` 文件处理失败，`2` 参数写错。

## 设计决定

**时间统一用毫秒整数。** 用浮点秒数做平移和缩放会有累积误差，长视频里最后几行字幕会明显漂移。

**手写字符串切分，不用正则。** MoonBit 核心库没有内置正则，`moonbitlang/regexp` 仍是 alpha。
时间戳的规则足够简单，手写切分反而更可控。

**数据类型用 `pub` 而非 `pub(all)`。** 其他包能读字段、能模式匹配，但不能凭空构造。
一份合法的时间值只能由解析函数产生，校验逻辑因此只有一个出口。

**库本体零第三方依赖。** 解析、变换、渲染只用核心库。
唯一的外部依赖 `moonbitlang/x` 只出现在 `cmd/main` 里，用来读写文件 ——
核心库至今没有文件 IO。库本体被引入时不会带上它。

**块形状对不上就报错，不做静默猜测。** 一条坏掉的字幕不会被悄悄并进上一条的正文，
而是带着块号返回错误：`第 2 块：第二行不是时间行：…`。

**默认不剥标记。** 剥掉之后还原不回来，信息一旦在解析阶段丢掉，
连"要不要剥"这个选择都没了。所以只在 `markup.mbt` 里留一个显式入口，
解析和渲染都不动标记。

## 已知限制

- 只按 UTF-8 读文件；GBK 编码的字幕需要先转换
- 时间精度到毫秒，再小的单位会被截断
- 时间行右侧的排版设置（WebVTT 的 `align:start position:10%`、SRT 的 `X1:100 X2:500`）
  解析时读掉不保存，转换一圈回来会消失，字幕位置回到播放器的默认值
- WebVTT 的 `NOTE` / `STYLE` / `REGION` 块整块跳过，原文不保留
- native 目标需要 C 编译器，本机没装，所以 `moon.mod` 里把 `preferred_target` 定为 wasm

## 许可证

MIT
