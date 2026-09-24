# OpenVINO Nim API 0.1.0 开发流程与 AI 开发代理执行规范

> 本文档是 `D:\nim\openvino-nim` 从 Resonance 原型整理为社区维护的 OpenVINO Nim API 的开发基线，可直接作为任意 AI 编程助手或人工开发团队的主任务说明。
>
> 执行者必须按阶段推进。只有在当前阶段的验收门禁有可复核证据时，才可以勾选完成并进入下一阶段。若本文与 OpenVINO 2026.4 官方 C 头文件冲突，以固定版本的官方头文件为准，并在 `docs/decisions/` 中记录差异和处理决定。

## 0. 通用 AI 开发代理执行入口

可把本文与下面这段指令一起交给任意支持仓库读写、命令执行和测试的 AI 编程助手：

```text
请在 D:\nim\openvino-nim 中完整阅读并按本开发流程执行 OpenVINO Nim API 0.1.0 重构。
先执行 Phase 0，报告现状、风险和 Gate 结果；只有当前 Gate 通过后才进入下一 Phase。
持续维护本文 Checklist，并为每个勾选项保留文件、测试输出或 CI 证据。
允许的 Git、远端、tag 和发布动作只以我当前明确授予的权限为准，不要从文档目标推导额外授权。
遇到 ABI、所有权或上游行为不明确时，先核对固定的 OpenVINO 2026.4.0 官方 header/source，记录 ADR，不要猜测。
```

若项目所有者希望 AI 开发代理连续完成多个 Phase，应在交付时额外说明是否允许创建本地分支/提交；这不自动包含 push、tag、PR 或 release 权限。

## 1. 项目元数据

| 项目 | 约定 |
|---|---|
| 项目名 | OpenVINO Nim API |
| 对外包名/仓库名/发行名 | `openvino-nim` |
| Nimble 包标识 | `openvino`（Nimble 标识不允许连字符，并与导入根模块一致） |
| Nimble 清单文件 | `openvino.nimble` |
| Nim 导入入口 | `import openvino` |
| 首个版本 | `0.1.0` |
| OpenVINO 基线 | `2026.4.x`，首个验证版本为 `2026.4.0` |
| 许可证 | Apache-2.0 |
| 项目性质 | 社区维护、非 Intel/OpenVINO 官方项目 |
| 当前源码位置 | `D:\nim\openvino-nim` |
| 最低 Nim 版本候选 | `2.0.0`；发布前以 CI 实测结果为准 |
| Tier 1 平台 | Windows x86_64、Linux x86_64 |
| 发布基线设备 | CPU；GPU/NPU 不得成为构建或发布前置条件 |

### 1.1 一句话定位

为 Nim 提供两层 OpenVINO Runtime 接口：一层是可审计、与 OpenVINO 2026.4 C ABI 对齐的 raw binding；另一层是符合 Nim 使用习惯、具备明确错误和资源生命周期语义的 managed API。

### 1.2 0.1.0 完成定义

只有同时满足以下条件，才能宣布 `0.1.0` 完成：

1. Windows x86_64 和 Linux x86_64 均可通过 `import openvino` 使用 managed API。
2. raw 层与 OpenVINO 2026.4 头文件的关键类型、枚举值、结构体布局、调用约定和所需符号通过 ABI 验证。
3. 可完成一条真实 CPU 推理闭环：创建 Core、读模型、编译、创建 Tensor 和 InferRequest、设置输入、同步推理、读取并验证输出。
4. 所有 native handle 都有单一、可审计、可重复测试的释放策略；double close 无害，use-after-close 在进入 C 层前失败。
5. 没有把 Resonance/Isvik 的缓存策略、设备策略、业务流程或品牌概念混入公共 API。
6. Tier 1 CI、示例、API 文档、安装文档、Apache-2.0 `LICENSE`、`CHANGELOG` 和兼容矩阵齐全。
7. 在全新环境中用固定的 OpenVINO 2026.4 runtime 完成安装、构建和 CPU 推理验证。

---

## 2. 当前仓库基线与已知阻断项

本节记录 2026-09-24 对 `D:\nim\openvino-nim` 的只读审计结果。实施前必须再次核对，不能假定工作树仍保持不变。

Phase 0 已于 2026-09-24 执行完毕，逐项证据见 `docs/resonance-audit.md`。本节中所有 ABI 结论均已通过读取本机固定 2026.4.0 header 复核，复核发现的偏差记录在 §2.5。

### 2.1 当前状态

- Git 分支为 `main`，尚无提交、无 remote；`src/`、`examples/` 和 `resonance.nimble` 均未跟踪（Phase 0 复核仍成立）。
- 当前入口为 `src/resonance.nim`，子模块包括 `c_api`、`errors`、`core`、`model`、`compiled_model`、`infer_request`、`tensor`。
- `examples/basic_infer.nim` 实际只演示设备枚举和编译/导入缓存，没有设置 Tensor、执行 infer 或验证输出。
- 当前只有 `.nimble` 中的 Apache-2.0 元数据，没有实际 `LICENSE` 文件。
- 当前没有 README、测试、CI、CHANGELOG、CONTRIBUTING、`.gitignore` 或 API 文档。
- 本机实测 Nim 2.2.12（Windows amd64）和 OpenVINO 2026.4.0；OpenVINO 安装目录仅可作为本机审计依据，绝不能写死进库代码。
- 本机 OpenVINO 通过符号链接 `openvino_2026` → `openvino_2026.4.0` 暴露；固定版本时必须解析到带完整三段版本号的实际目录，不能依赖会随升级漂移的 `openvino_2026`。
- 本机未发现 runtime 二进制、构建产物、模型权重、cache blob 或 credentials；全部 14 个未跟踪文件均为手写源码与文档，可以进入基线提交。

### 2.2 必须先修复的 ABI 问题

这些问题禁止用“先沿用、以后再修”的方式带入新 raw 层。“2026.4 要求”一列已由 Phase 0 读取本机固定 header 逐项核对，括号内为对应 header 及其 SHA-256 前 8 位：

| 问题 | 当前情况 | 2026.4 要求 | 处理 |
|---|---|---|---|
| 元素类型枚举错位 | `U1 = 11` 之后直接写 `U4 = 12`、`U8 = 13`，并在 `U64 = 16` 截止 | `ov_element_type_e` 自 `DYNAMIC = 0U` 隐式递增至 `F8E8M0`，共 26 个值（0–25）；`U2 = 12`、`U3 = 13`、`U4 = 14`、`U6 = 15`、`U8 = 16`（`ov_common.h` / `a5dd4572`） | 从 2026.4 头文件重新建立 raw 常量并做全 26 值 ABI probe，不复制旧枚举 |
| 元素类型偏移的实际后果 | 旧绑定 `U8` 比真实值小 3 | 任何按 `U8` 传入的输入会被 runtime 当作 `U3` 低精度类型解释 | 视为数据损坏级缺陷，Phase 2 Gate 阻断项 |
| 状态码错误 | `-10` 被写为 `ALLOCATED`，并缺少 `-14..-17` | `-10` 是 `NOT_ALLOCATED`；C wrapper 错误码为 `INVALID_C_PARAM = -14`、`UNKNOWN_C_ERROR = -15`、`NOT_IMPLEMENT_C_METHOD = -16`、`UNKNOW_EXCEPTION = -17`，合计 18 个值（`ov_common.h` / `a5dd4572`） | 重新绑定并逐值验证；保留上游 `UNKNOW_EXCEPTION` 拼写 |
| `ov_tensor_set_shape` 签名错误 | 旧绑定传 `ptr OvShape` | 声明为 `ov_tensor_set_shape(ov_tensor_t*, const ov_shape_t)`，按值传结构体；`ov_tensor_create`、`ov_tensor_create_from_host_ptr`、`ov_tensor_create_from_string_array` 同样按值接收 `const ov_shape_t`（`ov_tensor.h` / `01c3e0de`） | 修正签名，加入实际调用与 ABI 回归测试 |
| `ov_tensor_create` 未绑定 | 旧 raw 层只有 `ov_tensor_create_from_host_ptr` | `ov_tensor.h` 提供 `ov_tensor_create`，由 OpenVINO 用默认 allocator 分配内部 host 存储（`ov_tensor.h` / `01c3e0de`） | 绑定该函数，并作为 §6.4 安全默认 `newTensor` 的实现基础 |
| last error 泄漏 | 当前把 `ov_get_last_err_msg()` 转成 Nim string 后不释放 | 2026.4 实现返回需由 `ov_free()` 释放的分配字符串；同一 header 注释明确 `ov_get_error_info` 的返回值是进程生命周期静态指针且 MUST NOT 传给 `ov_free`（`ov_common.h` / `a5dd4572`） | 失败后立即复制，并在 `finally` 中 `ov_free`；`ov_get_error_info` 静态字符串则绝不能释放 |
| C enum 布局未验证 | 依赖 Nim 默认 enum 布局 | C ABI 通常按 `int`，但必须实测 | raw 层使用明确 ABI 表示并验证 `sizeof`/值 |
| 平台写死 | 固定 `openvino_c.dll`，并无条件编译 Win32 C 桥 | Tier 1 至少 Windows/Linux | 集中库名选择，移除无条件 Windows 代码 |
| 手写 property key | `OvPropertyKeyEnableProfiling* = "PERF_COUNT"` 为手写字符串 | property key 是 runtime 导出的 `const char*` 数据符号 | 绑定官方数据符号，删除手写常量 |
| profiling 列表释放条件错误 | `getProfilingInfo` 仅在 `infoList.size > 0` 时调用 free | 释放合约由函数成功与否决定，不由元素数量决定 | 成功即无条件释放；`size == 0` 同样释放 |
| raw 与安全层混导出 | 顶层直接导出 `c_api` 和公开可写裸指针 | 默认入口不得暴露不安全所有权 | raw 只能由 `openvino/raw` 显式导入 |

### 2.3 2026.4 带来的关键设计变化

OpenVINO 2026.4 C API 已提供适合 FFI 的非可变参数属性接口，包括 `ov_property_t`、`ov_core_set_properties`、`ov_core_compile_model_props`、`ov_core_compile_model_from_file_props` 和 `ov_compiled_model_set_properties`。

因此：

- 禁止在新实现中调用 C 可变参数 API。
- 删除 `perf_count_wrapper.c` 和自定义 `nv_*` 导出，不把 MinGW/MSVC variadic ABI 桥接保留下来。
- profiling 通过通用 properties API 和官方 `ov_property_key_enable_profiling` 实现，不使用手写字符串常量或 NPU 专用入口。
- `_props` API 是本项目要求 OpenVINO 2026.4.x 的直接原因之一；不承诺在旧 runtime 上静默降级。

### 2.4 迁移红线

- 在建立可恢复基线前，不得批量删除或重命名现有 Resonance 文件。
- 不得对现有 `c_api.nim` 做机械改名后宣称完成 2026.4 绑定。
- 不得在测试缺失时把旧公开裸 handle 继续导出。
- 不得把本机 OpenVINO 安装绝对路径、DLL、插件或 SDK 二进制提交到仓库。
- 不得把“能编译”视为 ABI 正确；raw 层必须通过 C probe 和真实 runtime smoke test。

### 2.5 Phase 0 复核发现的计划偏差

按 §17 规则 15，本节记录本文原有技术假设与实测结果不符之处。更正依据全部是本机固定 2026.4.0 header 与工具链实测，不是推断。

| 本文原假设 | 实测结果 | 处理 |
|---|---|---|
| 本机 Nim 2.2.10 | `nim --version` 报 Nim 2.2.12（Windows amd64） | §2.1 已更正；Phase 1 pin 工具链时以实测版本为基准，不沿用 2.2.10 |
| 元素类型问题描述为“`U1` 后缺 `U2`、`U3`，`U4` 后缺 `U6`” | 缺失导致 `U8` 起的全部值偏移 3，且总数为 26（新增 `F4E2M1`、`F8E8M0`） | §2.2 已改为逐值描述并补充数据损坏后果 |
| —（本文未提及） | header 符号拼写为 `F8E5M3`，而其自身注释写 `f8e5m2` | 列为 ABI 例外：raw 层保留符号名 `F8E5M3`，禁止按注释“纠正”；probe 必须覆盖该值 |
| —（本文未提及） | 旧 raw 层完全没有绑定 `ov_tensor_create` | §2.2 新增对应行；这是旧实现只能走外部 host pointer 的根因 |
| —（本文未提及） | `getProfilingInfo` 用 `size > 0` 作为释放条件 | §2.2 新增对应行，与 §10.2 的释放合约一致 |

`perf_count_wrapper.c` 的逐行复核补充证据，全部支持 §2.3 的删除决定：

- 无条件 `{.compile: "perf_count_wrapper.c".}`，Linux 构建必然失败。
- 依赖 `__declspec(dllimport)`、`LoadLibraryA`、`GetProcAddress`。
- 依赖 GCC 专有 `__attribute__((ms_abi))` 做 MinGW→MSVC variadic 桥接。
- 硬编码 `"openvino_c.dll"` 与 `"PERF_COUNT"`。
- 解析失败与调用失败一律返回 `-1`（`GENERAL_ERROR`），丢失真实状态码。

### 2.6 Phase 1 发现的阻断项：双 manifest 冲突

本文原先假定可以在保留 `resonance.nimble` 的同时新增 `openvino.nimble`，并在 Phase 1 Gate 验证 `nimble check`。实测这两件事互斥。

Nimble 对每个包只接受一个 manifest。在两个 `.nimble` 并存时，`nimble check` 直接失败：

```text
    Error:  Only one .nimble file should be present in D:\nim\openvino-nim
   Failure: Validation failed.
```

这不是警告，而是包级校验失败，因此 `nimble check`、`nimble install`、`nimble` 任务和打包测试在冲突解除前全部不可用。

影响的 Checklist 项：B08 的 Linux 侧、B09 打包实测、S15 的本地/CI 一致性验证，以及 Phase 1 Gate 中的 `nimble check` 条目。

已采取的规避措施：Phase 1 的 manifest 与任务在一个排除了 `resonance.nimble` 的临时工作副本中验证，工作树本身未被改动。`nimble check`、`formatCheck`、`lint`、`test`、`docs`、`releaseCheck` 全部在该副本中通过。这是规避，不是关闭；只有真实工作树上的 `nimble check` 通过才算 Gate 达成。

解除冲突需要项目所有者在以下两者中明确选一项，二者都不能由本文推导：

1. 授权建立可恢复基线（A08），随后按 §7.4 删除 `resonance.nimble`；旧内容由基线提交保留。
2. 授权把 `resonance.nimble` 移出仓库根目录；这属于 §16 Phase 0 Gate 明令禁止的“改名包入口”，因此必须是所有者的显式例外决定，并记录风险。

在授权到达前，不得删除或移动 `resonance.nimble`。

### 2.7 Phase 1 发现的 Nimble manifest 约束

`requires` 不能使用计算值。Nimble 会对 manifest 做两次解析——一次声明式静态解析，一次 VM 求值——并在两者结果不一致时拒绝整个包：

```text
     Info:  Parsed declarative dependencies: @[]
     Info:  Parsed VM dependencies: @[nim@>= 2.0.0]
    Error:  Parsed declarative and VM dependencies are not the same
```

因此 `requires "nim >= 2.0.0"` 必须写成字符串字面量。为了不牺牲 B07 的单一事实来源，改为反向约束：`nimble releaseCheck` 读取 manifest 文本，断言其中存在与 `version.nim` 的 `MinimumNimVersion` 完全对应的 `requires` 字面量。`version` 字段本身仍可由 `staticRead` 派生，实测不受该限制影响。

### 2.8 本机 Git 环境与 LF 策略

建立基线前对 Git 环境的实测结果：

| 配置 | 实测值 | 影响 |
|---|---|---|
| `core.autocrlf` | `true` | 检出时把文本文件转成 CRLF |
| `user.name` | 未设置 | 无法创建提交 |
| `user.email` | 未设置 | 无法创建提交 |

`core.autocrlf=true` 与本项目的 LF 要求直接冲突。`.editorconfig` 和 `nimble lint` 都要求工作树中为 LF，而在该配置下任何新检出都会得到 CRLF，导致贡献者在完全没有改动代码的情况下 lint 失败。

处理方式：新增 `.gitattributes`，声明 `* text=auto eol=lf`。`eol=lf` 优先于 `core.autocrlf`，因此 LF 策略随仓库传播，而不依赖每位开发者的 Git 配置。二进制 fixture 扩展名单独标记为 `binary`，防止被转换。这条修复不改动任何 Git 配置。

`user.name` / `user.email` 未设置是 A08 的实际执行阻断项。按 §17 规则 2 与本文的 Git 安全约束，AI 开发代理不得自行设定提交身份，也不得凭猜测填写邮箱——错误的作者信息一旦进入历史，只能靠被禁止的历史改写来纠正。因此基线提交需要项目所有者提供确切的 name 与 email。

---

## 3. 范围与非目标

### 3.1 0.1.0 必须包含

#### Raw binding

- 版本、公共状态码、错误信息和释放函数。
- Core 与可用设备枚举。
- `ov_property_t` 以及 0.1.0 所需的非 variadic properties API。
- Model、输入/输出 port 和必要元数据。
- CompiledModel、模型 import/export。
- Tensor、静态 shape、元素类型、大小和数据访问。
- InferRequest 的输入/输出 Tensor、同步推理和 profiling 信息。
- 完成上述功能所需的字符串、数组和 opaque handle 类型。

#### Managed API

- runtime 版本查询和支持版本诊断。
- `Core`、`Model`、`Port`、`CompiledModel`、`InferRequest`、`Tensor`。
- 读模型、按设备编译、import/export compiled model。
- 设备枚举和基础 property 设置/读取。
- 输入/输出数量、名称、元素类型和 shape 查询。
- OpenVINO 自有内存 Tensor；从 Nim 数据安全复制创建 Tensor。
- 明确标为 unsafe 的外部 host pointer/零拷贝入口，或能可靠持有 owner 的安全入口。
- 同步推理、profiling 信息复制。
- 统一异常、统一 close/析构语义。
- Windows 非 ASCII 模型路径的明确支持方案与测试。

#### 工程质量

- Windows x86_64 与 Linux x86_64 的 CPU 集成测试。
- ABI、单元、失败路径、生命周期压力、打包和文档测试。
- 至少三个可运行示例：设备枚举、同步推理、Tensor/shape 使用；profiling 可作为第四个示例。
- README、API 文档、ownership 文档、C API coverage、迁移说明和故障排查。

### 3.2 可选但不阻断 0.1.0

- 无 callback 的 `startAsync` / `wait` / `cancel` managed API；只有生命周期和线程测试全部通过后才可加入稳定入口。
- macOS 构建或运行支持；只有官方 2026.4 C runtime 和 CI 实测均具备时才写入兼容表。
- GPU/NPU 手工 smoke test 或自托管 runner。
- partial shape、layout、pre/post-processing 的 raw 覆盖；除非同步推理闭环确实需要，否则不得拖延 0.1.0。

### 3.3 明确非目标

- OpenVINO C++ API、C++ ABI 或 opset/图构建 API。
- 首版覆盖全部 OpenVINO C headers。
- 训练框架或模型转换工具的 Nim 封装。
- Remote Tensor、VAAPI、DirectX、OpenCL context 等设备专用能力。
- callback 式异步 managed API；C 回调与 Nim GC/线程模型需要独立设计。
- 自动下载模型、模型仓库、业务预处理/后处理流水线。
- 自动选择设备、失败后设备回退、隐式开启缓存或 profiling。
- Resonance/Isvik 的日志、CLI、配置、模型发现、调度、缓存命名、任务标签或业务策略。
- 对 OpenVINO 2026.3、2027.x 或未实测 patch 版本的兼容承诺。
- 将 OpenVINO runtime、插件 DLL/SO 或大模型打包进 Nimble 包。

---

## 4. 架构分层

依赖只允许自上而下：

```text
用户程序 / Resonance / Isvik
              |
              v
src/openvino.nim                 稳定公共入口
              |
              v
src/openvino/*.nim               managed API
              |
              v
src/openvino/raw/*.nim           OpenVINO 2026.4 C ABI
              |
              v
OpenVINO 2026.4 C Runtime
```

### 4.1 Raw 层

- 名称尽量对应 C API，便于逐项与头文件核对。
- 只表达 ABI：类型、常量、结构体、函数、调用约定和动态库符号。
- 不抛 Nim 异常，不加入缓存、默认设备、日志或数据复制策略。
- opaque handle 只声明不透明类型；不猜测内部布局。
- 对 C `const` 在 Nim 无法完全表达的地方，通过命名、文档和 managed 边界保持只读语义。
- raw 层是高级用户可显式导入的接口，但 0.x 期间只保证“与固定 header 对齐”，不承诺 managed 级别的源码稳定性。

### 4.2 Managed 层

- 对 native handle 提供一致所有权和关闭状态。
- 检查参数，转换状态码，立即复制错误详情。
- 把 native 字符串、数组和 profiling 数据复制到 Nim 管理内存后释放原生容器。
- 默认提供安全、显式的行为；有复制、阻塞或 native 调用时必须在 API 文档中说明。
- 不让普通用户接触裸指针；必要的 escape hatch 必须包含 `unsafe` 命名并返回 borrowed handle。

### 4.3 稳定入口

- `import openvino` 只导出已承诺的 managed API。
- 不导出 raw、private、experimental 模块。
- `import openvino/raw` 才能使用 C 风格接口。
- 实验功能使用 `openvino/experimental/...`，并在文档中明确不受 0.x 稳定性承诺。

### 4.4 依赖约束

- `raw` 不得依赖 managed 层。
- `private` 不得被顶层入口导出。
- `openvino` 包不得 import Resonance 或 Isvik。
- `errors`、`properties`、`handles` 等底层模块不得反向依赖 `core`、`model` 等上层模块。
- 不建立隐式全局 `Core` 或全局可变配置。

---

## 5. 目标目录结构

```text
D:\nim\openvino-nim\
├─ .github\
│  └─ workflows\
│     ├─ ci.yml
│     └─ release.yml
├─ .clang-format
├─ .editorconfig
├─ docs\
│  ├─ architecture.md
│  ├─ c-api-coverage.md
│  ├─ compatibility.md
│  ├─ ownership.md
│  ├─ resonance-migration.md
│  ├─ troubleshooting.md
│  └─ decisions\
│     └─ 0001-handle-model.md
├─ examples\
│  ├─ list_devices.nim
│  ├─ sync_infer.nim
│  ├─ tensor_basics.nim
│  └─ profiling.nim
├─ src\
│  ├─ openvino.nim
│  └─ openvino\
│     ├─ raw.nim
│     ├─ raw\
│     │  ├─ common.nim
│     │  ├─ property.nim
│     │  ├─ core.nim
│     │  ├─ shape.nim
│     │  ├─ node.nim
│     │  ├─ model.nim
│     │  ├─ compiled_model.nim
│     │  ├─ tensor.nim
│     │  └─ infer_request.nim
│     ├─ errors.nim
│     ├─ version.nim
│     ├─ properties.nim
│     ├─ shape.nim
│     ├─ node.nim
│     ├─ core.nim
│     ├─ model.nim
│     ├─ compiled_model.nim
│     ├─ tensor.nim
│     ├─ infer_request.nim
│     └─ private\
│        ├─ library.nim
│        ├─ handles.nim
│        └─ conversions.nim
├─ tests\
│  ├─ abi\
│  │  ├─ abi_probe.c
│  │  └─ tabi_layout.nim
│  ├─ fixtures\
│  │  ├─ README.md
│  │  └─ <small deterministic model files>
│  ├─ integration\
│  ├─ lifecycle\
│  └─ unit\
├─ tools\
│  ├─ README.md
│  └─ <binding audit/update scripts if adopted>
├─ .gitignore
├─ CHANGELOG.md
├─ CONTRIBUTING.md
├─ LICENSE
├─ README.md
├─ STYLE_GUIDE.md
└─ openvino.nimble
```

说明：

- 不要求一开始创建所有空文件；文件必须随着所属阶段的真实实现落地。
- 若 raw 绑定由工具生成，生成器、版本锁定信息和生成结果必须一起提交。
- fixture 必须体积小、离线可用、输出确定，并记录来源、许可证和 SHA-256。
- 旧 `resonance.nimble` 与 `src/resonance/` 只有在基线可恢复、迁移清单完成后才可移除。

---

## 6. API 设计原则

### 6.1 命名与可见性

- raw 层保留 `ov_*` C 名称；managed 层使用 Nim 风格，例如 `newCore`、`readModel`、`compileModel`、`createInferRequest`、`setInputTensor`、`infer`。
- managed 类型使用 `Core`、`Model`、`Port`、`CompiledModel`、`InferRequest`、`Tensor`、`OpenVinoError`。
- native handle 字段必须私有。
- 如确有互操作需求，提供名称明确的 `unsafeRawHandle`，返回值始终是 borrowed；调用者不得释放。
- 顶层入口只导出 0.1.0 稳定清单，避免“先全部 export 再收回”。

### 6.2 行为必须显式

- 不隐式选择 `CPU`、`GPU` 或 `NPU`。
- 不隐式设备回退。
- 不隐式创建目录、读写 blob、下载模型或修改环境变量。
- 不隐式开启 profiling、cache 或性能 hint。
- 文件 I/O、数据复制、阻塞推理和 native 调用必须能从 proc 名称或文档看出。
- optional 参数使用 overload、`Option` 或清晰类型，不用空字符串同时表达“没有值”和合法值。
- index 在转为 `csize_t` 前检查非负和范围。

### 6.3 属性 API

- raw 层直接绑定 `ov_property_t` 与官方导出的 property key。
- managed 层首版优先支持字符串值的通用 `Property`/`openArray[Property]`。
- 指针值、加密 callback 或设备 handle 等属性仅留在 raw/experimental，除非有独立类型和生命周期设计。
- 编译模型时统一使用 properties 参数，不增加 `compileModelWithProfiling` 之类功能重复入口。
- profiling 是 `enableProfiling` 属性与 `profilingInfo` 查询的组合，不是 NPU 特例。

### 6.4 Tensor API

- 默认 `newTensor[T](shape)` 由 OpenVINO 分配存储，或 `tensorFromSeq` 明确复制数据到自有 Tensor。
- 零拷贝 host pointer 必须显式命名为 unsafe，或者让 Tensor 强持有 owner，并在文档中说明 owner 与 buffer 不得发生重分配。
- typed 数据访问必须验证 OpenVINO element type、元素数和字节容量。
- `shape`、元素总数和字节数的乘法必须检查负维度与整数溢出。
- 返回裸视图时必须说明：Tensor close、reshape 或 owner 失效后视图立即失效。
- 为一般使用提供复制到 `seq[T]` 的安全入口；性能敏感用户再选择显式 view/unsafe API。

### 6.5 公共 API 合入条件

任何新公共符号必须同时具备：

1. 文档注释，包含所有权、复制/阻塞行为和可能异常；
2. 至少一个成功测试；
3. 至少一个相关失败路径测试；
4. `docs/c-api-coverage.md` 或 managed API 清单更新；
5. 若用户可观察行为变化，更新 `CHANGELOG.md`。

### 6.6 0.1.0 公共能力清单

具体 Nim 签名在 Phase 3/4 由测试驱动确定，但稳定入口不得少于以下行为，也不得未经评审随意扩张：

| 模块/类型 | 0.1.0 必需行为 |
|---|---|
| Version | 查询并复制 runtime build number/description，报告支持状态 |
| Core | 创建/关闭、设备枚举、读模型、编译模型、import compiled model、基础 property set/get |
| Model | 输入/输出数量与 port metadata；关闭 |
| Port | 名称、element type、shape；按官方 ownership 关闭 |
| CompiledModel | 创建 InferRequest、port metadata、explicit export、基础 property set/get；关闭 |
| Tensor | owned 创建、copy-from-Nim、shape/type/size/byte-size、安全 copy-out、受控 view；关闭 |
| InferRequest | 按 index/name（以实际 C API 覆盖为准）设置/取得 Tensor、同步 infer、profiling；关闭 |
| Properties | 构造字符串型 property 列表，并在调用期间稳定持有 key/value |
| Errors | 统一 OpenVINO/library/version/参数错误语义 |

所有类型都应遵循同一 closed-state 规则。`startAsync`/`wait`/`cancel` 不属于本表的发布阻断项，callback 更不进入 0.1.0 稳定入口。

### 6.7 强制代码风格：Google 风格原则的 Nim 适配

Google 没有官方 Nim Style Guide，因此本项目不机械照搬 Google C++ 的语法和命名。项目采用以下组合规则：

1. ABI 层首先忠实于 OpenVINO C API；
2. Nim 语法和命名遵循 Nim 官方 Standard Library Style Guide；
3. 可读性、短函数、明确接口、注释质量和评审标准遵循 Google Style Guide 的工程原则；
4. 本节规则解决二者未覆盖或发生冲突的部分。

规则优先级为：**ABI 正确性 > Nim 语言惯例 > Google 可维护性原则 > 个人偏好**。任何例外都必须局部化、写明原因并由测试保护。

#### 6.7.1 格式

- 手写 Nim、C 和 Markdown 原则上每行不超过 80 个字符。
- URL、不可拆分字符串、表格、生成声明和会因换行而失真的命令可以超过 80 字符。
- 使用 2 个空格缩进，禁止 Tab；禁止行尾空格。
- 文件使用 UTF-8、LF 换行，并以单个换行结尾。
- 用空行分隔不同逻辑段，不在函数首尾放无意义空行，也不靠大段垂直对齐制造“表格代码”。
- 多行 proc 声明、调用、object/tuple 字段按 Nim 官方样式续行；不手工对齐远处的 `=`、类型或注释。
- 仓库根目录提供 `.editorconfig`，至少固定 charset、LF、final newline、trim trailing whitespace、2-space indentation。
- Nim 代码由项目固定 Nim 版本附带的 `nimpretty` 统一格式化；格式化后必须无语义变化。

#### 6.7.2 命名

| 对象 | 规则 | 示例 |
|---|---|---|
| managed 类型、异常、枚举 | `PascalCase`，缩写按普通单词处理 | `OpenVinoError`, `CompiledModel` |
| proc、func、变量、参数、字段 | `lowerCamelCase` | `compileModel`, `deviceName` |
| public managed 常量 | `PascalCase` | `TargetOpenVinoMajor` |
| private 常量 | `lowerCamelCase` | `defaultLibraryName` |
| Nim 文件/模块 | 小写 `snake_case`，名称描述单一职责 | `compiled_model.nim` |
| raw C 类型、函数、常量 | 保留官方 C 拼写和值 | `ov_core_create`, `ov_status_e`, `F32` |
| C probe/shim 函数和变量 | Google C/C++ 风格的小写 `snake_case` | `probe_shape_size` |
| C 宏 | `UPPER_SNAKE_CASE`，仅在确有必要时使用 | `OV_NIM_ASSERT_SIZE` |
| 测试文件 | Nim 官方测试惯例的 `t<subject>_<behavior>.nim` | `ttensor_lifecycle.nim` |
| 测试辅助模块 | `m<subject>.nim` | `mopenvino_fixture.nim` |

补充规则：

- 名称表达意图，不为省字符使用生造缩写；允许 Nim 社区通用的 `len`、`idx`、`ptr`、`msg` 等短名。
- 局部循环计数可用 `i`/`j`；跨较大作用域必须使用描述性名称。
- 布尔参数容易让调用点含糊时，改用 enum 或 options object，不堆叠多个裸 `bool`。
- 无副作用且 O(1) 的 getter 优先命名为 `shape`、`len` 等；触发 native 调用、分配、I/O 或明显计算时使用 `get...`/动作动词。
- public 名称使用稳定领域术语；同一概念不得交替使用 `request`、`req`、`infer` 等不同简称。
- 不添加类型前缀、匈牙利命名或作者缩写。
- raw 层的下划线、全大写值和上游拼写错误属于 ABI 例外，禁止为了 managed 风格擅自改名。

#### 6.7.3 Import 与模块组织

- Import 分为三组：`std`、第三方依赖、项目本地模块；组间空一行。
- 每组按字母顺序排列。多个标准库模块优先使用 `std/[...]` 的清晰写法。
- 遵循 “import what you use”：直接 import 定义所用符号的模块，不依赖其他模块的偶然间接 import。
- 禁止未使用 import、循环依赖和为了省一行而从大入口反向 import。
- 普通实现禁止使用 `include` 拼接源码；仅确定性的 generated fragment 可在记录原因后例外。
- 调用 raw API 时优先使用限定模块名或清晰别名，让不安全边界在调用点可见。
- 每个模块只承担一个清晰职责；文件名、module doc 和导出内容必须一致。
- 默认显式 export；不得用总入口把 raw/private/experimental 意外暴露出去。
- 当模块超过约 500 行或同时包含两个独立所有权域时，必须评审是否拆分；这是一条 review trigger，不是机械行数处罚。

示例：

```nim
import std/[options, strutils]

import third_party_package

import openvino/errors
import openvino/raw/core
```

#### 6.7.4 函数与接口设计

- 函数保持短小并只做一件事；超过约 40 个逻辑行时必须评审能否拆分。
- 控制流优先使用 guard clause/early return，避免超过三层的嵌套。
- 参数应有清晰名称；输入参数在前，输出/可变参数在后。
- 参数超过约 4 个、存在多个可选项或多个布尔值时，优先引入有命名字段的 options object。
- 优先返回值，不用裸 output pointer 模拟 C 风格；只有 raw ABI 层保留原始输出参数。
- 默认使用 `let`，只有确实重新赋值时使用 `var`。
- 普通结果优先写入 Nim 隐式 `result`；`return` 主要用于能简化控制流的提前退出。
- 优先普通 `proc`/`func`；只有普通过程无法表达需求时才引入 template、macro、converter 或复杂泛型。
- 不使用隐式全局状态、隐藏 I/O、隐藏环境变量修改或与函数名不符的副作用。
- 不把昂贵 native 调用伪装成字段访问或简单 accessor。

#### 6.7.5 注释与 API 文档

- 每个手写源码文件以 `SPDX-License-Identifier: Apache-2.0` 开头；不添加个人 author 行。
- 文件级 module doc 说明该模块负责什么以及明确不负责什么。
- 所有 public 类型、字段和 proc 使用 Nim `##` 文档注释；非显而易见的 private helper 也要说明契约。
- public 文档至少说明：用途、参数、返回值、所有权/借用、复制行为、阻塞行为、异常、线程限制和失效条件。
- 实现注释解释“为什么”和不变量，不逐句复述代码“做了什么”。
- 注释使用完整句子和一致术语；代码、注释和文档使用包容性语言。
- TODO 必须可追踪，例如 `TODO(#123): ...`；禁止无负责人/issue 的永久 `TODO`、`FIXME` 或“以后处理”。
- unsafe block、cast、borrowed pointer 和忽略 native 状态都必须就地解释安全前提；无法解释即不得合入。

#### 6.7.6 错误、所有权和 unsafe 代码

- 禁止裸 `discard` OpenVINO status；确实只能忽略的 release status 要有局部注释和测试依据。
- 禁止 magic status number、property string 和 dtype number；使用已验证常量。
- 不使用无类型的 `pointer` 穿过 managed 公共边界。
- `cast`、`unsafeAddr` 和 pointer arithmetic 限制在 raw/private 的最小作用域内。
- managed 层所有 unsafe escape hatch 必须在名字中含 `unsafe`，并在 doc comment 中列出调用者义务。
- 捕获具体异常；禁止没有重新抛出/转换依据的宽泛 `except:`。
- 资源获取与释放尽量放在同一可读作用域，用 `defer`/`finally` 表达异常安全。
- close/析构代码优先简单、幂等、无分配、无日志、无异常。

#### 6.7.7 C 文件、ABI probe 与生成代码

- 手写 `.c`/`.h` 使用仓库 `.clang-format`，配置基于 `BasedOnStyle: Google`，`IndentWidth: 2`、`ColumnLimit: 80`。
- ABI probe 使用 C，不因方便而引入 C++ ABI；include 顺序为对应项目 header、C 标准库、OpenVINO/第三方 header。
- 禁止可变参数、编译器私有 ABI attribute 和平台 API，除非固定 C API 无替代方案且有独立 ADR/测试。
- generated raw 文件必须包含生成器、输入 tag/commit 和“不要手改”说明；手工改生成结果视为 Gate 失败。
- 生成器重复运行必须得到零 diff；生成结果和生成器变更放在同一提交。
- 格式工具不得重命名 raw C symbol，也不得改变字段顺序、类型或调用约定。

raw 声明如需绕过 Nim managed 命名检查，只允许在批准的声明区间使用并立即恢复：

```nim
{.push styleChecks: off.}

# Generated or header-faithful OpenVINO C declarations only.

{.pop.}
```

CI 必须对 `styleChecks: off` 做目录/文件 allowlist 检查；它不得出现在 managed、测试或示例代码中。

#### 6.7.8 测试风格

- 测试名称描述可观察行为和条件，不使用 `test1`、`works`、`misc`。
- 一个测试聚焦一个主要行为；失败消息包含 operation、输入条件和期望/实际值。
- 测试遵循 Arrange / Act / Assert 的逻辑顺序，只有能提升可读性时才写分段注释。
- 测试必须确定、离线、与执行顺序无关；禁止固定 sleep 等待异步状态。
- 公共 API 的成功、边界、失败和生命周期路径放在相邻测试中，便于评审契约。
- 测试 helper 同样受生产代码风格约束；不得用大段重复代码掩盖测试意图。

#### 6.7.9 Markdown 与用户文档

- 每份文档只有一个 H1，使用 ATX 标题（`#`/`##`），标题名称唯一且完整。
- 代码块使用 fenced code block 并标注语言；命令块标注 `text`、`shell` 或对应 shell。
- 链接文字描述目标，禁止使用“点这里”；优先标准 Markdown，不用 HTML 做布局。
- 普通段落按 80 字符换行；URL、表格、标题和代码块可以例外。
- README 示例必须可复制、可运行，并由 CI 编译；注释不能代替缺失的错误处理。

#### 6.7.10 自动执行与例外管理

CI 的 `static` job 必须执行并阻断：

1. `nimble format` 对手写 `.nim`、`.nims` 和 `.nimble` 文件运行固定版本的 `nimpretty --indent:2 --maxLineLen:80`；
2. `nimble formatCheck` 在干净工作树执行相同格式化并以 `git diff --exit-code` 证明零 diff；
3. `nimble lint` 汇总 style、warning、allowlist、public-doc 和依赖边界检查；
4. 对 managed 源码、示例和测试运行 `nim check --styleCheck:error`；
5. raw C 风格符号使用单独策略：至少运行 `--styleCheck:usages`、编译和 ABI 测试，不因上游 `ov_*` 名称关闭整个仓库的 style check；
6. 对手写 C/header 运行 pinned `clang-format` dry-run/check，并在 GCC/Clang/MSVC 上以高 warning 等级和 warning-as-error 编译；
7. 检查 Tab、行尾空格、文件末尾换行、未格式化文件和未解释 lint suppression；
8. 重新运行 binding generator 并验证工作树零 diff；
9. 检查 Markdown 基础格式、链接和 fenced code block。

任何 formatter/linter 例外必须：范围最小、紧邻代码、说明原因、关联 issue/ADR，并有测试覆盖。禁止仓库级关闭规则来迁就单个 raw symbol。

---

## 7. Resonance / Isvik 边界

当前仓库中没有以 Isvik 命名的模块或直接 Isvik 业务代码；不能虚构“已有 Isvik 模块”并迁移。边界按职责而非旧文件名划分。

### 7.1 可进入 OpenVINO Nim API 的职责

- OpenVINO C ABI 声明，但必须按 2026.4 重新核对或重写。
- 通用错误转换。
- Core、Model、Port、CompiledModel、InferRequest、Tensor 的通用包装。
- 设备枚举、模型读/编译、compiled model import/export。
- 同步 infer、通用 properties、通用 profiling 数据复制。

### 7.2 必须留在 Resonance/Isvik 或下游 adapter 的职责

- `compileOrImportModel` 目前的“文件存在就导入，否则编译、建目录并导出”策略。
- cache 文件命名、cache hit tuple、失效/回退策略和应用目录选择。
- 默认设备、设备优先级、自动 fallback、NPU 特定优化和性能策略。
- 模型发现、下载、预处理、后处理、结果解释和业务数据结构。
- 日志、CLI、配置、任务调度、InferRequest 池和应用并发策略。
- Isvik 的 UI、领域对象和任何产品级默认值。

### 7.3 迁移规则

- `compileOrImportModel` 不进入稳定 Core API；通用的显式 `importModel` / `exportModel` 可以进入。
- OpenVINO 自带 cache property 可以作为通用 property 使用，但“何时启用、目录在哪、如何失效”由下游决定。
- 旧 Resonance 调用兼容层如有必要，应放在 Resonance 仓库，而不是污染 `openvino` 包。
- OpenVINO Nim API 绝不能依赖 Resonance/Isvik；依赖方向只能是 Resonance/Isvik -> OpenVINO Nim API。
- 迁移完成时，`src/openvino` 的 import、公共符号、异常文本和用户文档不得遗留 Resonance/Isvik 品牌或业务语义；迁移文档中的历史说明除外。

### 7.4 当前文件迁移映射

| 当前文件 | 迁移决定 |
|---|---|
| `src/resonance.nim` | 由新的 `src/openvino.nim` 取代；不继续无差别导出 raw API |
| `src/resonance/c_api.nim` | 不逐行迁移；按 2026.4 headers 拆分并重写为 `openvino/raw/*` |
| `src/resonance/errors.nim` | 保留“统一状态转异常”的概念；重写 last-error 复制/`ov_free` 和结构化字段 |
| `src/resonance/core.nim` | 通用 Core/读/编译/import 职责可重构；`compileOrImportModel`、隐式目录/缓存和 `nv_*` 移出 |
| `model.nim` / `compiled_model.nim` / `infer_request.nim` | 保留职责，按私有 handle、幂等 close、失败清理和 metadata 范围重写 |
| `tensor.nim` | 重写外部 buffer 生命周期、dtype/capacity/overflow 检查和安全数据入口 |
| `perf_count_wrapper.c` | 基线保存后从新包删除；由 2026.4 非 variadic property API 取代 |
| `examples/basic_infer.nim` | 不再冒充完整推理示例；拆成真实 `sync_infer` 和必要的显式 import/export/profiling 示例 |
| `resonance.nimble` | 由 `openvino.nimble` 取代；对外发行名仍为 `openvino-nim`，并先保留旧文件于可恢复基线 |

---

## 8. OpenVINO C API 绑定策略

### 8.1 唯一事实来源

- 使用 OpenVINO `2026.4.0` 官方发布包/对应 tag 的 `runtime/include/openvino/c/*.h` 作为首个事实来源。
- 固定上游 tag `2026.4.0`、发布 commit `99c8149`；不得跟随 `master`/滚动 latest 生成绑定。
- 在 `docs/c-api-coverage.md` 记录上游版本、tag/commit、获取方式和 header 集合的 SHA-256。
- 本机已安装的 2026.4 头文件可用于首次核对，但仓库代码不得依赖该绝对路径。
- 若 header、在线文档和导出符号不一致，记录证据并以实际固定发布包的 header + runtime 为发布门禁。

### 8.2 绑定方式

- 采用“raw 声明机械生成或手工逐项核对 + managed 层人工设计”的混合方式。
- 不要求最终用户安装 C headers 才能编译普通 Nim 程序；headers 只用于更新绑定和 ABI CI。
- 若生成 raw 文件，文件头写明生成命令、工具版本、输入 header 版本和“请勿手改”。
- 若手工维护 raw 文件，每个函数必须能在 coverage 表中定位到具体 header 和签名。
- 不解析或绑定 C++ headers，不链接 C++ ABI。
- OpenVINO 官方 C API 只覆盖 C++ API 的主要部分；managed API 的 0.1.0 能力边界不得超出固定 C headers 实际提供的能力。

### 8.3 ABI 表示规则

- 所有函数使用与官方宏展开一致的调用约定；Windows C API 为 `cdecl`。
- C callback 在 Windows 同样使用 `cdecl`；即使 0.1.0 不提供 callback managed API，raw ABI probe 仍应验证 callback 布局/调用约定。
- `size_t` 使用 `csize_t`，固定宽度整数使用对应 `int*_t` 语义。
- opaque struct 只声明不透明 object/指针。
- C enum 采用能保证 C `int` ABI 的表示，或显式 size pragma；无论采用哪种都必须由 C probe 验证大小和值。
- raw 名称必须忠实保留官方 ABI 拼写，包括 `UNKNOW_EXCEPTION`；managed 层可另提供更友好的展示文字，但不得改 raw 常量值/符号。
- struct 字段顺序、类型、对齐和 by-value/by-pointer 传参逐项核对。
- raw proc 的输出指针在调用前置 `nil`/零值；只有状态成功且输出非空后才交给 managed owner。
- 不用 Nim 的方便类型替代 C ABI 类型，例如不能把 `size_t` 直接假定为 `int`。

### 8.4 ABI probe 最低覆盖

`tests/abi/abi_probe.c` 编译时直接包含固定的 2026.4 C headers，并向 Nim 测试暴露或输出以下事实：

- `sizeof`/必要时 `alignof`：status/element type、`ov_shape_t`、`ov_property_t`、available devices、version、profiling info/list、callback（即使 callback 暂不包装）。
- 关键 struct 字段的 `offsetof`。
- 全部已绑定 status 和 element type 的数值。
- property key 符号能解析且值非空。
- 所有 0.1.0 必需函数符号存在。
- 至少包含一个 by-value struct 调用回归测试，重点覆盖 `ov_tensor_set_shape`。
- Core 创建/释放的 raw smoke test。

### 8.5 动态库发现

- 所有平台判断集中在 `openvino/private/library.nim` 或 raw 公共基础模块中。
- 默认候选名：Windows `openvino_c.dll`、Linux `libopenvino_c.so`、macOS `libopenvino_c.dylib`；最终名称以官方 2026.4 包和 CI 实测为准。
- 支持编译期覆盖库名，例如项目约定的 `-d:openvinoLib=...`；只覆盖“库名/路径字符串”，不改变 API。
- 不在库代码中修改进程环境变量或 PATH。
- 找不到库或必需符号时，诊断应包含：目标平台、尝试的库名、期望 OpenVINO 版本和安装/环境配置提示。
- 文档分别说明 Windows DLL 搜索路径和 Linux loader 搜索路径，不把开发机配置冒充包内自动配置。
- 仅能加载 `openvino_c` 还不等于部署完整；Core 仍可能需要同一官方 runtime 布局中的 `plugins.xml`、device plugins 和 model frontends。包不得只复制单个 DLL/SO，也不得递归扫描磁盘并静默选择任意 OpenVINO 安装。

### 8.6 Properties 与 variadic API

- 新代码一律优先并要求使用 2026.4 的 `_props` / `*_properties` 非 variadic 函数。
- raw 层可为覆盖完整性记录旧 variadic 函数，但 managed 层禁止调用，0.1.0 也无需导出。
- 删除 `perf_count_wrapper.c` 和 `nv_compile_model_with_perf_count` / `nv_enable_perf_count`。
- Property 的 key/value cstring 存储必须活到 C 调用返回；构造临时数组时由同一作用域持有字符串。
- 若未来属性值不是字符串，必须为每种值类别单独说明类型、所有权和有效期，不允许任意 `pointer` 混入稳定 managed API。
- property key 是导出的 `const char*` 数据符号，不都是宏或函数；绑定/加载方案必须能正确处理数据符号。
- 2026.4 仍有个别变参 API，例如带 subname 的 color-format 预处理接口；0.1.0 不开放这些接口，也不为它们保留通用 variadic 桥。

---

## 9. 错误策略

### 9.1 错误类型

managed 层至少区分：

- `OpenVinoError`：OpenVINO C 调用返回非 OK。
- `OpenVinoLibraryError`：动态库缺失、必需符号缺失或无法加载。
- `OpenVinoVersionError`：检测到不受支持的 runtime major/minor。
- Nim 参数错误：在进入 C 层前发现负 index、shape 非法、容量不匹配、对象已关闭等；可以使用 `ValueError` 或专用子类，但全库保持一致。

`OpenVinoError` 至少保存或呈现：

- 操作名；
- 原始数值状态码；
- `ov_get_error_info(status)` 的稳定描述；
- `ov_get_last_err_msg()` 的当次原生详情；
- 与调用相关但不泄露敏感数据的上下文，例如 device、index 或文件名。

### 9.2 状态检查规则

- raw 层原样返回 status，不抛异常。
- managed 层只通过一个统一入口检查 status，避免每个模块自行拼装错误。
- 一旦 status 失败，必须在任何后续 OpenVINO C 调用前复制 last error 文本。
- `ov_get_error_info` 返回进程生命周期内的静态字符串，绝不能释放。
- `ov_get_last_err_msg()` 在 2026.4 实现中返回新分配字符串：失败后立即取得、复制，并在 `finally` 中调用 `ov_free()`。当前实现使用全局互斥保护的 last-error 状态而非 thread-local；延迟读取可能被另一线程的失败覆盖。
- 不得忽略状态码后继续使用输出结构。
- 析构函数、finalizer 和释放兜底不得抛异常。
- 异常绝不能跨越 C callback 边界；0.1.0 不提供 callback 式 managed API。

失败处理顺序固定为：先取得 `ov_get_last_err_msg()` 指针，立即复制并 `ov_free()`；再读取无需释放的 `ov_get_error_info(status)`；最后构造并抛出 Nim 异常。last-error 指针为 `nil` 时跳过复制与释放。

### 9.3 必测错误路径

- 模型文件不存在或格式错误。
- 不存在的 device。
- 不支持或格式错误的 property。
- 负 index、越界 index。
- 空/非法 shape、负维度、元素数或字节数溢出。
- Tensor 类型或容量不匹配。
- 对已关闭对象调用方法。
- OpenVINO 动态库缺失。
- runtime 版本或必需符号不匹配。

---

## 10. 内存、所有权与生命周期策略

### 10.1 非协商语义

- 每个 native allocation 有且只有一个 owner 和一个对应 release 路径。
- managed handle 内部 native 指针私有。
- 所有 handle 提供幂等 `close()`：第一次释放并清空 handle；后续调用不再进入 native 层。
- 析构是兜底，不替代长期资源的显式 `close()`。
- 所有别名共享同一关闭状态，或值对象严格禁止复制并正确实现 move/sink；全库只能选择一种统一模型。
- Phase 3 必须用 ADR 记录最终 Nim 表示，并用 ORC、ARC（以及可行时 refc）生命周期测试证明选择。
- 任何 public 方法先检查对象是否有效；use-after-close 必须成为可预测的 Nim 错误，而不是 native 崩溃。
- 析构和异常清理路径不得 double-free，也不得抛异常。

### 10.2 Ownership 表

在 `docs/ownership.md` 为每个已绑定函数维护以下列：

| 对象/函数 | 返回所有权 | 释放函数 | 借用自谁 | 有效期 | 线程/回调约束 |
|---|---|---|---|---|---|

首版至少覆盖：

| 原生资源 | 释放函数/策略 | managed 要求 |
|---|---|---|
| `ov_core_t` | `ov_core_free` | 独占 native owner，close 幂等 |
| `ov_model_t` | `ov_model_free` | 成功读模型后才包装 |
| `ov_compiled_model_t` | `ov_compiled_model_free` | import/compile 两条路径一致 |
| `ov_infer_request_t` | `ov_infer_request_free` | 不与并发 infer 竞态 close |
| `ov_tensor_t` | `ov_tensor_free` | 区分 OpenVINO-owned 与外部 buffer |
| output port | 对应 `ov_output_port_free` / const 版本 | 明确 owned/borrowed，不凭名称猜测 |
| `ov_shape_t` 内部 dims | `ov_shape_free` | 只释放由 OpenVINO 分配的 shape |
| available devices | `ov_available_devices_free` | 先复制每个字符串，再无条件释放成功结果 |
| version | `ov_version_free` | 先复制字符串 |
| profiling list | `ov_profiling_info_list_free` | 成功获得后按合约释放，不以 `size > 0` 判断 |
| `ov_get_last_err_msg()` 结果 | `ov_free` | 失败后立即取得并复制；即使 Nim string 转换失败也在 `finally` 释放 |
| `ov_get_error_info()` 结果 | 不释放 | 进程生命周期静态指针 |
| `char*` 输出 | 依具体 API 使用 `ov_free` | 每个函数逐项记录，禁止一刀切 |

### 10.3 失败清理

- 输出指针/结构先零初始化。
- 只有 status OK 且返回值满足合约时才建立 managed owner。
- 如果失败时 API 可能产生部分分配，必须按官方合约清理；合约不明确则先记录阻断问题，不猜测。
- 所有“复制原生内容 -> 释放原生容器”流程使用 `defer`/`finally`，让字符串转换失败也能释放。
- release 返回 status 的结构（例如 shape）在普通逻辑中检查，在析构兜底中不得抛。

### 10.4 Tensor 外部内存

- 安全默认：OpenVINO-owned buffer 或复制输入数据。
- 如果从 Nim `seq`/array 零拷贝创建 Tensor，Tensor 必须持有稳定 owner，且文档禁止导致 buffer 重分配的操作。
- 如果无法证明稳定性，只提供 `newTensorFromHostPtrUnsafe` 一类显式接口，并要求调用者保证地址、对齐、容量和生命周期。
- 外部 buffer Tensor 的 owner 生命周期测试必须主动触发 GC/ORC 回收并完成推理，证明没有悬垂指针。

---

## 11. 跨平台目标

### 11.1 支持分级

| 等级 | 平台 | 0.1.0 承诺 |
|---|---|---|
| Tier 1 | Windows x86_64 | 安装、编译、ABI、CPU 推理、示例均为阻断测试 |
| Tier 1 | Linux x86_64 | 安装、编译、ABI、CPU 推理、示例和内存检查均为阻断测试 |
| Tier 2 | Linux ARM64、macOS ARM64 | 只有官方 2026.4 runtime 可得且 CI 实测后才列入兼容表；否则 best effort/未承诺 |
| Hardware optional | GPU/NPU | 手工或专用 runner；失败不阻断通用 CPU 包构建 |

### 11.2 跨平台规则

- 公共 Nim 代码不得无条件 import Win32 API 或编译 Windows C 文件。
- 动态库名、路径说明和 Unicode 文件路径实现分平台集中管理。
- 不以某台机器的 PATH、注册表或 OpenVINO 安装目录作为默认事实。
- Windows 必测非 ASCII 路径；使用官方 Unicode path API 或有证据的 UTF-8 方案。
- Unicode raw 绑定必须按平台验证 `wchar_t` 宽度，不能把 Nim `WideCString` 的某种表示假定为所有平台通用 ABI。
- Linux 发布前进行 ASan/Valgrind 等内存检查；Windows 至少执行生命周期压力与缺 DLL 诊断测试。
- CPU 是一致性基线；设备插件能力通过 available devices 动态发现，不在编译时假定存在。
- 不把 macOS x86_64 或 Windows ARM64 写成 0.1.0 支持目标，除非以后有对应官方 runtime 和完整实测证据。
- 官方 2026 系列 x86 CPU plugin 的最低指令集要求需在安装文档中说明；CI runner 必须满足上游系统要求。

---

## 12. 版本与兼容策略

### 12.1 两套版本彼此独立

- Nim 包遵循 SemVer：首版 `0.1.0`。
- OpenVINO 兼容基线单独记录：首版只声明已验证的 `2026.4.x`。
- 2026.4 当前按官方发布策略不是 LTS；项目必须固定发布包/checksum，并把上游支持周期列为兼容性风险。
- README 不得写“兼容 2026.3–2026.4”，除非相应 runtime 已进入 CI 且所有门禁通过。
- 对 2027.x 不做前向兼容推断。

### 12.2 版本演进

- 0.x 阶段，公共 Nim API 的破坏性变化提升 minor；兼容 bugfix 提升 patch。
- OpenVINO patch 更新若 ABI/行为测试通过，可只发布 Nim patch 版本。
- 切换 OpenVINO major/minor 基线至少发布新的 Nim minor，并更新 coverage、ABI fixture 与兼容矩阵。
- 候选标签：`v0.1.0-rc.1`；正式标签：`v0.1.0`。
- `CHANGELOG.md` 分开记录 Nim API 变化和 OpenVINO runtime/header 兼容变化。

### 12.3 Runtime 诊断

- 通过 `ov_get_openvino_version` 暴露原始 build number/description，并可提供尽力解析的结构化版本。
- 无法解析版本字符串时不得伪造版本；保留原始值并通过必需符号/ABI smoke 判断。
- major/minor 明确不匹配时给出可操作错误，而不是等到随机符号调用时崩溃。
- 兼容表只列出真实跑过 CI 或发布验证的 OS、架构、Nim、内存管理器和 OpenVINO 组合。

### 12.4 包名、标签与 Release 产物命名

项目必须区分下面四类名称，不能为了“统一”而把一个名字机械用于所有位置：

| 用途 | 0.1.0 约定 | 说明 |
|---|---|---|
| 对外包名、仓库名、发行名前缀 | `openvino-nim` | 用户指定的公开名称 |
| Nimble 包标识与清单文件 | `openvino`、`openvino.nimble` | Nimble 包名语法不接受 `-`；标识与根模块一致，也不改变对外发行名 |
| Nim 源码导入入口 | `import openvino` | 用户代码中的稳定模块名 |
| Git 标签 | `v0.1.0-rc.1`、`v0.1.0` | 保持标准 SemVer，不能使用长归档名替代标签 |

正式 Release 的自定义归档基名使用以下模板：

```text
openvino-nim-{nim-version-dash}-{release-date}-ov{openvino-version-dash}
```

字段规则：

- `nim-version-dash` 是本项目 SemVer 的三个数字段，并把点替换为连字符；`0.1.0` 变为 `0-1-0`。
- `release-date` 是明确指定的发布日期，格式为 `YYYY-M-D`，月和日不补零；不能直接读取 CI runner 的本地日期。
- `openvino-version-dash` 是本次实际固定并通过完整发布验证的 OpenVINO 三段版本，并把点替换为连字符；`2026.4.0` 变为 `2026-4-0`。
- 基名只使用 ASCII 小写字母、数字和连字符；扩展名之外不使用点、空格或 `+`。

因此，本项目 `0.1.0` 在 `2026-9-24` 面向 OpenVINO `2026.4.0` 的规范基名为：

```text
openvino-nim-0-1-0-2026-9-24-ov2026-4-0
```

规范发布产物为：

```text
openvino-nim-0-1-0-2026-9-24-ov2026-4-0.zip
openvino-nim-0-1-0-2026-9-24-ov2026-4-0.zip.sha256
openvino-nim-0-1-0-2026-9-24-ov2026-4-0.tar.gz
openvino-nim-0-1-0-2026-9-24-ov2026-4-0.tar.gz.sha256
```

发布约束：

- Release 展示标题建议使用 `openvino-nim 0.1.0 — 2026-9-24 — OpenVINO 2026.4.0`。
- 归档内唯一顶层目录必须与归档基名完全相同，用户解压后不会得到含糊的 `source` 或 commit hash 目录。
- 自定义 `.zip` 和 `.tar.gz` 是本项目的规范发布包；托管平台自动生成、名称不可控的 “Source code” 归档只作为附加入口，不作为命名契约。
- 源码包不得捆绑 OpenVINO runtime/SDK。以后若确有经批准的平台二进制辅助包，在规范基名后追加 `-windows-x86_64`、`-linux-x86_64` 等后缀，不能改变基名前半部分。
- 归档使用稳定的文件排序、权限和时间戳生成，并在相同 commit、相同发布元数据下验证可重复构建；每个归档旁必须提供 SHA-256 文件。
- 名称必须由发布脚本从 `openvino.nimble` 的版本、明确输入的发布日期和固定 OpenVINO 版本生成并校验，禁止在多个工作流中手工复制长文件名。
- CI 必须验证 Git 标签、本项目版本、OpenVINO 固定版本、Release 标题、归档基名、归档顶层目录和 checksum 彼此一致。

---

## 13. 测试策略与矩阵

### 13.1 测试层次

1. **静态/包检查**：模块边界、导出清单、包元数据、文档和格式。
2. **纯单元测试**：不要求 OpenVINO runtime，覆盖转换、状态、shape、溢出、closed-state 和 property 构造。
3. **ABI 测试**：用固定 2026.4 headers 编译 C probe，对比 Nim raw 类型、常量和符号。
4. **raw smoke**：加载 runtime，查询版本，创建/释放 Core。
5. **CPU 集成测试**：完整同步推理与固定输出。
6. **错误测试**：所有公开错误路径必须稳定抛错而非崩溃。
7. **生命周期压力**：循环创建/推理/释放至少 1000 次，检查 double-free、invalid access 和包装层泄漏。
8. **打包测试**：在干净临时目录安装包、只用公共入口编译并运行示例。
9. **文档测试**：README 最小代码必须真实编译。

### 13.2 最低阻断矩阵

| 组合 | Windows x64 | Linux x64 | PR 阻断 | 发布阻断 |
|---|---:|---:|---:|---:|
| 最低支持 Nim 2.0.x + ORC，unit/build | 是 | 是 | 是 | 是 |
| 固定当前稳定 Nim 2.2.x + ORC，unit/ABI/CPU integration | 是 | 是 | 是 | 是 |
| 当前稳定 Nim + ARC，unit/lifecycle | 是 | 是 | 至少代表作业 | 是 |
| 当前稳定 Nim + refc，build/unit | 条件允许 | 条件允许 | 否 | 若声明支持则是 |
| Debug 构建 | 是 | 是 | 是 | 是 |
| Release 构建与示例 | 是 | 是 | 是 | 是 |
| OpenVINO 2026.4.0 精确基线 | 是 | 是 | 是 | 是 |
| 最新已审核 2026.4 patch | 定时/发布前 | 定时/发布前 | 否 | 是 |
| ASan/Valgrind | 不要求 | 是 | 定时 | 是 |
| GPU/NPU | 可选 | 可选 | 否 | 否 |

不要在每个 PR 跑完整笛卡尔积。PR 使用代表性作业；nightly/release 扩展版本、内存管理器和压力测试。

### 13.3 必测功能

- 版本查询、设备枚举和 Core close。
- 读小型模型、获取输入/输出 metadata。
- 带空 property 和带 profiling property 的模型编译。
- Tensor 创建、shape 查询/修改、类型/容量验证、scalar 与多维 shape。
- set input、同步 infer、get output、固定数值验证。
- compiled model export/import；临时文件由测试自己管理，API 不隐式建业务 cache。
- profiling on/off；关闭时的错误/空结果行为按上游合约验证。
- 非 ASCII 路径（Windows）。
- double close、别名 close、作用域析构、异常中途清理。
- 外部 buffer owner 保活或 unsafe 约束。

### 13.4 Fixture 规则

- 模型必须小、离线、确定性，不能在测试运行时从网络下载。
- 优先使用项目自行生成且可重现的简单模型；记录生成方法。
- `tests/fixtures/README.md` 记录来源、许可证、SHA-256、输入 shape/dtype 和预期输出。
- 不提交真实业务模型、受限权重、cache blob 或硬件相关 compiled model。

### 13.5 Nimble 任务目标

最终 `.nimble` 至少提供稳定入口：

```text
nimble format
nimble formatCheck
nimble lint
nimble check
nimble test
nimble testAbi
nimble testIntegration
nimble examples
nimble docs
nimble releaseCheck
nimble releaseArchive
```

`releaseCheck` 校验版本、标签和产物命名；`releaseArchive` 只生成规范源码归档与 checksum，不执行 tag、push 或发布。若某任务需要 OpenVINO SDK/runtime，失败消息必须明确说明前置条件，不能悄悄 skip 后返回成功。

---

## 14. CI 设计

### 14.1 作业划分

- `static`：包元数据、`nimpretty` 零 diff、managed `--styleCheck:error`、raw `--styleCheck:usages`、pinned `clang-format`、空白/换行、导出和依赖边界检查。
- `unit`：Windows/Linux，最低与当前稳定 Nim，ORC/ARC 代表组合。
- `abi`：固定 OpenVINO 2026.4.0 headers/runtime 和 checksum，运行 C probe 与符号检查。
- `integration-cpu`：Release 模式完成真实 CPU 推理、profiling 和 import/export。
- `lifecycle`：压力测试与多内存管理器测试。
- `examples-package`：干净目录安装包并运行公开示例。
- `docs`：生成 API 文档，编译 README 示例，检查内部链接。
- `memory`：Linux 定时和 release 前运行 ASan/Valgrind。
- `release`：校验 tag/版本/日期/OpenVINO 版本，生成规范命名的可重复源码归档与 SHA-256；仅 tag 和明确发布流程触发，PR/fork 不能发布产物。

### 14.2 CI 约束

- Nim、OpenVINO 包、CI action 全部固定版本；禁止无约束 `latest`。
- 下载 OpenVINO 发布包时校验 checksum，并记录来源 URL。
- 测试不在线下载模型。
- Windows 显式配置 DLL 搜索路径；另设负测试验证缺 DLL 的诊断。
- warning 默认视为错误；必要豁免必须局部、解释原因并有 issue/风险记录。
- 失败时保留 runtime 版本、设备列表、ABI probe、测试日志；不得上传模型机密或环境 secrets。
- sanitizer suppression 逐项说明，禁止用全局忽略掩盖 binding 问题。
- GPU/NPU job 与通用 CI 分离，不因 hosted runner 无设备导致核心 CI 失败。
- 风格检查不得全局豁免 raw 绑定；只对必须忠实保留的 C 标识符采用独立、可审计的窄例外策略。
- CI 中 formatter 版本必须与本地开发文档一致；禁止未固定版本自动重写源码。
- 发布日期必须作为明确的发布元数据输入；禁止依赖 runner 时区或执行时刻自动推断文件名日期。
- 发布工作流必须先在不上传的模式生成并核验归档、顶层目录、SHA-256 和可重复性；上传步骤必须受明确发布授权和受保护环境约束。

---

## 15. 文档与示例

### 15.1 README 必须回答

- 这是什么，以及“社区维护、非官方”的声明。
- 支持的 Nim/OpenVINO/OS 组合。
- OpenVINO runtime 安装与动态库可见性。
- Nimble 安装和最小同步推理代码。
- 错误诊断入口。
- 生命周期和零拷贝的最短安全说明。
- 指向 API、ownership、compatibility、migration、troubleshooting 文档的链接。

### 15.2 API 文档

- 每个 managed 类型说明 native 所有权、`close()` 和线程约束。
- 每个 Tensor 数据入口说明 copy/borrow/unsafe 语义。
- 每个可能阻塞的 proc 明确标记。
- raw 文档说明它是 C ABI 层，不提供安全性保证。
- 不复制大段上游文档；链接到对应 OpenVINO 2026.4 官方资料并写 Nim 特有差异。

### 15.3 示例验收

| 示例 | 必须证明 |
|---|---|
| `list_devices.nim` | runtime 加载、版本查询、设备枚举 |
| `sync_infer.nim` | 真正设置输入、执行 infer、读取并验证/打印输出 |
| `tensor_basics.nim` | owned Tensor、shape、dtype、安全数据复制/访问 |
| `profiling.nim` | 通过 properties 开启 profiling，并复制读取结果 |

所有示例只 import 公共入口；不能使用 private handle，也不能依赖开发机绝对路径。

---

## 16. 开发阶段与验收门禁

### Phase 0：保护现状与冻结范围

**任务**

- 重新记录 branch、commit、remote、`git status` 和文件清单。
- 审计 secrets、生成物和大文件；确认现有文件可以进入基线。
- 创建 `docs/resonance-audit.md`，逐文件标记：保留概念、重写、迁出、删除。
- 记录本机 2026.4 headers/runtime 版本与官方来源。
- 确认 0.1.0 公共范围和非目标。
- 在得到执行任务对本地提交的授权后，建立现状基线 commit 和可恢复分支/tag。

**验收 Gate**

- 所有旧文件都有处理结论和许可证结论。
- 用户现有改动没有被覆盖。
- 可恢复的 Resonance 基线存在，或用户明确决定不用 Git 基线并记录风险。
- `docs/resonance-audit.md` 明确列出本节的三个已知 ABI 错误和 Windows-only 桥接。
- 未通过 Gate 前不得删除 `src/resonance` 或改名包入口。

**Gate 状态（2026-09-24）**

| Gate 条目 | 状态 | 证据 |
|---|---|---|
| 旧文件处理结论与许可证结论 | 通过 | `docs/resonance-audit.md` §3、§6 |
| 用户现有改动未被覆盖 | 通过 | 本阶段唯一写入为新增 `docs/resonance-audit.md` |
| 可恢复基线存在或已明确放弃 | **未通过** | 仓库零提交、无 remote；等待授权（A08） |
| 审计文档列出已知 ABI 错误与 Windows 桥接 | 通过 | `docs/resonance-audit.md` §7.1–§7.5，并已回写本文 §2.2、§2.5 |
| 未删除 `src/resonance`、未改名包入口 | 保持中 | 未执行任何删除或重命名 |

结论：Phase 0 仅剩基线授权一项未关闭。在该项关闭前，允许进行纯新增性质的 Phase 1 骨架工作，但不得执行任何删除、改名或覆盖既有文件的步骤。

### Phase 1：项目骨架、许可证与最小构建

**任务**

- 建立 `openvino.nimble`、`src/openvino.nim` 和分层目录；对外名称固定为 `openvino-nim`，Nimble/导入标识固定为 `openvino`。
- 添加 Apache-2.0 `LICENSE`、README、CHANGELOG、CONTRIBUTING、`.gitignore`。
- 添加 `STYLE_GUIDE.md`、`.editorconfig` 和基于 Google 风格的 `.clang-format`。
- 加入社区维护/非官方声明。
- 建立最小 CI 和 Nimble `check`/`test` 入口。
- 设置统一版本常量/元数据，避免多处手工漂移。

**验收 Gate**

- `nimble check` 通过。
- `import openvino` 在 Windows/Linux 都可编译，即使功能仍为空壳。
- 包归档不包含旧构建产物、runtime 二进制或开发路径。
- README、nimble 元数据和 CHANGELOG 的项目名、版本、许可证一致。
- README 明确说明 `openvino-nim`、`openvino`、`import openvino` 和 Release 归档名前缀分别用于什么场景。
- managed 示例代码通过 `nimpretty` 和 `--styleCheck:error`；C probe 通过 pinned Google-based `clang-format` 检查。
- raw C 名称例外已有独立检查策略，不存在仓库级 style/lint 关闭。

**Gate 状态（2026-09-24）**

验证环境：Windows x86_64、Nim 2.2.12、Nimble 随该 Nim 分发。按 §2.6，包级命令只能在排除了 `resonance.nimble` 的临时工作副本中执行；真实工作树未被改动。

| Gate 条目 | 状态 | 证据 |
|---|---|---|
| `nimble check` 通过 | 副本通过，工作树阻断 | 副本输出 `Success: The package "openvino" is valid.`；工作树因双 manifest 失败（§2.6） |
| `import openvino` 可编译 | Windows 通过，Linux 未验证 | `nim check --styleCheck:error --path:src src/openvino.nim` 零输出退出；Linux 仅有 CI 定义 |
| 包归档不含构建产物/runtime/开发路径 | **未通过** | 打包实测被 §2.6 阻断；`.gitignore` 已覆盖但未实测 |
| 项目名、版本、许可证三处一致 | 通过 | `nimble releaseCheck` 输出 `openvino-nim 0.1.0 against OpenVINO 2026.4.0`，并已反向测试 |
| README 说明四种名称的用途 | 通过 | `README.md` 的 "Four names, four purposes" 表 |
| managed 代码通过 `nimpretty` 与 `--styleCheck:error` | 通过 | `nimble formatCheck` 报 5 个文件零差异；`nimble lint` 逐文件 `nim check --styleCheck:error` 通过 |
| C probe 通过 pinned `clang-format` | 不适用 | 尚无手写 C 文件；`.clang-format` 已就位，检查随 Phase 2 的 probe 接入 |
| 不存在仓库级 style/lint 关闭 | 通过 | `styleChecks: off` 零出现，且 `nimble lint` 强制其目录 allowlist |

已完成 Checklist：B01–B07、B11、S01–S05、S08、S09、S11、S14、S16、S17。
部分完成：B08、B10、B12、S07、S10、S15。
阻断：B09 与 `nimble check`、打包实测，均由 §2.6 的双 manifest 冲突造成。

结论：Phase 1 的实现内容已完成并逐项验证，但 Gate 未通过。唯一根因是 §2.6：`resonance.nimble` 与 `openvino.nimble` 并存使 Nimble 拒绝包级操作，而移除旧 manifest 需要 §2.6 列出的两种授权之一。不得在授权到达前进入 Phase 2。

### Phase 2：Raw C ABI 基础

**任务**

- 固定 2026.4 header 来源/checksum。
- 实现 common/status/version/property/core/shape/tensor 的 raw 基础。
- 建立统一库名/覆盖机制。
- 建立 `docs/c-api-coverage.md`。
- 建立 C ABI probe、必需符号测试和 Core raw smoke。
- 移除新架构对 `perf_count_wrapper.c` 的依赖。

**验收 Gate**

- 所有 raw 声明都能定位到 2026.4 header。
- status/element type 的数值和 C enum 大小通过 probe。
- 关键 struct 的 size/offset 通过 probe。
- `ov_tensor_set_shape` by-value 签名通过真实回归测试。
- Windows/Linux 都能加载 2026.4 runtime、查询版本、创建并释放 Core。
- `_props` 必需符号解析成功；无 C++ 或 Resonance 依赖。

### Phase 3：错误与 handle 生命周期

**任务**

- 实现统一错误类型和状态检查。
- 实现统一 handle 状态、幂等 close 和析构兜底。
- 写 `docs/ownership.md` 与 handle ADR。
- 为 version、devices 等 native 容器实现复制后释放。
- 建立 close、别名、失败中途清理、use-after-close 测试。

**验收 Gate**

- 每个已用 native allocation 都有明确释放映射。
- double close 无害；所有 handle 在 close 后为统一状态。
- use-after-close 不进入 C 层。
- status 失败后立即复制原生错误详情。
- 析构不抛异常，异常中途已创建资源不泄漏。
- ORC 与 ARC 生命周期测试通过；refc 支持状态已明确记录。

### Phase 4：Model、Port、Tensor 与同步推理闭环

**任务**

- 实现 Core、Model、Port、CompiledModel、InferRequest、Tensor managed API。
- 实现 model metadata、properties、同步 infer、profiling、explicit import/export。
- 实现 owned/copy Tensor；决定并实现 external buffer 策略。
- 加入小型确定性 fixture 和完整 CPU 示例。
- 加入参数、overflow、dtype/capacity、负 index 测试。

**验收 Gate**

- Windows/Linux Debug 与 Release 都得到固定 CPU 推理输出。
- 顶层流程不要求用户接触 raw pointer。
- 设备、模型、属性、shape 和 index 错误都有上下文明确的异常。
- profiling 使用官方 property 与 `_props` API，不再存在 `nv_*`。
- import/export 是显式操作，不自动创建业务 cache。
- 1000 次创建/推理/释放压力测试无 double-free、invalid access 或包装层泄漏。

### Phase 5：跨平台、CI、文档和打包加固

**任务**

- 完成 Tier 1 CI 所有作业。
- 完成 README、ownership、compatibility、migration、troubleshooting 和 API 文档。
- 完成至少三个示例并纳入 CI。
- 测试 Windows 非 ASCII 路径、缺动态库诊断和干净目录安装。
- 运行 Linux 内存检查。
- 扫描 Resonance/Isvik 依赖和品牌残留。

**验收 Gate**

- Tier 1 阻断 CI 全绿。
- README 代码和所有示例从干净安装真实编译运行。
- 兼容矩阵只列实测组合。
- 文档无未解释的 Resonance/Isvik 残留。
- 包归档不包含 SDK、cache blob、临时目录、大模型或 secrets。
- 所有 warning、skip 和 suppression 都有解释；不存在静默跳过的必测项。
- `nimble formatCheck`、`nimble lint` 和 C/Markdown 风格作业全部通过，工作树零格式 diff。

### Phase 6：0.1.0 RC 与发布准备

**任务**

- 统一版本为 `0.1.0`，完成 CHANGELOG 和 release notes。
- 明确写入发布日期和固定 OpenVINO 三段版本，由发布脚本生成规范归档基名；不允许手工拼写长文件名。
- 在全新 Windows/Linux 环境验证固定 2026.4 runtime。
- 运行完整 release 矩阵与内存检查。
- 建立 `v0.1.0-rc.1` 候选；RC 后只接受阻断性修复。
- 生成 `.zip`、`.tar.gz` 与各自 `.sha256`，复核包内容、顶层目录、许可证、fixture 来源和文档链接。
- 在相同 commit 和发布元数据下重复打包并比较 checksum，确认发布归档可重复。

**验收 Gate**

- 所有阶段 Gate 都有测试日志、CI 链接或可审计产物。
- 全新环境可安装、加载 runtime 并完成 CPU 推理。
- 无未解释失败、warning、skip、sanitizer suppression 或待定高风险项。
- `0.1.0`、`2026-9-24`、OpenVINO `2026.4.0` 这一发布组合的归档基名精确为 `openvino-nim-0-1-0-2026-9-24-ov2026-4-0`；若发布日期或已验证的 OpenVINO patch 改变，必须按同一模板重新生成而非继续复用旧名。
- Git tag、Release 标题、归档文件名、归档顶层目录和 checksum 文件全部通过自动一致性检查。
- 正式 tag、push、创建 release 或发布 Nimble 包前，必须取得用户明确授权。

---

## 17. AI 开发代理工作规则

交给任何 AI 编程助手执行时，以下规则均具有约束力，不依赖具体模型、编辑器、IDE 或代理框架：

1. 每次开始前读取仓库内适用于当前目录的开发说明文件（如 `AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING.md` 或同类文件），检查分支、`git status`、未跟踪文件和当前 diff。
2. 用户已有改动一律视为不可覆盖；禁止 `git reset --hard`、无授权 checkout 恢复、历史改写或无关批量格式化。
3. 一次只推进一个 Phase；当前 Gate 未通过，不得把下一阶段标记完成。
4. 不得猜测 C 签名、ABI、所有权或线程语义；必须核对固定的 2026.4 header/官方文档。无法确认时记录阻断，而不是凭经验实现。
5. 不得为了通过测试忽略状态码、泄漏资源、扩大 unsafe 范围、关闭整个 warning 类别或把必测项改成 silent skip。
6. 所有 public API 变化必须同时更新测试、文档、coverage 和 CHANGELOG。
7. generated raw binding 只能经规定生成流程更新；修改生成器时同一提交包含生成结果。
8. 不引入新 runtime 依赖、OpenVINO 二进制、大模型或联网测试，除非计划明确批准。
9. 不把 Resonance/Isvik 逻辑“顺手”移入通用包；范围外问题只记录。
10. 每完成一个 Phase，报告：修改文件、设计决定、执行命令、测试结果、未解决风险和下一 Gate。
11. SDK/runtime 缺失时可以完成不依赖它的工作，但不得伪造 ABI、集成或平台测试通过。
12. Checklist 只有在有测试日志、CI 结果或可审计文件时才能勾选。
13. 批量删除、创建/修改远端、push、force push、tag、PR、release 和发布包均不得从本文自动推导授权；按用户当前指令执行。
14. 每个提交前复核 diff，确保没有绝对开发路径、runtime 二进制、模型机密、cache、临时文件或 credentials。
15. 发现本文的技术假设与 2026.4 实际 header/runtime 不符时，先记录证据和 ADR，再更新计划；不能悄悄偏离。
16. 所有新代码遵循 `STYLE_GUIDE.md`；提交前运行 formatter 和 style/lint 检查，不得以“功能可用”为理由留下风格债务。
17. 不对 generated/raw 文件做会改变 C 标识符或 ABI 的美化；风格与 ABI 冲突时保留 ABI，并记录最小例外。

### 17.1 每阶段报告模板

```text
Phase:
完成项:
修改文件:
关键设计决定:
执行的验证:
通过/失败结果:
尚未解决的风险:
当前 Gate 是否通过:
建议下一步:
```

---

## 18. 分支与提交策略

### 18.1 初次迁移

当前仓库没有提交，因此先保护现状，再进行重构：

```text
main                              # 可恢复的 Resonance 基线/随后保持可构建
└─ refactor/openvino-nim-0.1      # 首次整体迁移分支
```

建议基线名称：

```text
archive/resonance-before-openvino-nim
```

是否创建本地 commit/tag 取决于项目所有者对执行任务的授权。由于现有文件全是未跟踪文件，AI 开发代理在审计来源和 secrets 前不得直接把全部内容提交。

### 18.2 提交规则

- 每个提交原子化、可解释，并尽量对应一个 Phase 子目标。
- 纯格式化与语义修改分开。
- 生成器与生成结果放在同一提交。
- 公共 API 改动同一提交更新测试/文档/CHANGELOG。
- 合入 `main` 前必须满足当前 Phase Gate；`main` 保持可构建。
- 提交说明至少回答 What、Why、Test、Risk；“修复问题”之类无上下文描述不合格。
- 优先小而完整的变更；接近 1000 行的手写语义 diff 原则上拆分。生成文件单独统计，不用生成量掩盖手写复杂度。
- 合并前至少进行一次独立 diff review；单人维护时也要分开执行实现与复核，并记录 checklist 结果。
- Review 顺序固定为：范围/分层、ABI/所有权、API/命名、测试、跨平台/文档、format/lint。
- generated diff 通过输入版本、生成器变更、coverage diff 和 ABI probe 评审，不能只凭肉眼浏览海量输出。
- 初版后使用短分支：`feat/...`、`fix/...`、`docs/...`、`test/...`、`chore/...`。
- 禁止 force push `main`；禁止为“整理历史”丢失基线。

建议 Conventional Commit 示例：

```text
chore: establish OpenVINO Nim package skeleton
feat(raw): bind OpenVINO 2026.4 core and property APIs
test(raw): add OpenVINO 2026.4 ABI probe
feat(runtime): add managed core and model handles
feat(runtime): add tensor and synchronous inference
test: add CPU inference and lifecycle coverage
docs: prepare OpenVINO Nim API 0.1.0 release
```

### 18.3 发布分支/标签

- RC：`v0.1.0-rc.1`。
- 正式：`v0.1.0`。
- 正式 Release 标题：`openvino-nim 0.1.0 — 2026-9-24 — OpenVINO 2026.4.0`；日期随实际发布日更新。
- 正式资产基名：`openvino-nim-0-1-0-2026-9-24-ov2026-4-0`；长资产名不能代替 SemVer tag。
- tag 必须指向通过完整 release Gate 的 commit。
- tag、push、GitHub/GitLab release、Nimble 发布都需要用户单独明确授权。

---

## 19. 风险清单

| 风险 | 严重度 | 触发信号 | 缓解与阻断点 |
|---|---|---|---|
| C ABI 声明错误 | 高 | 随机崩溃、参数错位、仅某编译器失败 | 固定 header、C probe、by-value 回归、Windows/Linux raw smoke；Phase 2 阻断 |
| element/status 枚举漂移 | 高 | Tensor dtype 错误、异常名称错误 | **Phase 0 已确认实际发生**：旧绑定 `U8` 偏移 3、`-10` 命名错误。不复制旧枚举；全值 probe；coverage 表 |
| header/runtime 不匹配 | 高 | 缺 `_props` 符号、版本描述异常 | 固定来源/checksum、版本/符号诊断、发布环境复测 |
| variadic ABI 跨编译器问题 | 高 | Windows MinGW/MSVC 调用崩溃 | managed 层只用 2026.4 非 variadic properties API |
| double-free/use-after-free | 高 | close 顺序相关崩溃、压力测试不稳定 | 私有 handle、统一 owner、幂等 close、别名/ARC/ORC 测试 |
| 外部 Tensor buffer 提前释放 | 高 | GC 后随机输出或崩溃 | 默认 copy/owned；安全路径持有 owner；否则显式 unsafe |
| Tensor shape/容量溢出 | 高 | 小输入通过、大 shape 越界 | 负维度和 checked multiply；dtype/byte capacity 验证 |
| 原生错误被后续调用覆盖 | 中 | 错误文本为空或对应错误不一致 | status 失败后立即复制 last error |
| DLL/SO 搜索路径漂移 | 高 | 开发机成功、干净环境失败 | 集中加载逻辑、库名覆盖、干净安装与缺库负测试 |
| Windows Unicode 路径 | 中 | 中文路径模型无法读取 | 官方 Unicode API/实测方案，非 ASCII CI 测试 |
| Resonance/Isvik 逻辑渗入 | 中 | Core 出现 cache 命名、默认设备或业务日志 | 边界清单、依赖扫描、品牌 grep、Phase 5 Gate |
| 首版 API 膨胀 | 中 | 大量无测试 helper、发布延期 | 冻结 MVP；额外能力进入 experimental/后续版本 |
| callback 与 Nim GC/线程冲突 | 高 | 异步随机崩溃、异常跨 C | 0.1.0 不提供 callback managed API；未来单独 ADR/测试 |
| GPU/NPU runner 不稳定 | 中 | hosted runner 无设备/驱动 | CPU 为发布基线，硬件 job 完全分离 |
| Fixture 许可证不清 | 中 | 无法公开分发包 | 自生成或宽松许可；记录来源、方法和 checksum |
| 官方品牌误导 | 中 | 用户误认为 Intel 官方 binding | README、包描述和 release notes 明确社区/非官方 |
| 对外名与 Nimble 标识混淆 | 中 | 创建 `openvino-nim.nimble`、`nimble check` 失败或安装/导入说明互相矛盾 | 对外始终称 `openvino-nim`；Nimble 清单/标识/根模块统一为 `openvino`；CI 检查映射 |
| Nimble 名称被占用 | 中 | 提交官方包索引时 `openvino` 已指向其他项目 | Phase 1 和正式发布前各查询一次官方包索引；冲突时先由项目所有者决定新合法标识，不静默改名 |
| Release 名称元数据漂移 | 中 | tag、标题、归档名或顶层目录版本不一致 | 从受控元数据生成名称并做一致性测试；禁止手工复制长名称 |
| 发布日期受 runner 时区影响 | 低/中 | 同一发布在不同作业生成不同日期文件名 | 日期作为明确输入；采用项目约定 `YYYY-M-D`，不读取 runner 本地日期 |
| 归档不可重复 | 中 | 相同 commit 重打包 checksum 不同 | 固定排序、权限、时间戳和工具版本；发布前双构建比对 |
| Nim 版本/内存管理器差异 | 中 | ORC 通过而 ARC/refc 失败 | 固定最低/当前版本矩阵，handle ADR，生命周期测试 |
| Google C++ 命名机械套用到 Nim | 中 | managed API 出现非惯用命名、styleCheck 大量豁免 | 采用本节 Nim 适配优先级；raw C 名称单独处理 |
| Formatter/版本漂移 | 中 | 本地与 CI 反复产生格式 diff | 固定 Nim/nimpretty/clang-format 版本，CI 验证零 diff |
| 为 raw 符号全局关闭风格检查 | 中 | managed 层风格错误不再被发现 | managed/raw 分开检查，只允许最小局部例外 |
| 安全复制带来性能成本 | 低/中 | 大 Tensor benchmark 下降 | 默认安全，显式零拷贝；有 benchmark 后再优化 |
| CI 供应链漂移 | 中 | action/latest 或下载包突然变化 | 固定 action/工具/SDK 版本与 checksum |
| 旧用户迁移破坏 | 中 | Resonance import/name 失效 | 保留基线、提供迁移映射；compat adapter 放下游 |

高风险项未关闭时不得发布 RC。

---

## 20. 可执行 TODO / Checklist

> 勾选规则：必须有 commit、文件、命令输出或 CI 链接作为证据。不要预先勾选。

### A. 保护与审计

- [x] A01 记录当前 branch、commit、remote 和完整 `git status`。证据：`docs/resonance-audit.md` §1；分支 `main`、零提交、无 remote、5 项未跟踪。
- [x] A02 检查未跟踪文件中是否有 secrets、生成物、runtime 二进制或模型机密。证据：`docs/resonance-audit.md` §2；14 个文件全为手写源码/文档，凭据扫描唯一命中为 `toolSearch.minTokens` 配置项。
- [x] A03 建立 `docs/resonance-audit.md`，逐文件分类为保留概念、重写、迁出或删除。证据：该文件 §6 逐文件表 + §6.1 迁出职责清单。
- [x] A04 记录旧源码作者/来源和许可证；无法确认的部分列为重写。证据：`docs/resonance-audit.md` §3；`c_api.nim` 与 `perf_count_wrapper.c` 因无法追溯上游依据，一律列为重写。
- [ ] A05 固定 OpenVINO 2026.4.0 header/runtime 来源、版本、tag/commit 和 checksum。**部分完成**：本机 18 个 C header 的 SHA-256、安装布局与 tag/commit 已记录在 `docs/resonance-audit.md` §4；官方发布物下载 URL 与其归档 checksum 留待 Phase 2 在 `docs/c-api-coverage.md` 固定并与本机值交叉核对后才可勾选。
- [x] A06 确认 Tier 1 为 Windows x64/Linux x64、CPU 为发布基线。证据：`docs/resonance-audit.md` §5，本次确认不变。
- [x] A07 确认最低 Nim 候选和需要实测的 ORC/ARC/refc 范围。证据：`docs/resonance-audit.md` §5；最低候选 2.0.0，本机 2.2.12，ORC/ARC 阻断、refc 仅记录结论。
- [ ] A08 经授权后建立可恢复的 Resonance 基线 commit/branch/tag。**阻断中**：仓库零提交，需项目所有者按 §17 规则 13 明确授权，或明确决定放弃 Git 基线并记录风险。
- [ ] A09 确认所有 Phase 0 Gate 后再开始重命名或删除。取决于 A05、A08。

### B. 包与法律文件

- [x] B01 创建 `openvino.nimble`，设置 Nimble 标识 `openvino`、版本 `0.1.0`、Apache-2.0 和最低 Nim 版本；对外包名固定为 `openvino-nim`。证据：`nimble check` 输出 `The package "openvino" is valid.`（见 §16 Phase 1 Gate 状态的验证说明）。
- [x] B02 添加完整 Apache-2.0 `LICENSE`。证据：`LICENSE`，正文取自 `https://www.apache.org/licenses/LICENSE-2.0.txt`，未做任何改写。
- [x] B03 添加 README、CHANGELOG、CONTRIBUTING 和 `.gitignore`。证据：四个文件均已创建。
- [x] B04 README/包描述加入社区维护、非官方声明。证据：`README.md` 首屏加粗声明 + `openvino.nimble` 的 `description` 字段均含 "Not an official Intel or OpenVINO project"。
- [x] B05 建立 `src/openvino.nim`，默认仅导出 managed API。证据：该文件仅 `import openvino/version` 并 `export version`；`nimble lint` 含拒绝 re-export raw 层的检查。
- [x] B06 建立 raw、managed、private 分层目录。证据：`src/openvino/`（managed）、`src/openvino/raw/`、`src/openvino/private/`，后两者以带说明的 `.gitkeep` 占位。
- [x] B07 建立单一版本事实来源或自动一致性检查。证据：`src/openvino/version.nim` 为唯一来源，`openvino.nimble` 用 `staticRead` 派生 `version`；`nimble releaseCheck` 通过，并已用反向测试验证：把 `PackageVersion` 改为 `0.2.0` 后该任务以 exit 1 报出 CHANGELOG/README 不一致。
- [ ] B08 在 Windows/Linux 验证最小 `import openvino` 编译。**部分完成**：Windows x86_64 + Nim 2.2.12 实测 `nim check --styleCheck:error` 通过、8 个单元测试全过。Linux 侧仅由 `.github/workflows/ci.yml` 的 `unit` 作业定义，尚无 CI 运行记录，因此不勾选。
- [ ] B09 验证 Nimble 包归档不含本机路径、SDK/runtime 或临时文件。**阻断中**：工作树同时存在 `resonance.nimble` 与 `openvino.nimble`，Nimble 拒绝任何包级操作（见 §2.6）。`.gitignore` 已覆盖构建产物、runtime 库、blob 与模型权重，但打包实测需先解除双 manifest 冲突。
- [ ] B10 为翻译/生成自上游 C headers 的声明记录 SPDX、tag/commit 和来源，并复核是否需要 NOTICE/归属说明。**部分完成**：全部手写源文件已带 `SPDX-License-Identifier: Apache-2.0`；上游 tag/commit 已记录为 `version.nim` 的 `TargetOpenVinoTag`/`TargetOpenVinoCommit`。真正翻译自 header 的声明尚不存在（Phase 2），NOTICE 结论随 raw 层一并给出。
- [x] B11 README 解释对外名 `openvino-nim`、Nimble 标识 `openvino`、清单 `openvino.nimble` 和导入入口 `import openvino` 的区别。证据：`README.md` 的 "Four names, four purposes" 表，四项逐条给出用途与原因。
- [ ] B12 查询官方 Nimble 包索引，确认 `openvino` 在采用时未被其他项目占用；发布前再次查询并保留证据。**首次查询已完成**：2026-09-24 拉取 `nim-lang/packages` 的 `packages.json`，共 2945 个包，`name` 精确等于 `openvino` 的记录数为 0，且不存在任何包含 `openvino` 或 `vino` 的近似名。发布前的第二次查询尚未进行，故不勾选。

### S. Google 风格与可维护性

- [x] S01 创建 `STYLE_GUIDE.md`，写明 Google 原则、Nim 适配和规则优先级。证据：该文件的 "Rule precedence" 一节给出 ABI > Nim 惯例 > Google 可维护性 > 个人偏好的四级优先级，并把上游拼写（`UNKNOW_EXCEPTION`、`F8E5M3`）单列为 ABI 例外。
- [x] S02 添加 `.editorconfig`：UTF-8、LF、final newline、trim trailing whitespace、2-space indentation。证据：`.editorconfig`，并对 `LICENSE` 单独豁免重排以保持逐字不变。
- [x] S03 添加 pinned `.clang-format`，基于 Google style，80 列、2 空格。证据：`.clang-format` 使用 `BasedOnStyle: Google`、`IndentWidth: 2`、`ColumnLimit: 80`，并关闭 `SortIncludes` 以保护本文要求的 include 分组顺序。
- [x] S04 固定 `nimpretty`/Nim 版本并定义可重复的格式检查入口。证据：`STYLE_GUIDE.md` 的 Pinned tools 表；`nimble format` / `nimble formatCheck` 统一使用 `nimpretty --indent:2 --maxLineLen:80`。
- [x] S05 managed 源码、示例和测试通过 `nim check --styleCheck:error`。证据：`nimble lint` 对 5 个 Nim 文件逐个执行该命令并通过（`src/openvino.nim`、`src/openvino/version.nim`、`tests/unit/tmetadata_consistency.nim`、`tools/mdcheck.nim` 及其余）。Resonance 原型文件按 §2.6 显式排除，`lint` 每次运行都逐个列出被排除项，不静默跳过。
- [ ] S06 raw 层保留精确 C 名称，并通过独立 `--styleCheck:usages`、编译和 ABI 检查。**未开始**：raw 层由 Phase 2 落地。`nimble lint` 已预留 `src/openvino/raw` 前缀的排除逻辑与 `styleChecks: off` allowlist。
- [ ] S07 CI 验证 formatter 执行后工作树零 diff。**部分完成**：`nimble formatCheck` 实测通过，且实现方式不依赖 Git —— 它把 `nimpretty` 输出写到临时文件后逐字节比对，因此在当前无提交的仓库中同样有效。CI 的 `static` 作业已调用该任务，但尚无 CI 运行记录。
- [x] S08 CI 拒绝 Tab、行尾空格、缺 final newline 和未解释 lint suppression。证据：`nimble lint` 对每个手写文件检查 Tab、CR、行尾空白与末尾换行，并强制 `styleChecks: off` 的目录 allowlist；实测通过，且该 allowlist 检查在开发中确实触发过一次误报（manifest 自身存放该字符串），已按最小范围修正。
- [x] S09 Import 按 std/第三方/本地分组并在组内排序。证据：当前含 import 的三个文件（`src/openvino.nim`、`tests/unit/tmetadata_consistency.nim`、`tools/mdcheck.nim`）均符合，`std/[...]` 形式用于多标准库模块。
- [ ] S10 public API 文档包含所有权、复制、阻塞、异常和线程契约。**部分完成**：现有公共符号（`version.nim` 的 8 个常量、入口模块）均有 `##` 文档并说明不负责什么；所有权/阻塞/线程契约随 Phase 3、4 的实际 handle 与 Tensor API 落地。
- [x] S11 超过约 40 逻辑行的函数已拆分或有评审记录；复杂参数改用 options object。证据：当前最长函数为 `tools/mdcheck.nim` 的 `checkMarkdown`，已把整文件形状检查拆到 `checkFileShape`；无函数超过阈值，无超过 4 参数的接口。
- [ ] S12 unsafe/cast/borrowed pointer 仅存在于最小作用域并有不变量说明。**未开始**：当前新代码不含 `cast`、`unsafeAddr` 或裸指针。规则已写入 `STYLE_GUIDE.md`，随 raw 层生效。
- [ ] S13 generated binding 重复生成零 diff，且没有手工修改生成结果。**未开始**：尚无生成代码。`tools/README.md` 已写明生成器若被采用需附带固定输入版本与"禁止手改"说明。
- [x] S14 Markdown 使用单一 H1、ATX 标题、有语言标签的 fenced code block 和可描述链接。证据：`tools/mdcheck.nim` 对 7 个 Markdown 文件（含本文）全部通过；反向测试构造了 2 个 H1 + 无语言标签 + 未闭合 fence 的文件，工具逐条报出三个问题并使 `nimble lint` 以 exit 1 失败。
- [ ] S15 `nimble format`、`nimble formatCheck`、`nimble lint` 在本地与 CI 行为一致。**部分完成**：三者在本机（Windows、Nim 2.2.12）通过，但按 §2.6 只能在排除 `resonance.nimble` 的临时副本中运行；真实工作树与 CI 的一致性验证需先解除双 manifest 冲突。
- [x] S16 `styleChecks: off` 仅出现在批准的 raw 声明区间，并通过 allowlist 检查。证据：`nimble lint` 实现该 allowlist，当前代码中该 pragma 零出现；`STYLE_GUIDE.md` 与 `CONTRIBUTING.md` 均写明仅 `src/openvino/raw` 允许且必须立即 `{.pop.}`。
- [x] S17 测试/辅助文件遵循 `t...`/`m...` 命名，测试名描述可观察行为。证据：`tests/unit/tmetadata_consistency.nim`；8 个测试名均为可观察行为陈述，例如 "minimum Nim version is not newer than the compiling Nim"。

### C. Raw binding 与 ABI

- [ ] C01 建立 `docs/c-api-coverage.md` 并列出 0.1.0 所需 headers/symbols。
- [ ] C02 绑定 status，并修正 `NOT_ALLOCATED` 与 `-14..-17`。
- [ ] C03 绑定完整所需 element type，包含 2026.4 的 U2/U3/U6/低精度/string 值。
- [ ] C04 验证 raw C enum 表示大小为 C ABI 所需大小。
- [ ] C05 绑定 `ov_get_error_info`、`ov_get_last_err_msg`、`ov_free`。
- [ ] C06 绑定 version/Core/devices 与对应 free 函数。
- [ ] C07 绑定 `ov_property_t`、官方 property key 和非 variadic properties API。
- [ ] C08 绑定 shape/Tensor，并正确声明 by-value `ov_tensor_set_shape`。
- [ ] C09 绑定 node/port/Model 所需 API。
- [ ] C10 绑定 CompiledModel/import/export 所需 API。
- [ ] C11 绑定 InferRequest/sync infer/profiling 所需 API。
- [ ] C12 集中实现 Windows/Linux 动态库名和编译期覆盖。
- [ ] C13 动态库缺失/符号缺失时给出可操作诊断。
- [ ] C14 创建 C ABI probe，覆盖 size/align/offset/enum/constants。
- [ ] C15 创建必需符号解析测试。
- [ ] C16 创建 raw 版本查询和 Core 创建/释放 smoke test。
- [ ] C17 创建 `ov_tensor_set_shape` by-value 回归测试。
- [ ] C18 Windows/Linux 2026.4.0 ABI 与 raw smoke 全部通过。
- [ ] C19 新架构完全不依赖 `perf_count_wrapper.c` 或 `nv_*`。

### D. Managed 错误与生命周期

- [ ] D01 实现 `OpenVinoError`，含 operation/status/status info/native detail/context。
- [ ] D02 实现 library/version 专用错误或同等可区分诊断。
- [ ] D03 实现唯一的 managed status 检查入口。
- [ ] D04 证明 status 失败后在下一次 C 调用前复制 last error。
- [ ] D05 建立 handle ADR，选择全库统一的所有权表示。
- [ ] D06 所有 native handle 字段改为私有。
- [ ] D07 所有 owner 提供幂等 `close()` 和非抛异常析构兜底。
- [ ] D08 所有 public 方法在进入 C 层前检查 closed state。
- [ ] D09 实现输出指针零初始化与失败中途清理。
- [ ] D10 实现原生字符串/数组复制后释放。
- [ ] D11 创建并维护 `docs/ownership.md`。
- [ ] D12 double close、别名 close、use-after-close 测试通过。
- [ ] D13 异常中途清理和析构不抛测试通过。
- [ ] D14 ORC/ARC 生命周期测试通过；refc 状态有明确结论。

### E. Managed 功能

- [ ] E01 实现 runtime 版本查询和 2026.4 支持诊断。
- [ ] E02 实现 `Core` 和 available devices。
- [ ] E03 实现 `Model` 读取和输入/输出 metadata。
- [ ] E04 实现 owned `Port`/const port 释放语义。
- [ ] E05 实现 properties 构造、set/get 和 compile properties。
- [ ] E06 实现 `CompiledModel`、explicit import/export。
- [ ] E07 实现 OpenVINO-owned Tensor。
- [ ] E08 实现从 Nim 数据安全复制创建 Tensor。
- [ ] E09 决定并实现外部 buffer：强 owner 或显式 unsafe；禁止模糊入口。
- [ ] E10 实现 dtype、shape、元素数、byte size 和 checked overflow。
- [ ] E11 实现安全数据复制与有约束的数据 view。
- [ ] E12 实现 `InferRequest`、set input、get output 和同步 `infer`。
- [ ] E13 实现 profiling property 与 profiling 结果复制。
- [ ] E14 所有 index 转 `csize_t` 前验证非负/范围。
- [ ] E15 Windows 非 ASCII 模型路径方案实现并测试。
- [ ] E16 顶层同步流程不暴露 raw pointer。
- [ ] E17 `compileOrImportModel`、默认 cache/device/fallback 不进入稳定 API。

### F. 测试与 fixture

- [ ] F01 选择或可重现生成小型确定性模型 fixture。
- [ ] F02 记录 fixture 来源、许可证、生成方法和 SHA-256。
- [ ] F03 单元测试覆盖状态、错误、properties、shape 和 overflow。
- [ ] F04 ABI 测试覆盖全部 0.1.0 关键类型、常量和符号。
- [ ] F05 Windows/Linux 完整 CPU 推理得到固定输出。
- [ ] F06 Debug/Release 均运行核心集成测试。
- [ ] F07 失败路径覆盖无效模型、device、property、shape、dtype、index。
- [ ] F08 import/export 集成测试通过，测试自行管理临时文件。
- [ ] F09 profiling on/off 行为测试通过。
- [ ] F10 外部 buffer owner/unsafe 生命周期测试通过。
- [ ] F11 1000 次生命周期压力测试通过。
- [ ] F12 Linux 内存/非法访问检查通过。
- [ ] F13 干净临时目录 Nimble 安装/打包测试通过。
- [ ] F14 README 最小代码真实编译运行。
- [ ] F15 所有示例只使用公共 managed API。

### G. CI、文档与示例

- [ ] G01 添加 Windows x64 与 Linux x64 阻断 CI。
- [ ] G02 固定 Nim、OpenVINO、CI actions 和下载 checksum。
- [ ] G03 完成 static、unit、abi、integration-cpu 作业。
- [ ] G04 完成 lifecycle、examples-package、docs 作业。
- [ ] G05 完成定时/release 内存检查作业。
- [ ] G06 CI 失败产物包含 ABI/runtime/设备诊断且不泄露 secrets。
- [ ] G07 完成 `list_devices.nim`。
- [ ] G08 完成真正端到端的 `sync_infer.nim`。
- [ ] G09 完成 `tensor_basics.nim`。
- [ ] G10 完成 `profiling.nim` 或明确移到后续版本。
- [ ] G11 完成 architecture、ownership、compatibility 文档。
- [ ] G12 完成 Resonance migration 和 troubleshooting 文档。
- [ ] G13 生成 API 文档并检查内部链接。
- [ ] G14 检查 `src/openvino` 不 import Resonance/Isvik。
- [ ] G15 检查公共符号/错误/用户文档无业务品牌残留。
- [ ] G16 确认 macOS/GPU/NPU 只按实测状态声明。
- [ ] G17 发布 CI 从版本、明确发布日期和 OpenVINO 固定版本生成归档名，不读取 runner 本地日期。
- [ ] G18 发布 CI 校验 tag、Release 标题、归档名、归档顶层目录和 checksum 一致。
- [ ] G19 发布 CI 支持只生成不上传的 dry run；PR/fork 无上传权限。

### H. RC 与发布

- [ ] H01 所有 Phase Gate 都有可复核证据。
- [ ] H02 兼容矩阵只列真实测试组合。
- [ ] H03 所有版本号统一为 `0.1.0`。
- [ ] H04 CHANGELOG 和 release notes 完成。
- [ ] H05 包内容复核无 SDK、cache、临时文件、大模型、绝对路径或 secrets。
- [ ] H06 无未解释 warning、skip、suppression 或高风险项。
- [ ] H07 全新 Windows/Linux 环境完成安装、runtime 加载和 CPU 推理。
- [ ] H08 经授权创建并验证 `v0.1.0-rc.1`。
- [ ] H09 RC 后只接受阻断性修复并重跑 release Gate。
- [ ] H10 经用户明确授权后再创建正式 tag、push、release 或发布包。
- [ ] H11 对 `0.1.0`、`2026-9-24`、OpenVINO `2026.4.0` 生成精确基名 `openvino-nim-0-1-0-2026-9-24-ov2026-4-0`；元数据变化时按模板重算。
- [ ] H12 生成同基名的 `.zip`、`.tar.gz`、`.zip.sha256` 和 `.tar.gz.sha256`。
- [ ] H13 两种归档都只有一个与基名相同的顶层目录，且不包含 OpenVINO runtime/SDK。
- [ ] H14 在相同 commit 和发布元数据下重复生成归档，逐项 checksum 一致。
- [ ] H15 确认托管平台自动生成的源码包不被误写为规范命名资产；规范资产由受控发布流程上传。

---

## 21. 最终发布验收摘要

发布负责人必须能对下列问题全部回答“是”：

- raw ABI 是否由 2026.4 header 和 C probe 共同证明，而不是只靠编译成功？
- 是否完全移除了 Windows variadic 桥接作为核心依赖？
- 是否修复了 enum 错位和 `ov_tensor_set_shape` 签名？
- 每个 native allocation 是否有唯一 owner、对应 free 和失败清理测试？
- 外部 Tensor 内存是否不会在调用者不知情时悬垂？
- Windows/Linux 是否都真实完成 CPU 推理？
- 默认入口是否只暴露 managed API？
- 是否没有隐式 cache、默认设备、fallback 或 Isvik/Resonance 业务策略？
- 文档中的兼容性是否全部有 CI/发布验证证据？
- managed/Nim、raw/C 和 Markdown 是否分别通过规定的 Google-style/Nim-style 自动检查，且 formatter 零 diff？
- raw C 标识符的风格例外是否局部、可审计，未关闭 managed 层检查？
- 包是否可在干净环境安装，且不携带 OpenVINO runtime 或受限模型？
- 对外名称是否始终为 `openvino-nim`，同时 `openvino.nimble`、Nimble 标识和 `import openvino` 是否保持一致？
- Git tag、Release 标题、规范归档名、归档顶层目录和 SHA-256 是否由同一组版本元数据生成并完全一致？
- `0.1.0` 在 `2026-9-24` 面向 OpenVINO `2026.4.0` 时，规范归档基名是否精确为 `openvino-nim-0-1-0-2026-9-24-ov2026-4-0`？
- 相同 commit 和发布元数据能否生成 checksum 相同的 `.zip` 与 `.tar.gz`？
- 发布动作是否获得了用户明确授权？

任何一项为“否”，都不能发布 `0.1.0`。

---

## 22. 官方基线资料

### 22.1 OpenVINO 与许可证

以下资料均应固定到 2026.4 基线；生成/审计 raw binding 时不得以 `master` 或滚动 latest 页面代替 tag：

- [OpenVINO 2026.4.0 Release（tag `2026.4.0`，commit `99c8149`）](https://github.com/openvinotoolkit/openvino/releases/tag/2026.4.0)
- [2026.4.0 C API 总入口 `openvino/c/openvino.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/openvino.h)
- [2026.4.0 `ov_common.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_common.h)
- [2026.4.0 `ov_property.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_property.h)
- [2026.4.0 `ov_core.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_core.h)
- [2026.4.0 `ov_tensor.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_tensor.h)
- [2026.4.0 `ov_infer_request.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_infer_request.h)
- [OpenVINO 2026 C API Reference](https://docs.openvino.ai/2026/api/c_cpp_api/group__ov__c__api.html)
- [OpenVINO 2026 System Requirements](https://docs.openvino.ai/2026/about-openvino/release-notes-openvino/system-requirements.html)
- [OpenVINO Release Policy](https://docs.openvino.ai/2026/about-openvino/release-notes-openvino/release-policy.html)
- [OpenVINO 2026.4.0 Apache-2.0 LICENSE](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/LICENSE)

`docs/c-api-coverage.md` 必须记录实际采用的精确 URL、tag/commit 和下载物/header 集合 checksum。对动态字符串所有权、callback 捕获或其他仅从实现可确认的行为，应同时链接 `2026.4.0` tag 下的对应 C binding 源码，不能只引用未固定版本的在线说明。

### 22.2 代码与文档风格

- [Google Style Guides 总览](https://google.github.io/styleguide/)
- [Google C++ Style Guide](https://google.github.io/styleguide/cppguide)
- [Google Markdown Style Guide](https://google.github.io/styleguide/docguide/style.html)
- [Google Documentation Best Practices](https://google.github.io/styleguide/docguide/best_practices.html)
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html)
- [Google Engineering Practices: What to Look for in a Code Review](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
- [Nim Standard Library Style Guide（NEP 1）](https://nim-lang.org/docs/nep1.html)
- [Nim Compiler `--styleCheck` 文档](https://nim-lang.org/docs/nimc.html)
- [Nim 官方工具与 `nimpretty`](https://nim-lang.org/docs/tools.html)
- [LLVM ClangFormat](https://clang.llvm.org/docs/ClangFormat.html)

`STYLE_GUIDE.md` 应固定本项目采用的具体规则，不把外部滚动更新页面直接当作未经评审即可改变 CI 的配置。升级 formatter 或规则时，单独提交配置变更与机械格式化，禁止和功能修改混在一起。

### 22.3 Nimble 包结构与发布命名

- [Nimble User Guide：推荐的包、清单与 `src` 模块结构](https://nim-lang.github.io/nimble/create-packages.html#project-structure)
- [Nimble `packageparser.nim`：包名只允许字母、数字、下划线，并要求清单文件名与包名匹配](https://github.com/nim-lang/nimble/blob/master/src/nimblepkg/packageparser.nim)
- [Nimble User Guide：Git tag 用于解析可安装版本](https://nim-lang.github.io/nimble/create-packages.html#dependencies)
- [Nimble 官方包索引](https://github.com/nim-lang/packages/blob/master/packages.json)
- [GitHub Releases：Release 与自动源码归档](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- [GitHub REST API：上传自定义 Release assets](https://docs.github.com/en/rest/releases/assets)

上述约束解释了为什么项目对外使用 `openvino-nim`，而 Nimble 清单、包标识和导入根模块使用 `openvino`。正式发布前必须再次核对当时的 Nimble/Nim 规则和官方包索引；若发生名称冲突，必须形成明确决策并同步修改安装文档、CI 和兼容说明。
