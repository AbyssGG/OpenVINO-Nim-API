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

### 2026-09-24 Phase 2: first verified slice, status codes and element types

Added `src/openvino/raw/common.nim`, a C ABI probe in `tests/abi/`, the
`nimble testAbi` entry point, and a separate `--styleCheck:usages` pass over
the raw layer in `nimble lint`.

The probe is compiled against the pinned headers and linked into the Nim
test, so the C side of every comparison is produced by the compiler rather
than transcribed a second time. Each enumerator appears once, next to its own
name, through a macro that stringifies it; an enumerator renamed upstream
fails to compile in the probe, which is the intended alarm.

22 ABI tests pass. The comparisons are driven from the C side, so a status
code or element type that exists in the header but not in the binding fails
the count check rather than going unnoticed.

Verified the test is not vacuous by setting `U8` to `13`, the value the
prototype bound. Two tests failed and `nimble testAbi` exited 1, so this
check would have caught the data-corruption defect from the audit.

Layout facts now confirmed rather than assumed. The `ov_profiling_info_t`
status field has the same width as a C enum, which the prototype declared as
`int32` without checking. `ov_shape_t` is an `int64` rank followed by a
pointer. `ov_property_t`, `ov_version_t`, `ov_profiling_info_list_t` and
`ov_callback_t` are all two-pointer structs. Nim's `bool` matches C `bool`,
which matters because `ov_model_is_dynamic` returns one.

Two Nimble and toolchain constraints surfaced while wiring the task.
NimScript has no path `/` operator, so paths are joined as strings. More
interesting, Nim forwards a `--passC` value to the C compiler verbatim, so an
include path such as `C:/Program Files (x86)/Intel/...` is split on its
spaces and gcc reports `Files: No such file or directory`. Rather than fight
nested quoting, the task sets `CPATH` and `INCLUDE`, which gcc, clang and
MSVC read and which need no quoting at all.

`nimble testAbi` refuses to run without the headers. It looks at
`OPENVINO_INCLUDE_DIR`, then at `INTEL_OPENVINO_DIR`, and on failure prints
what it needed, what it tried and how to fix it, then exits 1. It never skips
and reports success.

Still to do in this phase: the loader implementation and the remaining raw
modules for property, core, shape, node, model, compiled model, tensor and
infer request, plus the required-symbol test, the Core smoke test and the
`ov_tensor_set_shape` by-value regression. Nothing in the package calls
OpenVINO yet.

### 2026-09-24 Phase 2: the loader, and the first real calls into OpenVINO

Added `openvino/raw/loader`, `error`, `shape`, `core` and `tensor`, plus
`tests/abi/tsmoke_runtime.nim` and `nimble testSmoke`. All 8 smoke tests pass
against the installed runtime, so the package now genuinely calls OpenVINO.

Before writing the loader, one more measurement settled its shape. A `dynlib`
given as a runtime variable rather than a constant still loads during module
initialisation, and the diagnostic is worse: the message reads
`could not load: ` with an empty name, because the variable has not been
assigned yet when the init-time load runs. The variable form is therefore
strictly worse than the constant form, and ADR 0001 stands.

Bindings are declared through an `{.openvinoImport.}` macro pragma, so a
binding is a single declaration that reads like the C prototype it mirrors:

```nim
proc ov_core_create*(core: ptr ptr ov_core_t): ov_status_e {.openvinoImport.}
```

The expansion adds a cached procedure pointer, resolves it through
`functionSymbol` on first call, and forwards the arguments. The imported C
name is the Nim procedure's own name, so the two cannot disagree, and there is
no per-function boilerplate to keep in step.

The by-value regression for `ov_tensor_set_shape` asserts more than a success
status. It creates a tensor, replaces its shape, then reads the shape back and
requires the observed dimensions, element count, byte size and element type to
match what was requested. A pointer-passing declaration, which is what the
prototype had, would hand OpenVINO the wrong bytes; only checking the observed
result distinguishes a correct signature from one that merely fails to crash.

A deployment lesson came out of getting the smoke test to run. The library
would not load even when given its full path, with the file demonstrably
present on disk. The cause was a missing dependency: `openvino_c.dll` needs
`openvino.dll` beside it, and that needs the bundled oneTBB library from the
runtime's `3rdparty` directory, which is a different directory. This is
exactly the case the deployment hint warns about, so the loader now
distinguishes "no such file" from "file exists but could not be loaded" and
says that the second means a dependency is missing, not a wrong path.

Two Nim details worth recording. `return` is not allowed inside a `unittest`
`test` block, because the block is a template body, so early-exit guards are
written as nested conditions. And Nim now warns that an implicit `string` to
`cstring` conversion from a non-const location will become an error, so
`symAddr` calls convert explicitly.

Still to do in this phase: raw modules for property, node, model, compiled
model and infer request, and extending the required-symbol list as they land.

### 2026-09-24 Phase 2 complete: full raw surface, prototype deleted

Added the remaining raw modules for property, node, model, compiled model and
infer request, plus `openvino/raw` as the explicit entry point for the layer.
9 smoke tests pass against the installed runtime.

Deleted `src/resonance/`, `src/resonance.nim`, `examples/basic_infer.nim` and
with them `perf_count_wrapper.c`. That wrapper existed to bridge MinGW to MSVC
varargs so that profiling could be switched on; the non-variadic
`ov_compiled_model_set_properties` and the exported
`ov_property_key_enable_profiling` data symbol replace it outright, and both
are now bound and exercised. The prototype is recoverable from the
`archive/resonance-before-openvino-nim` tag and from `AbyssGG/Resonance`.

With the prototype gone, the `skipDirs` and `skipFiles` exclusions in
`openvino.nimble` are removed, and the legacy exclusion list that `lint`
reported on every run is now empty.

Ownership asymmetries that the header forced into the design, each recorded in
the doc comment of the function it applies to. `ov_get_error_info` returns a
process-lifetime pointer that must never be freed, while
`ov_get_last_err_msg` returns an allocated string that must be. Ports come in
const and mutable flavours with separate release functions, and only the const
one accepts the metadata getters. Property keys are exported data symbols, so
each is a nullary procedure rather than a Nim `const`, because a `const`
cannot hold a value resolved at run time.

Windows wide-path model reading is declared as `ptr uint16` rather than a Nim
wide-string type, so that the element width is stated rather than assumed, and
only under `when defined(windows)` because the header guards it.

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

### 2026-09-24 Phase 2：第一个已验证切面，状态码与元素类型

加入 `src/openvino/raw/common.nim`、`tests/abi/` 下的 C ABI probe、
`nimble testAbi` 入口，以及 `nimble lint` 中对 raw 层单独执行的
`--styleCheck:usages` 检查。

probe 针对固定 header 编译并链接进 Nim 测试，因此每次比对的 C 一侧都由编译器
产生，而不是再手抄一遍。每个枚举值只出现一次，紧挨着自己的名字，由一个宏做
字符串化；上游改名会让 probe 编译失败，这正是预期的报警方式。

22 个 ABI 测试通过。比对由 C 一侧驱动，因此 header 里存在而绑定里缺失的状态码
或元素类型会让计数检查失败，不会被悄悄漏过。

通过把 `U8` 改成原型绑定的 `13` 验证了该测试并非空转：两个测试失败，
`nimble testAbi` 以 1 退出。也就是说这个检查确实能抓住审计发现的数据损坏缺陷。

若干布局事实现在是确认的而非假定的。`ov_profiling_info_t` 的 status 字段宽度
与 C enum 相同，而原型未经核对就声明为 `int32`。`ov_shape_t` 是一个 `int64`
rank 后跟一个指针。`ov_property_t`、`ov_version_t`、
`ov_profiling_info_list_t` 与 `ov_callback_t` 均为双指针结构。Nim 的 `bool`
与 C `bool` 一致，这一点重要，因为 `ov_model_is_dynamic` 返回它。

接线过程中暴露了两个 Nimble 与工具链约束。NimScript 没有路径 `/` 操作符，
所以路径改用字符串拼接。更值得记的是，Nim 会把 `--passC` 的值原样转交 C
编译器，于是像 `C:/Program Files (x86)/Intel/...` 这样的 include 路径会在
空格处被切碎，gcc 报 `Files: No such file or directory`。与其和嵌套引号纠缠，
该任务改为设置 `CPATH` 与 `INCLUDE`——gcc、clang 与 MSVC 都读取它们，且完全
不需要引号。

`nimble testAbi` 在缺少 header 时拒绝运行。它先查 `OPENVINO_INCLUDE_DIR`，
再查 `INTEL_OPENVINO_DIR`，失败时打印需要什么、尝试过什么、如何修复，然后以
1 退出。它绝不会跳过并报告成功。

本阶段尚未完成：加载器实现，以及 property、core、shape、node、model、
compiled model、tensor、infer request 各 raw 模块，加上必需符号测试、Core
smoke test 和 `ov_tensor_set_shape` 的按值传参回归测试。包内目前仍无任何代码
调用 OpenVINO。

### 2026-09-24 Phase 2：加载器，以及第一次真正调用 OpenVINO

加入 `openvino/raw/loader`、`error`、`shape`、`core`、`tensor`，以及
`tests/abi/tsmoke_runtime.nim` 与 `nimble testSmoke`。8 个 smoke 测试针对已
安装的 runtime 全部通过，包内现在确实会调用 OpenVINO 了。

写加载器之前又做了一次测量来确定其形态。把 `dynlib` 写成运行期变量而非常量，
仍然在模块初始化阶段加载，而且诊断更差：消息是 `could not load: `，库名为空，
因为初始化期加载时该变量还没被赋值。所以变量形式严格差于常量形式，ADR 0001
的结论成立。

绑定通过 `{.openvinoImport.}` 宏 pragma 声明，因此一个绑定就是一行、读起来
与它镜像的 C 原型一致：

```nim
proc ov_core_create*(core: ptr ptr ov_core_t): ov_status_e {.openvinoImport.}
```

展开后会添加一个缓存的过程指针，首次调用时经 `functionSymbol` 解析，然后转发
参数。导入的 C 名称就是 Nim 过程自己的名字，两者无法不一致，也没有需要同步
维护的逐函数样板。

`ov_tensor_set_shape` 的按值回归测试断言的不只是成功状态。它创建 tensor、
替换 shape，然后把 shape 读回来，要求观测到的维度、元素数、字节数与元素类型
都与请求一致。传指针的声明——也就是原型的写法——会把错误的字节交给 OpenVINO；
只有检查观测结果才能区分"签名正确"与"恰好没崩"。

让 smoke 测试跑起来的过程带来一个部署层面的教训。即使给出完整路径、文件明明
存在于磁盘上，库依然加载失败。原因是依赖缺失：`openvino_c.dll` 需要同目录的
`openvino.dll`，而后者需要 runtime 的 `3rdparty` 目录下自带的 oneTBB 库——那
是另一个目录。这正是 deployment hint 警告的情形，因此加载器现在会区分"文件
不存在"与"文件存在但加载失败"，并说明后者意味着依赖缺失，而不是路径写错。

两个值得记录的 Nim 细节。`unittest` 的 `test` 块内不允许 `return`，因为那是
模板体，所以提前退出改写成嵌套条件。另外 Nim 现在会警告：从非 const 位置发生
的 `string` 到 `cstring` 隐式转换将来会成为错误，因此 `symAddr` 调用改为显式
转换。

本阶段尚未完成：property、node、model、compiled model、infer request 各 raw
模块，以及随其落地扩充必需符号列表。

### 2026-09-24 Phase 2 收尾：raw 面补齐，原型删除

补上 property、node、model、compiled model、infer request 各 raw 模块，以及
`openvino/raw` 作为该层的显式入口。9 个 smoke 测试针对已安装 runtime 通过。

删除 `src/resonance/`、`src/resonance.nim`、`examples/basic_infer.nim`，连带
`perf_count_wrapper.c`。那个 wrapper 的存在只为桥接 MinGW 到 MSVC 的 variadic
调用以便开启 profiling；非 variadic 的 `ov_compiled_model_set_properties` 与
导出的 `ov_property_key_enable_profiling` 数据符号把它完全取代，两者现在都已
绑定并被测试覆盖。原型可从 `archive/resonance-before-openvino-nim` 标签以及
`AbyssGG/Resonance` 恢复。

原型删除后，`openvino.nimble` 里的 `skipDirs` 与 `skipFiles` 排除项一并移除，
`lint` 每次运行都会报告的 legacy 排除列表现在为空。

header 强加给设计的几处所有权不对称，各自记录在对应函数的文档注释里。
`ov_get_error_info` 返回进程生命周期指针、绝不能释放，而
`ov_get_last_err_msg` 返回必须释放的分配字符串。port 分 const 与可变两种、
各有独立释放函数，且只有 const 那种能用于 metadata getter。property key 是
导出的数据符号，因此每个都是无参过程而不是 Nim `const`——`const` 无法持有运行期
解析的值。

Windows 宽路径读模型声明为 `ptr uint16` 而非 Nim 宽字符串类型，以便显式陈述
元素宽度而不是假定，并且只在 `when defined(windows)` 下声明，因为 header 对它
加了守卫。
