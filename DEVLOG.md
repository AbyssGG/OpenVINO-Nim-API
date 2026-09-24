# Development log / 开发日志

A dated record of what actually happened while building `openvino-nim`:
decisions, measurements, and the assumptions that turned out to be wrong.

`openvino-nim` 构建过程的按日记录：做了哪些决定、测了哪些事实，以及哪些
原有假设被推翻。

## How to read this log / 阅读说明

This log is written in both English and Chinese. The two halves below carry
the same entries in the same order. Any change must update both halves in the
same commit; `nimble lint` fails when the two halves hold a different number
of entries.

本文分英文与中文两部分，条目内容与顺序一致。任何改动必须在同一个提交里同时
更新两部分；两部分条目数不一致时 `nimble lint` 会失败。

This log is not a changelog. `CHANGELOG.md` records what changed for a user
of the package. This log records why, what was measured, and what is still
open. Where the two overlap, the changelog is the shorter statement.

本文不是 changelog。`CHANGELOG.md` 记录对使用者可见的变化；本文记录原因、
实测结果和尚未关闭的问题。两者重叠处以 changelog 的简短陈述为准。

Phase numbers refer to
[OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md).

阶段编号对应
[OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md)。

## English

### 2026-09-24 Phase 0: audit the prototype and freeze the scope

Audited the Resonance prototype that this package replaces, and verified the
plan's ABI claims against the pinned OpenVINO `2026.4.0` headers instead of
trusting them. Recorded the result in `docs/resonance-audit.md`, including
the SHA-256 of all 18 C headers.

Three defects in the prototype were confirmed by reading the headers.

`ov_common.h` shows status `-10` is `NOT_ALLOCATED`, not `ALLOCATED`, and
that four C-wrapper codes `-14` to `-17` were missing entirely.

The element-type problem is worse than the plan described. `ov_element_type_e`
rises implicitly from `DYNAMIC = 0U` to `F8E8M0`, 26 values in total, so
`U2`, `U3` and `U6` being absent shifts everything from `U8` upward by three.
The prototype bound `U8 = 13` where the real value is `16`. Any `u8` input
tensor was therefore handed to the runtime as a `U3` low-precision type. This
is a data-corruption defect, not a naming slip.

`ov_tensor.h` declares `ov_tensor_set_shape(ov_tensor_t*, const ov_shape_t)`,
taking the shape **by value**. The prototype passed a pointer. The same header
also declares `ov_tensor_create`, which lets OpenVINO own the storage, and
which the prototype never bound at all. That absence is why the prototype
only had an external host-pointer path.

`ov_common.h` states that `ov_get_error_info` returns a process-lifetime
pointer that must never be passed to `ov_free`, while `ov_get_last_err_msg`
returns an allocated string that must be. The prototype leaked the latter on
every failure.

Also found: the prototype's `perf_count_wrapper.c` is compiled
unconditionally, so a Linux build could never have succeeded, and it bridges
MinGW to MSVC varargs using the compiler-private `ms_abi` attribute.

One environment drift: the plan records Nim 2.2.10 on this machine; the
measured version is 2.2.12.

Open at the end of the phase: the baseline commit needed an authorisation
that cannot be derived from the plan.

### 2026-09-24 Phase 1: package skeleton, licence and minimal build

Added the `openvino` Nimble package, the layered source tree, the Apache-2.0
`LICENSE`, `README.md`, `CONTRIBUTING.md`, `STYLE_GUIDE.md`, `.editorconfig`,
a Google-based `.clang-format`, `.gitignore`, a first unit test, a Markdown
checker and a blocking CI workflow.

`src/openvino/version.nim` is the single source of truth for the package
version, the minimum Nim version and the pinned OpenVINO baseline.

Nimble imposed two constraints that only surfaced by running it.

`requires` must be a string literal. Nimble parses the manifest twice, once
declaratively and once in the VM, and rejects the package when the two
disagree; a computed dependency is invisible to the declarative parser.

Later, the packaging test showed that no manifest value may be computed by
reading a file. Nimble copies the manifest into the installed package and
flattens `srcDir`, so `staticRead("src/openvino/version.nim")` failed with
"cannot open file" for every consumer resolving the dependency. Both values
are now literals, and `nimble releaseCheck` asserts each one against the
version module, plus rejects any manifest that reads files while being
evaluated.

The same packaging test showed the installed package shipped the whole
prototype, letting a consumer `import resonance` and get the defective
binding. Fixed with `skipDirs` and `skipFiles`. Their paths are relative to
the package root and must keep the `src/` prefix even though installation
flattens `srcDir`; spelling them relative to `srcDir` excludes nothing and
fails silently.

Three self-reference bugs appeared in checks that scan repository text. The
`styleChecks: off` allowlist flagged the manifest, which stores that pragma
text as its search needle. The guard against reading files at manifest
evaluation time then matched its own error message, and after that its own
search literal. The lesson is recorded in the plan: any check that scans
repository text must be shown not to match its own implementation.

This machine has `core.autocrlf=true`, which would give every fresh checkout
CRLF and fail `nimble lint` through no fault of the contributor. Fixed with
`.gitattributes` declaring `* text=auto eol=lf`, so the rule travels with the
repository instead of depending on each developer's configuration.

Queried the official Nimble index: 2945 packages, none named `openvino`, and
no near-match containing `openvino` or `vino`.

Confirmed that `AbyssGG/Resonance` is already published under Apache-2.0 and
that all 11 local prototype files are byte-identical to its `main` branch.
That closes the provenance question and means the prototype could always have
been recovered from its published history. `AbyssGG/Isvik` and
`AbyssGG/NimVoice` are downstream consumers, which confirms the dependency
direction the plan assumes.

With authorisation, created a baseline commit tagged
`archive/resonance-before-openvino-nim`, then removed `resonance.nimble` so
Nimble would accept the package.

Open at the end of the phase: Linux compilation, which only CI's first run
can confirm.

### 2026-09-24 Phase 2: pin the C API surface and decide symbol loading

Extracted the full ABI surface from the six remaining headers and wrote
`docs/c-api-coverage.md`, classifying every C entry point as bound, planned
or out of scope, with its header, ownership rules and by-value facts.

Facts worth stating from that extraction. `ov_property_t.value` is
`const void*`, so a string value is a reinterpreted `const char*`. The first
field of `ov_profiling_info_t` is an anonymous nested enum, which the
prototype declared as `int32`; it happens to match but must be probed.
`ov_port_get_any_name` and `ov_port_get_element_type` accept only the
**const** port, which is a distinct type from the mutable port with its own
release function. Property keys are exported `const char*` data symbols, so
resolving one is a different operation from resolving a function.

Two experiments were run before writing any binding, and both overturned an
assumption.

An enum whose explicit values descend, the way the prototype declared
`ov_status_e`, compiles without complaint. The status-code defect was
therefore semantic, and no compiler would ever have caught it. The raw layer
still avoids Nim enums for `ov_status_e` and `ov_element_type_e`, using a
`cint` alias with constants, because casting an unexpected value from the
runtime into a Nim enum leaves it holding an illegal value.

Nim's `dynlib` pragma loads during module initialisation and cannot report
failure to Nim code. A program declaring a procedure against a missing
library printed `could not load: <lib>` and exited 1 before the first
statement of its own body. That makes `OpenVinoLibraryError`, checklist item
C13 and the diagnostics required by plan sections 8.5 and 12.3 unreachable
with the pragma. The raw layer will therefore resolve symbols explicitly with
`loadLib` and `symAddr`, as recorded in
[ADR 0001](docs/decisions/0001-symbol-loading.md).

That decision carries one documented exception to the rule that the raw layer
raises nothing: the loader must raise, because a call that never happened has
no `ov_status_e` to return, and reusing `GENERAL_ERROR` would merge "OpenVINO
is not installed" with "OpenVINO rejected your arguments".

Added `src/openvino/private/library.nim`, the only module that knows a
platform-specific library name, with a `-d:openvinoLib=` compile-time
override. It reports which names to try and never loads, searches the
filesystem or touches environment variables.

Still to do in this phase: the nine raw binding modules, the loader
implementation, the C ABI probe, the required-symbol test, the Core smoke
test and the `nimble testAbi` entry point. No raw bindings exist yet, so
nothing in the package calls OpenVINO.

## 中文

### 2026-09-24 Phase 0：审计原型并冻结范围

审计了本包要取代的 Resonance 原型，并且没有采信计划里的 ABI 论断，而是逐项
核对固定的 OpenVINO `2026.4.0` 头文件。结果写入 `docs/resonance-audit.md`，
含全部 18 个 C 头文件的 SHA-256。

读 header 确认了原型的三个缺陷。

`ov_common.h` 显示状态码 `-10` 是 `NOT_ALLOCATED` 而非 `ALLOCATED`，并且
`-14` 到 `-17` 四个 C wrapper 错误码完全缺失。

元素类型问题比计划描述的严重。`ov_element_type_e` 从 `DYNAMIC = 0U` 起隐式
递增到 `F8E8M0`，共 26 个值，因此缺少 `U2`、`U3`、`U6` 会让 `U8` 及其之后
全部偏移 3。原型把 `U8` 绑成 `13`，真实值是 `16`。任何按 `u8` 传入的输入
tensor 都会被 runtime 当作 `U3` 低精度类型解释。这是数据损坏级缺陷，不是
命名疏漏。

`ov_tensor.h` 声明 `ov_tensor_set_shape(ov_tensor_t*, const ov_shape_t)`，
shape **按值**传递，而原型传的是指针。同一 header 还声明了
`ov_tensor_create`，由 OpenVINO 持有存储，原型完全没有绑定——这正是原型只有
外部 host pointer 一条路径的根因。

`ov_common.h` 明确写出 `ov_get_error_info` 返回进程生命周期指针、绝不能传给
`ov_free`，而 `ov_get_last_err_msg` 返回的分配字符串必须释放。原型在每次
失败时泄漏后者。

另外发现：原型的 `perf_count_wrapper.c` 被无条件编译，所以 Linux 构建从来
不可能成功，而且它用编译器专有的 `ms_abi` attribute 做 MinGW 到 MSVC 的
variadic 桥接。

一处环境漂移：计划记载本机 Nim 2.2.10，实测为 2.2.12。

阶段结束时未关闭项：基线提交需要一项不能从计划推导的授权。

### 2026-09-24 Phase 1：项目骨架、许可证与最小构建

加入 `openvino` Nimble 包、分层源码目录、Apache-2.0 `LICENSE`、
`README.md`、`CONTRIBUTING.md`、`STYLE_GUIDE.md`、`.editorconfig`、基于
Google 风格的 `.clang-format`、`.gitignore`、第一个单元测试、Markdown
检查器和阻断式 CI 工作流。

`src/openvino/version.nim` 是包版本、最低 Nim 版本与固定 OpenVINO 基线的
唯一事实来源。

Nimble 有两个只有真正运行才会暴露的约束。

`requires` 必须是字符串字面量。Nimble 对 manifest 做两遍解析，一次声明式、
一次 VM 求值，两者不一致就拒绝整个包；计算出的依赖对声明式解析器不可见。

后来打包测试又表明，任何 manifest 字段都不能靠读文件得到。Nimble 会把
manifest 复制进安装后的包并摊平 `srcDir`，于是
`staticRead("src/openvino/version.nim")` 在依赖解析时对每个使用者都报
"cannot open file"。现在两个值都是字面量，`nimble releaseCheck` 反向断言
它们与版本模块一致，并拒绝任何在求值期读文件的 manifest。

同一个打包测试还显示安装后的包携带了整个原型，使用者能 `import resonance`
拿到有缺陷的绑定。用 `skipDirs` 与 `skipFiles` 修复。它们的路径相对包根
目录，即使安装会摊平 `srcDir` 也必须保留 `src/` 前缀；按 `srcDir` 相对书写
不会报错但什么也不排除，是静默失效。

扫描仓库文本的检查里出现了三次自指 bug。`styleChecks: off` 的 allowlist
命中了 manifest 本身，因为它把该 pragma 文本存作搜索串。随后"禁止 manifest
求值期读文件"的检查先命中自己的错误信息，再命中自己的检查字面量。教训已写
入计划：任何扫描仓库文本的检查都必须证明它不会命中自己的实现。

本机 `core.autocrlf=true`，会让任何新检出得到 CRLF 并使 `nimble lint` 失败，
而贡献者毫无过错。用 `.gitattributes` 声明 `* text=auto eol=lf` 修复，规则
随仓库传播，不依赖每个人的配置。

查询官方 Nimble 索引：2945 个包，无名为 `openvino` 者，也没有任何包含
`openvino` 或 `vino` 的近似名。

确认 `AbyssGG/Resonance` 已以 Apache-2.0 发布，且本地 11 个原型文件与其
`main` 分支字节级一致。这关闭了来源归属问题，也说明原型一直可以从已发布
历史恢复。`AbyssGG/Isvik` 与 `AbyssGG/NimVoice` 是下游消费者，印证了计划
假定的依赖方向。

在取得授权后建立基线提交并打上 `archive/resonance-before-openvino-nim`
标签，随后删除 `resonance.nimble` 以让 Nimble 接受该包。

阶段结束时未关闭项：Linux 编译，只能由 CI 的首次运行确认。

### 2026-09-24 Phase 2：固定 C API 面并决定符号加载方式

从其余六个 header 抽出完整 ABI 面，写成 `docs/c-api-coverage.md`，把每个
C 入口分类为 bound、planned 或 out of scope，并记录所属 header、所有权规则
与按值传参事实。

抽取过程中值得单独记下的事实：`ov_property_t.value` 是 `const void*`，因此
字符串值是重解释的 `const char*`。`ov_profiling_info_t` 的第一个字段是匿名
嵌套 enum，原型声明为 `int32`，碰巧吻合但必须 probe。
`ov_port_get_any_name` 与 `ov_port_get_element_type` 只接受 **const** port，
它与可变 port 是不同类型、有各自的释放函数。property key 是导出的
`const char*` 数据符号，解析它与解析函数是两种不同操作。

在写任何绑定之前跑了两个实验，两者都推翻了原有假设。

按原型那样给出降序显式值的 enum，编译毫无怨言。因此状态码缺陷是语义错误，
任何编译器都不会拦住。raw 层仍然不为 `ov_status_e` 与
`ov_element_type_e` 使用 Nim enum，而采用 `cint` 别名加常量，因为把 runtime
返回的意外值转入 Nim enum 会让它持有非法值。

Nim 的 `dynlib` pragma 在模块初始化阶段加载，无法把失败报告给 Nim 代码。
一个对缺失库声明过程的程序，在自己主体的第一条语句之前就打印
`could not load: <lib>` 并以 1 退出。这使得 `OpenVinoLibraryError`、
Checklist 项 C13 以及计划 §8.5 与 §12.3 要求的诊断在使用该 pragma 时无法
实现。因此 raw 层改用 `loadLib` 与 `symAddr` 显式解析符号，决策记录于
[ADR 0001](docs/decisions/0001-symbol-loading.md)。

该决策带来一条有记录的例外，针对"raw 层不抛异常"这条规则：加载器必须抛出，
因为一个从未发生的调用没有 `ov_status_e` 可返回，而复用 `GENERAL_ERROR`
会把"OpenVINO 没有安装"与"OpenVINO 拒绝了你的参数"混为一谈。

加入 `src/openvino/private/library.nim`，它是唯一知道平台相关库名的模块，
提供 `-d:openvinoLib=` 编译期覆盖。它只报告应尝试哪些名字，不做加载、不扫描
文件系统、不改动环境变量。

本阶段尚未完成：九个 raw 绑定模块、加载器实现、C ABI probe、必需符号测试、
Core smoke test 以及 `nimble testAbi` 入口。目前尚无任何 raw 绑定，因此包内
没有任何代码调用 OpenVINO。
