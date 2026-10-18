# OpenVINO Nim API 0.2.0 开发任务：异步推理、动态 Shape 与预处理 API

> 本文档是 `D:\nim\openvino-nim` 在 `0.1.1` 发布之后的下一阶段开发基线，覆盖
> `docs/roadmap.md` 中 "Next priorities" 的前三项：异步推理、动态与部分 shape、
> Layout 与预处理。它沿用 `OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md` 的分层、风格、
> 所有权和门禁规则；本文只写**增量**，不重复 0.1 已经确立的约束。
>
> 执行者必须按阶段推进。只有当前阶段的验收门禁有可复核证据时，才可以勾选完成并
> 进入下一阶段。若本文与固定版本的 OpenVINO 官方 C 头文件或 C 绑定源码冲突，以上游
> 为准，并在 `docs/decisions/` 中记录差异和处理决定。

## 0. AI 开发代理执行入口

```text
请在 D:\nim\openvino-nim 中完整阅读 OPENVINO_NIM_0.2_DEVELOPMENT_PLAN.md，
并以 OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md 的通用规则（分层、风格、所有权、门禁）为前提，
按 Phase 0 → Phase 5 执行 0.2.0 开发。
先执行 Phase 0：复核 §2 列出的上游事实，补齐 §2.6 的“待实测”项，起草 ADR 0003–0005，
报告结果与 Gate 状态；只有当前 Gate 通过后才进入下一 Phase。
Phase 2（动态 Shape）与 Phase 3（异步推理）在 Phase 1 通过后可以并行；Phase 4 依赖 Phase 2。
持续维护 §13 Checklist，为每个勾选项保留文件、测试输出或 CI 证据。
允许的 Git、远端、tag 和发布动作只以我当前明确授予的权限为准。
```

---

## 1. 版本目标

| 项目 | 约定 |
|---|---|
| 目标版本 | `0.2.0`（新增公共能力，0.x 下的 minor 升级） |
| OpenVINO 基线 | 不变：`2026.4.x`，验证 `2026.4.0` 与 `2026.4.1`（18 个头文件字节一致，SHA-256 见 `docs/c-api-coverage.md`） |
| Nim | 不变：`>= 2.0.0`；ORC 与 ARC 都必须通过 |
| Tier 1 平台 | 不变：Windows x86_64、Linux x86_64，CPU 为发布基线 |
| 硬件验证 | GPU/NPU 通过 `nimble testHardware` 补充验证，不作为 CI 前置条件 |
| 向后兼容 | `0.1.x` 的全部公共 API 签名与语义保持不变；只新增，不改名、不删除 |

### 1.1 0.2.0 完成定义

只有同时满足以下条件，才能宣布 `0.2.0` 完成：

1. **动态 Shape**：可读取任意端口的部分 shape（含动态 rank、无界维度、有界区间）；可对
   `Model` 做 reshape；同一个动态 `CompiledModel` 可以用不同输入 shape 连续推理，并读到
   正确的输出 shape 与数据。
2. **异步推理**：`startAsync` / `wait` / `waitFor` / `cancel` 可用；完成通知不让任何 Nim
   异常、GC 分配或 Nim `ref` 跨越 C 回调边界；在运行中关闭请求、析构兜底、取消、超时都有
   测试；ORC/ARC 下压力测试与 Linux valgrind 无泄漏、无非法访问。
3. **Layout 与预处理**：可用纯 Nim 的声明式 `PreprocessPlan` 描述输入张量格式、预处理步骤、
   模型 layout 与输出元素类型，并一次性构建出新的 `Model`；数值结果与 Nim 端参考实现一致。
4. raw 层新增声明全部通过 ABI probe 与真实 runtime smoke；仍然**不调用任何 C 可变参数函数**。
5. 文档（coverage、ownership、API overview、roadmap、troubleshooting、双语 README）、
   示例、`CHANGELOG.md`、`DEVLOG.md` 与 ADR 齐全，`nimble lint`/`docs`/`packagingCheck` 通过。

---

## 2. 上游事实核对（2026-10-18，基于 2026.4.0 头文件与 C 绑定源码）

以下事实已对照本机 `C:\Program Files (x86)\Intel\openvino_2026.4.0\runtime\include\openvino\c\`
与上游 `src/bindings/c/src/*.cpp`（tag `2026.4.0`）核对。Phase 0 必须再次复核，且凡标注
“待实测”的条目必须用测试或 probe 给出证据后才能进入设计定稿。

### 2.1 需要新增的 raw 声明

| Header | 新增函数 | 备注 |
|---|---|---|
| `ov_infer_request.h` | `ov_infer_request_start_async`、`_wait`、`_wait_for`、`_cancel`、`_set_callback` | 另可补 `_set_output_tensor_by_index`、`_get_tensor_by_const_port`、`_set_input_tensor`、`_get_input_tensor`、`_set_output_tensor`、`_get_output_tensor`（非阻断） |
| `ov_infer_request.h` | 类型 `ov_callback_t { void (OPENVINO_C_API_CALLBACK *callback_func)(void*); void* args; }` | Windows 上 `OPENVINO_C_API_CALLBACK` 为 `__cdecl`，Nim 侧用 `{.cdecl.}` |
| `ov_dimension.h` | 类型 `ov_dimension_t {int64 min; int64 max;}`，`ov_dimension_is_dynamic` | 见 §2.3 quirk |
| `ov_rank.h` | `ov_rank_t = ov_dimension_t`，`ov_rank_is_dynamic` | 见 §2.3 quirk |
| `ov_partial_shape.h` | 类型 `ov_partial_shape_t {ov_rank_t rank; ov_dimension_t* dims;}`；`_create`、`_create_dynamic`、`_create_static`、`_free`、`_to_shape`、`ov_shape_to_partial_shape`、`_is_dynamic`、`_to_string` | 多数函数**按值**接收 `ov_partial_shape_t` |
| `ov_node.h` | `ov_port_get_partial_shape(const ov_output_const_port_t*, ov_partial_shape_t*)` | 可直接用于现有 `Port` |
| `ov_model.h` | `ov_model_reshape`、`_reshape_input_by_name`、`_reshape_single_input`、`_reshape_by_port_indexes` | `_reshape_by_ports` 需要可变端口 `ov_output_port_t`，继续 deferred |
| `ov_layout.h` | `ov_layout_create`、`ov_layout_free`、`ov_layout_to_string` | `_to_string` 返回堆字符串，需 `ov_free` |
| `ov_prepostprocess.h` | 40 个函数中的 39 个非可变参数函数，以及 `ov_color_format_e`（10 值）、`ov_preprocess_resize_algorithm_e`（3 值）、`ov_padding_mode_e`（4 值）三个枚举 | `ov_preprocess_input_tensor_info_set_color_format_with_subname(..., ...)` 是可变参数函数，**禁止绑定**；使用数组版 `_with_subnames` |

### 2.2 异步推理事实

| 事实 | 证据 | 设计后果 |
|---|---|---|
| `start_async`、`wait`、`cancel` 只是 C++ 调用外包 `CATCH_OV_EXCEPTIONS`；异步执行中的异常在 `wait` 时以状态码返回 | `ov_infer_request.cpp` | 错误只在 `wait`/`waitFor` 上抛出；回调本身拿不到错误 |
| `wait_for(timeout)` 的 `timeout` 单位是毫秒（`int64_t`）；超时返回 `RESULT_NOT_READY (-9)`，不是失败 | `ov_infer_request.cpp`：`return ret ? OK : RESULT_NOT_READY` | 托管层 `waitFor` 返回 `bool`，`RESULT_NOT_READY` 映射为 `false`，绝不抛异常 |
| `set_callback` 的 lambda **按指针捕获** `const ov_callback_t* callback`，并丢弃 `std::exception_ptr` | `ov_infer_request.cpp`：`[callback](std::exception_ptr ex) { callback->callback_func(callback->args); }` | `ov_callback_t` 本身必须位于稳定地址，且**寿命不短于请求**（或直到被替换且确认不在飞行中）；不能是栈变量或可移动的 Nim 值 |
| 回调在 OpenVINO 的工作线程上执行，该线程不是 Nim 创建的 | OpenVINO 异步流水线语义 | 回调 trampoline 内禁止 GC 分配、禁止抛出、禁止触碰 Nim `ref`/`string`/`seq` |
| 请求忙时再次 `start_async`/`infer`/绑定张量，返回 `REQUEST_BUSY (-8)` | M-01 实测：`start_async`、`infer`、`set_input_tensor_by_index`、`get_output_tensor_by_index` 均返回 `-8`（3/3） | 新增 `OpenVinoBusyError` 子类型；运行中读取张量同样抛出 |
| `cancel` 后 `wait` 返回 `INFER_CANCELLED (-13)` | M-02 实测：10/10；再次 `wait` 仍为 `-13`，直到下次启动；请求可复用；对已完成/空闲/未启动请求 `cancel` 返回 OK | 新增 `OpenVinoCancelledError` 子类型 |
| 从未启动的请求：`wait` 立即返回 OK，`wait_for(0)`/`wait_for(10)` 却返回 `RESULT_NOT_READY`；`wait_for(-1)` 返回 `GENERAL_ERROR` | M-03 实测 | 托管层自行跟踪 `started`；未启动时 `waitFor` 直接返回 `true`，与 `wait` 一致；负超时预先拒绝 |
| 运行中 `ov_infer_request_free` 阻塞约 15 ms 后返回，不触发回调，进程存活 | M-04 实测（隔离进程 3/3），不在 C 头文件契约中 | 托管层 `close` 不依赖该行为：先 `cancel` + `wait`，再 free |
| 回调在 `wait` 返回前已执行完毕；取消的运行也触发回调；同步 `infer` 不触发回调 | M-05 实测（2000/2000） | `CompletionQueue` 不会收到同步 `infer` 的完成通知，文档写明 |

### 2.3 动态 Shape 事实与上游 quirk

| 事实 | 证据 | 设计后果 |
|---|---|---|
| `ov_dimension_t` 是闭区间 `[min, max]`；`max == -1` 表示无上界；`check_dimension` 拒绝 `< -1` 或 `max < min` | `ov_partial_shape.cpp` L11 | **（Phase 0 修正）** 因 `max < min` 检查，`_create`/`_create_dynamic` 拒绝 `{0,-1}` 与 `{2,-1}`（M-06）；托管层写入路径**不调用** `_create*`，见下行 |
| reshape 的 `partial_shape_convert_to_cpp_object` 不调用 `check_dimension`，直接 `ov::Dimension(min, max)`；`ov_rank_is_dynamic` 为真时构造的是 **rank 1 的 `[?]`** | `ov_model.cpp` L216–237 | 托管层在 Nim 中直接填充 `ov_partial_shape_t`（`dims` 指向调用期间存活的 Nim 数组），无需 free；动态 rank 与 rank 0 的 reshape 会被 C 层静默改成 `[?]`（M-06、M-07），托管层预先拒绝 |
| 从端口读出的无界维度是 `{0, -1}`，动态 rank 是 `rank = {0, -1}` 且 `dims == nil` | `ov_node.cpp`：`get_min_length()`/`get_max_length()` | 托管层规范形式为 `{0, -1}`；`{-1, -1}` 作为输入也接受并归一化 |
| **Quirk**：`ov_dimension_is_dynamic` 与 `ov_rank_is_dynamic` 只在 `min == max && max > 0` 时返回 `false`。静态的 `0` 维度、以及 **rank 0（标量）** 都被报告为“动态” | `ov_dimension.cpp`、`ov_rank.cpp` | 托管层**不调用**这两个函数，静态判定在 Nim 中实现：`min == max and max >= 0` |
| **Quirk**：`ov_partial_shape_create` 拒绝 `rank <= 0`；`_create_static` 拒绝任何 `<= 0` 的维度，且在失败前已经把 `dims` 写入输出结构 | `ov_partial_shape.cpp` L20、L75 | 托管层不调用任何 `_create*`（见上） |
| **Quirk**：`ov_partial_shape_to_shape` 遇到中途的动态维度时，已分配的 `ov_shape_t` 没有释放就返回 `PARAMETER_MISMATCH` | `ov_partial_shape.cpp` | 托管层**不调用**该函数；`PartialShape.toShape` 纯 Nim 实现 |
| `ov_partial_shape_free` 只 `delete[] dims`，`dims == nil` 时安全 | `ov_partial_shape.cpp` | 所有由 OpenVINO 填充的 `ov_partial_shape_t` 成功后无条件释放 |
| `ov_partial_shape_to_string`、`ov_layout_to_string` 返回 `str_to_char_array` 分配的字符串 | 源码 | 复制后 `ov_free`；托管层 `$` 不依赖它们 |
| `ov_model_reshape*` 接收 `const ov_model_t*`，但会**原地修改**图 | `ov_model.cpp`：`model->object->reshape(...)` | 托管层 `reshape` 文档写明会修改 `Model`；已编译的 `CompiledModel` 不受影响 |
| 标量（rank 0）与含 0 维度的 reshape 能否经 C 层正确往返 | M-07 实测：rank 0 返回 OK 但变成 `[?]`；`[0,4]` 可 reshape、编译、推理 | 托管层拒绝 rank 0 与动态 rank 的 reshape；接受 0 维度 |

### 2.4 预处理（PPP）事实

| 事实 | 证据 | 设计后果 |
|---|---|---|
| `prepostprocessor_create` 持有 `model->object` 的 `shared_ptr` | `ov_prepostprocess.cpp` | 关闭 Nim 侧 `Model` 不会让 PPP 悬空 |
| `get_input_info*`、`get_tensor_info`、`get_preprocess_steps`、`get_model_info`、`get_output_info*` 返回的子对象只保存**指向父对象内部的裸指针**（`&(preprocess->object->input(i))`） | 源码 | 子对象**不得比父 PPP 活得久**；释放子对象只 `delete` 包装壳 |
| `build()` 返回新的 `ov_model_t`，但其中的 `ov::Model` 与源模型是**同一个对象，被原地修改** | `ov_prepostprocess.cpp` L551；M-09 实测：同一 `ov::Model` 指针，源模型输入类型由 f32 变为 u8 | 托管层必须明确“源 `Model` 已被修改” |
| `set_layout`、`convert_layout`、`model_info_set_layout` 按值复制 `layout->object` | 源码 | `ov_layout_t` 可在调用后立即释放 |
| `set_from(tensor)` 以 `const Tensor&` 读取张量信息 | `ov_prepostprocess.cpp` L286；M-10 实测：调用后立即释放张量，`build` 仍正确 | 调用后张量可立即关闭 |
| `crop` 使用 `int32_t*` 加 `int32_t` 长度；`pad` 使用 `const int*` 加 `size_t` 长度，且第一个参数是 `const` steps 指针 | 头文件 | raw 层照抄类型，不要“统一”成同一种整型 |
| `mean_multi_channels`/`scale_multi_channels` 的长度是 `int32_t` | 头文件 | 托管层校验 `len <= int32.high` |
| 输出侧 C API 只有 `ov_preprocess_output_set_element_type`，没有输出 layout 或后处理步骤 | 头文件 | 托管层的 `OutputPostprocess` 只暴露元素类型 |
| `get_input_info()`（无索引）在多输入模型上失败 | C++ 语义 | 托管层只提供按索引/按名称 |

### 2.5 可变参数 API

0.1 的规则不变：Nim 不猜平台 varargs ABI。本阶段唯一涉及的可变参数函数
`ov_preprocess_input_tensor_info_set_color_format_with_subname` 有数组版
`_with_subnames`，raw 层只绑定后者，并在 `docs/c-api-coverage.md` 写明原因。

### 2.6 Phase 0 必须实测的条目

| ID | 问题 | 方法 | 结果（2026-10-18，Windows x86_64，2026.4.0 CPU） |
|---|---|---|---|
| M-01 | 忙请求上再次 `start_async`/`infer`/`set_tensor` 的状态码 | CPU + 大输入或人为延迟（例如对同一请求快速重复调用）记录状态 | [x] 全部 `-8`，含 `get_output_tensor`（ADR 0003） |
| M-02 | `cancel` 后 `wait` 的状态码；对已完成请求 `cancel` 是否无害 | smoke 测试 | [x] `wait` 为 `-13` 且保持；对已完成请求无害（ADR 0003） |
| M-03 | 从未启动的请求调用 `wait`/`wait_for` | smoke 测试 | [x] `wait` OK；`wait_for` 返回 `-9`（ADR 0003） |
| M-04 | 运行中直接 `ov_infer_request_free` 是否阻塞、崩溃或安全 | 仅在隔离进程中实测；结果只作为背景，托管层不依赖 | [x] 阻塞约 15 ms，安全，不触发回调（ADR 0003） |
| M-05 | 回调触发时机：是否在 `wait` 返回前一定已执行完毕 | 回调里原子计数 + `wait` 后检查 | [x] 2000/2000 已执行完毕（ADR 0003） |
| M-06 | 动态维度 `{-1,-1}` 与 `{0,-1}` 经 reshape 后读回的值 | smoke 测试 | [x] 读回均为 `{0,-1}`；`_create*` 拒绝 `{0,-1}`；动态 rank 变为 `[?]`（ADR 0004） |
| M-07 | rank 0 与含 0 维度的 reshape | smoke 测试 | [x] rank 0 变为 `[?]`；`[0,4]` 正常（ADR 0004） |
| M-08 | 动态输入在未绑定张量前，`get_input_tensor` 返回什么 shape | smoke 测试 | [x] `[0,4]`，size 0；空推理也返回 OK（ADR 0004） |
| M-09 | PPP `build` 后源 `Model` 的输入元素类型是否已改变（别名） | smoke 测试 | [x] 已改变，同一 `ov::Model`（ADR 0005） |
| M-10 | `set_from(tensor)` 后立即关闭张量，`build` 是否仍正确 | smoke 测试 | [x] 正确（ADR 0005） |
| M-11 | NPU 编译无界动态模型的行为；GPU 动态 shape 推理是否可用 | `testHardware` 主机 | [ ] Phase 5 |

实测结果写入 `docs/decisions/` 对应 ADR 的 “Evidence” 节，并在本节勾选。

---

## 3. 范围与非目标

### 3.1 0.2.0 必须包含

- 托管类型 `Dimension`、`PartialShape`；`Port.partialShape`、`Port.isDynamic`；
  `Model.reshape`（单输入、按名称、按索引、按名称批量原子 reshape）。
- `InferRequest.startAsync`、`wait`、`waitFor`、`cancel`；新错误子类型
  `OpenVinoBusyError`、`OpenVinoCancelledError`。
- 无回调跨界风险的完成通知：`CompletionQueue`（§5.4）。
- `Layout`、`ColorFormat`、`ResizeAlgorithm`、`PaddingMode`；声明式
  `PreprocessPlan` 与 `applyPreprocessing`。
- 上述全部能力的 raw 声明、ABI probe、smoke、单元、集成、生命周期测试、示例和文档。

### 3.2 可选但不阻断 0.2.0

- `openvino/asyncdispatch` 适配模块：`inferAsync(request): Future[void]`，基于
  `AsyncEvent`；只有在证明 `trigger` 可以从非 Nim 线程安全调用后才合入（ADR 0003 附录）。
- 简单请求池 `InferPool`（N 个请求 + 一个 `CompletionQueue`）。完整的并发共享规则仍属于
  roadmap 的 “Request pools and concurrency”。
- 输出侧绑定辅助：`setOutputTensor`、按 `Port` 读写张量。

### 3.3 明确非目标

- **不**允许用户把任意 Nim 闭包注册为 OpenVINO 回调。Nim 代码永远只在 Nim 线程上运行。
- 不绑定 `ov_preprocess_input_tensor_info_set_color_format_with_subname`（可变参数）。
- 不在托管层暴露 `set_memory_type`（GPU surface 属于 remote context，仍 deferred）。
- 不暴露可变端口 `ov_output_port_t` 及 `ov_model_reshape_by_ports`。
- 不提供图像解码、自动 layout 推断、模型下载等业务功能。
- 不引入 chronos 或其他第三方异步运行时依赖。

---

## 4. 设计：动态 Shape（Track S）

### 4.1 模块与依赖

```text
src/openvino/raw/dimension.nim        ov_dimension_t, ov_rank_t, *_is_dynamic（仅 raw）
src/openvino/raw/partial_shape.nim    ov_partial_shape_t 与 8 个函数
src/openvino/raw/node.nim             + ov_port_get_partial_shape
src/openvino/raw/model.nim            + 4 个 reshape 函数
src/openvino/partial_shape.nim        托管 Dimension / PartialShape（纯 Nim，可无 runtime 测试）
src/openvino/private/partial_shapes.nim   托管 <-> raw 转换，集中处理 create/free 与 quirk
src/openvino/node.nim                 + partialShape / isDynamic
src/openvino/model.nim                + reshape
```

`partial_shape.nim` 依赖 `shape.nim`，不依赖任何 raw 模块，因此 `nimble test` 可以在无
OpenVINO 的环境中覆盖全部构造、比较、格式化与兼容性逻辑。

### 4.2 托管 API 草案

```nim
type
  Dimension* = object
    ## 闭区间 [minLength, maxLength]。maxLength = -1 表示无上界。
    ## 构造时已校验，存在即合法。
    lo: int64
    hi: int64

  PartialShape* = object
    ## rank 已知时 dims 有效；rank 未知（动态 rank）时 dims 为空。
    rankKnown: bool
    dimensions: seq[Dimension]

proc staticDim*(length: int64): Dimension              # length >= 0
proc dynamicDim*(): Dimension                          # [0, ∞)
proc boundedDim*(lo, hi: int64): Dimension             # 0 <= lo <= hi
proc atLeastDim*(lo: int64): Dimension                 # [lo, ∞)（Phase 2 补充：端口可读出 "2.."）
proc minLength*(d: Dimension): int64
proc maxLength*(d: Dimension): int64                   # -1 = 无界
proc hasUpperBound*(d: Dimension): bool                # Phase 2 补充
proc isStatic*(d: Dimension): bool                     # lo == hi and hi >= 0（不调用 ov_dimension_is_dynamic）
proc isDynamic*(d: Dimension): bool                    # Phase 2 补充
proc contains*(d: Dimension; length: int64): bool

proc initPartialShape*(dims: openArray[Dimension]): PartialShape
proc initPartialShape*(shape: Shape): PartialShape
proc dynamicRankShape*(): PartialShape
proc hasStaticRank*(s: PartialShape): bool
proc rank*(s: PartialShape): int                       # 动态 rank 时 raise OpenVinoArgumentError
proc dims*(s: PartialShape): seq[Dimension]            # 返回副本
proc isStatic*(s: PartialShape): bool
proc toShape*(s: PartialShape): Shape                  # 纯 Nim；非静态时 raise
proc accepts*(s: PartialShape; shape: Shape): bool     # 推理前的兼容性预检
proc `$`*(d: Dimension): string                        # "4"、"?"、"1..8"、"2.."
proc `$`*(s: PartialShape): string                     # "[?, 4]"、"[1..8, 3, 224, 224]"、"[...]"
proc `==`*(a, b: Dimension): bool
proc `==`*(a, b: PartialShape): bool

proc partialShape*(port: Port): PartialShape
proc isDynamic*(port: Port): bool
proc reshape*(model: Model; shape: PartialShape)                       # 单输入模型
proc reshape*(model: Model; inputIndex: int; shape: PartialShape)
proc reshape*(model: Model; inputName: string; shape: PartialShape)
proc reshape*(model: Model; shapes: openArray[(string, PartialShape)])  # 单次 ov_model_reshape，原子
```

### 4.3 转换与所有权规则

1. **读取**：`ov_port_get_partial_shape` 成功后，在 `finally` 中无条件
   `ov_partial_shape_free`。rank 判定：`rank.min == rank.max and rank.max >= 0` 为已知
   rank（包括 rank 0 标量）；否则为动态 rank，忽略 `dims`。
2. **写入**（Phase 0 修正，见 ADR 0004）：由 `private/partial_shapes.nim` 在 Nim 中直接
   填充 `ov_partial_shape_t`，`dims` 指向只在调用期间存活的 Nim 数组；**不调用**任何
   `ov_partial_shape_create*`（它们拒绝 `{0,-1}` 与 `{2,-1}`），也**不得**对该结构调用
   `ov_partial_shape_free`。批量 reshape 的 `cstring` 数组与 `ov_partial_shape_t` 数组同样
   只在调用期间存活。
3. 不调用 `ov_dimension_is_dynamic`、`ov_rank_is_dynamic`、`ov_partial_shape_to_shape`、
   `ov_partial_shape_is_dynamic`、`ov_partial_shape_create*`；这些函数仍在 raw 层声明，并在
   doc comment 中写明 quirk。
4. M-07/M-06 已证明 rank 0 与动态 rank 经 C 层 reshape 会被静默改成 `[?]`：托管层在进入 C
   前抛 `OpenVinoArgumentError`，消息说明这是上游 C 绑定限制。0 维度可正常 reshape、编译与
   推理，予以接受。
5. `Port.shape` 行为不变：动态端口仍抛错，错误消息改为提示使用 `partialShape`。

### 4.4 动态模型推理语义

- 动态输入：先 `setInputTensor` 绑定具体 shape 的张量，再推理；`Tensor.setShape` 已存在，
  可用于复用 OpenVINO 分配的输入张量。M-08 的结论写入文档。
- 动态输出：推理后 `outputTensor(i).shape` 反映实际 shape；同一请求换 shape 再次推理时，
  先前取出的输出 `Tensor` 不保证仍指向有效形状，文档要求每次推理后重新获取。
- `CompiledModel.input(i).partialShape` 必须可用（const port 路径）。

---

## 5. 设计：异步推理（Track A）

### 5.1 原则

1. **Nim 代码不在 OpenVINO 线程上执行。** 回调只能是包内固定的 `{.cdecl, raises: [], gcsafe.}`
   trampoline；它只做原子写入、`Lock`/`Cond` 信号和固定容量环形缓冲区写入，不分配、不抛出、
   不访问 Nim `ref`、`string`、`seq`。
2. **错误只从 `wait`/`waitFor` 返回。** 完成通知只表示“可以取结果了”，调用者随后必须
   `wait` 来获得状态（此时 `wait` 立即返回）。
3. **一个 Nim 线程即可驱动多个请求。** 0.2.0 不要求、不声明跨 Nim 线程共享
   `InferRequest`。

### 5.2 A1：阻塞式异步原语（无回调）

```nim
proc startAsync*(request: InferRequest)
  ## 立即返回。请求忙时 raise OpenVinoBusyError。
proc wait*(request: InferRequest)
  ## 阻塞到完成；推理失败 raise OpenVinoError，被取消 raise OpenVinoCancelledError。
proc waitFor*(request: InferRequest; timeout: Duration): bool
  ## true = 已完成（成功；失败时抛出），false = 超时（RESULT_NOT_READY）。
  ## timeout 为负或超过 int64 毫秒范围时 raise OpenVinoArgumentError；0 表示轮询。
proc cancel*(request: InferRequest)
  ## 请求取消；随后仍需 wait，wait 将抛 OpenVinoCancelledError（以 M-02 为准）。
```

`infer` 保持不变（同步）。`errors.nim` 新增：

```nim
OpenVinoBusyError* = object of OpenVinoError        # REQUEST_BUSY
OpenVinoCancelledError* = object of OpenVinoError   # INFER_CANCELLED
```

二者是现有 `OpenVinoError` 的子类型，`0.1` 的 `except OpenVinoError` 代码不受影响。

### 5.3 请求所有权盒子

现有 `Handle[ov_infer_request_t]` 改为 `Handle[RequestBox]`（内部类型，`allocShared0`）：

```text
RequestBox
  native:     ptr ov_infer_request_t
  callback:   ov_callback_t            # 稳定地址，寿命 = RequestBox
  slot:       CompletionSlot           # 原子 done 标志、所属 queue 指针、请求 id
  started:    Atomic[bool]             # 用于 close 判定是否需要 cancel+wait
```

释放顺序（`close` 与析构兜底一致，且都不抛异常）：

1. 若 `started` 且未完成：`ov_infer_request_cancel`，再 `ov_infer_request_wait`（忽略状态）。
2. `ov_infer_request_free(native)`。
3. 从所属 `CompletionQueue` 解除引用（原子减计数）。
4. `deallocShared(box)`。

这样 `ov_callback_t` 永远比请求活得久，满足 §2.2 的按指针捕获事实；并且不依赖 M-04 的结果。
ADR 0003 记录该决定以及对 `docs/decisions/0002-handle-model.md` 的影响（`Handle[T]` 本身
不变，只是 `T` 换成盒子类型）。

**绑定张量的寿命**（Gate 3 修订，见 ADR 0003 决定 6）：上游 `ov::InferRequest::set_tensor`
自行持有张量实现的共享引用，关闭 Nim 侧 `Tensor` 不会使绑定失效（`tasync_inference.nim` 已验证），
因此托管层**不**再保存绑定张量引用；`unsafeTensorFromPointer` 背后的宿主内存仍须由调用者保证
在 `wait` 返回前有效，文档明确写出。

### 5.4 A2：`CompletionQueue`

```nim
type CompletionQueue* = object   # 内部为 allocShared 的 Lock + Cond + 固定容量环形缓冲区 + 引用计数

proc newCompletionQueue*(capacity: int): CompletionQueue
proc attach*(queue: CompletionQueue; request: InferRequest; id: int)
  ## 安装 trampoline 回调。请求运行中调用 raise OpenVinoBusyError。
  ## 每个请求同一时间只能属于一个 queue。
proc next*(queue: CompletionQueue; timeout: Duration): Option[int]
  ## 阻塞直到某个请求完成，返回其 id；超时返回 none。只在 Nim 线程调用。
proc pending*(queue: CompletionQueue): int
proc close*(queue: CompletionQueue)
```

- trampoline 只做：`slot.done.store(true)`、加锁写入 id、`signal(cond)`、解锁。
- 容量由 `attach` 的请求数保证：每个请求同一时间最多一条未消费完成记录，因此环形缓冲区
  不会溢出；`attach` 超过容量时抛 `OpenVinoArgumentError`。
- queue 的共享内存由引用计数保护：所有附着请求释放、且 queue 自身 `close` 后才真正释放。
- 典型用法（流水线）：

```nim
let queue = newCompletionQueue(capacity = requests.len)
for id, request in requests:
  queue.attach(request, id)
  fill(request, nextBatch()); request.startAsync()
while running:
  let id = queue.next(initDuration(seconds = 5)).get()
  requests[id].wait()          # 立即返回，失败在此抛出
  consume(requests[id])
  fill(requests[id], nextBatch()); requests[id].startAsync()
```

### 5.5 A3（可选）：`openvino/asyncdispatch`

`proc inferAsync*(request: InferRequest): Future[void]`。实现前提：证明
`asyncdispatch.AsyncEvent.trigger` 在 Windows（IOCP）与 Linux（eventfd/ioselectors）上可从
非 Nim 线程调用且不分配 GC 内存；否则改为“专用 Nim 等待线程 + `CompletionQueue` + 线程安全
`trigger`”。不满足证据要求就不进 0.2.0，不得以 “看起来能跑” 合入。

### 5.6 线程与编译约束

- 测试矩阵必须包含 `--mm:orc --threads:on` 与 `--mm:arc --threads:on`。
- trampoline 所在模块加 `{.push raises: [], gcsafe.}`，并由 `nimble lint` 增加检查：
  该模块中不得出现 `new`、`&`、`$`、`echo`、`seq`/`string` 构造（文本规则 + 代码审查）。
- Linux CI 增加可选 `-fsanitize=thread` 作业（允许失败但必须上传报告），valgrind memcheck
  覆盖异步测试。

---

## 6. 设计：Layout 与预处理（Track P）

### 6.1 选择声明式计划而不是暴露六种子句柄

上游 PPP 有 6 种子对象（input info、input tensor info、steps、input model info、output info、
output tensor info），全部借用父对象内部指针（§2.4）。若在托管层逐一暴露，每个都需要“父对象
已关闭”的检查、显式 `close` 和额外文档，且极易误用。

**决定（ADR 0005）**：raw 层完整绑定；托管层只提供纯 Nim 值类型 `PreprocessPlan`，由
`applyPreprocessing` 在一次调用中创建 PPP、按顺序应用、`build`，并在 `finally` 中按与创建
相反的顺序释放全部子对象和 PPP。任何子对象都不会逃出这个函数。

### 6.2 托管 API 草案

```nim
type
  Layout* = object                     # 已由 ov_layout_create 验证的描述，如 "NCHW"、"NC?"、"[N,C,H,W]"
  ColorFormat* = enum
    cfUndefined, cfNv12SinglePlane, cfNv12TwoPlanes, cfI420SinglePlane,
    cfI420ThreePlanes, cfRgb, cfBgr, cfGray, cfRgbx, cfBgrx
  ResizeAlgorithm* = enum raLinear, raCubic, raNearest
  PaddingMode* = enum pmConstant, pmEdge, pmReflect, pmSymmetric

  PreprocessStepKind* = enum
    pskConvertElementType, pskConvertColor, pskConvertLayout, pskResize,
    pskMean, pskMeanChannels, pskScale, pskScaleChannels,
    pskCrop, pskPad, pskReverseChannels
  PreprocessStep* = object             # case object，字段只读
  InputPreprocess* = object            # 目标（索引或名称）+ 张量描述 + 步骤序列 + 模型 layout
  OutputPostprocess* = object          # 目标 + 输出元素类型
  PreprocessPlan* = object

proc initLayout*(description: string): Layout          # 需要 runtime；非法描述 raise
proc `$`*(layout: Layout): string

proc initPreprocessPlan*(): PreprocessPlan
proc input*(plan: var PreprocessPlan; index: int): var InputPreprocess
proc input*(plan: var PreprocessPlan; name: string): var InputPreprocess
proc output*(plan: var PreprocessPlan; index: int): var OutputPostprocess
proc output*(plan: var PreprocessPlan; name: string): var OutputPostprocess

# 输入张量描述（tensor info）
proc tensorElementType*(p: var InputPreprocess; t: ElementType): var InputPreprocess
proc tensorLayout*(p: var InputPreprocess; layout: Layout): var InputPreprocess
proc tensorColorFormat*(p: var InputPreprocess; format: ColorFormat;
                        subNames: openArray[string] = []): var InputPreprocess
proc tensorSpatialStaticShape*(p: var InputPreprocess; height, width: int): var InputPreprocess
proc tensorFrom*(p: var InputPreprocess; sample: Tensor): var InputPreprocess
# 步骤（按调用顺序执行）
proc convertElementType*(p: var InputPreprocess; t: ElementType): var InputPreprocess
proc convertColor*(p: var InputPreprocess; format: ColorFormat): var InputPreprocess
proc convertLayout*(p: var InputPreprocess; layout: Layout): var InputPreprocess
proc resize*(p: var InputPreprocess; algorithm: ResizeAlgorithm): var InputPreprocess
proc mean*(p: var InputPreprocess; value: float32): var InputPreprocess
proc mean*(p: var InputPreprocess; perChannel: openArray[float32]): var InputPreprocess
proc scale*(p: var InputPreprocess; value: float32): var InputPreprocess
proc scale*(p: var InputPreprocess; perChannel: openArray[float32]): var InputPreprocess
proc crop*(p: var InputPreprocess; begin, `end`: openArray[int32]): var InputPreprocess
proc pad*(p: var InputPreprocess; padsBegin, padsEnd: openArray[int];
          value = 0'f32; mode = pmConstant): var InputPreprocess
proc reverseChannels*(p: var InputPreprocess): var InputPreprocess
# 模型侧
proc modelLayout*(p: var InputPreprocess; layout: Layout): var InputPreprocess
# 输出
proc tensorElementType*(p: var OutputPostprocess; t: ElementType): var OutputPostprocess

proc applyPreprocessing*(model: Model; plan: PreprocessPlan): Model
```

示例：

```nim
var plan = initPreprocessPlan()
plan.input(0)
  .tensorElementType(etU8).tensorLayout(initLayout("NHWC"))
  .tensorSpatialStaticShape(480, 640)
  .convertElementType(etF32).resize(raLinear)
  .mean([123.675'f32, 116.28, 103.53]).scale([58.395'f32, 57.12, 57.375])
  .modelLayout(initLayout("NCHW"))
plan.output(0).tensorElementType(etF32)
let prepared = model.applyPreprocessing(plan)   # model 已被原地修改，见 §6.3
model.close()
```

### 6.3 语义与校验

- **别名**：`applyPreprocessing` 返回新的 `Model` 所有者，但与源 `Model` 指向同一张被修改的
  图（以 M-09 实测为准）。文档与 doc comment 明确：“调用后源模型已被修改；通常应立即关闭源
  模型”。若 M-09 证明不共享，则改写本条。
- **校验在 Nim 侧先做**：索引非负；名称非空；`mean`/`scale` 通道数 `1..int32.high`；
  `crop` 的 begin/end 等长；`pad` 的两组等长；`spatialStaticShape` 为正；`subNames` 无空串、
  无 NUL；枚举经映射表转换，不做 `ord` 强转。
- **错误上下文**（Phase 4 修订，以上游为准）：单次 C 调用失败时，`OpenVinoError` 的 context
  包含 `input[0].steps[3] (pskResize)` 或 `input[5]` 这样的定位；但 OpenVINO 把通道数不符、
  缺 layout 的 resize、不支持的颜色转换等语义检查推迟到 `build`，此时 context 附整个计划的
  一行摘要，并保留 OpenVINO 自身的说明。
- **释放顺序**：子对象 → PPP；临时 `ov_layout_t` 在对应调用后立即释放；全部在 `finally`。
- `PreprocessPlan` 是纯值，可复用于多个模型，可在无 runtime 时构造与单元测试（`initLayout`
  除外；`Layout` 的单元测试放在 smoke/集成层）。

---

## 7. Raw 层与 ABI probe 增量

新增 raw 模块：`raw/dimension.nim`、`raw/partial_shape.nim`、`raw/layout.nim`、
`raw/prepostprocess.nim`；扩展 `raw/infer_request.nim`、`raw/node.nim`、`raw/model.nim`，并由
`raw.nim` 汇总导出。`src/openvino.nim` 仍不导出 raw。

`tests/abi/abi_probe.c` / `tabi_layout.nim` 至少新增：

| 检查 | 期望（x86_64，以 probe 实测为准） |
|---|---|
| `sizeof/alignof(ov_dimension_t)`、字段偏移 | 16 / 8，`min@0`、`max@8` |
| `sizeof(ov_rank_t) == sizeof(ov_dimension_t)` | 相等 |
| `sizeof/alignof(ov_partial_shape_t)`、字段偏移 | 24 / 8，`rank@0`、`dims@16` |
| `sizeof(ov_callback_t)`、字段偏移 | 16，`callback_func@0`、`args@8` |
| `ov_color_format_e` 全部 10 个值与 `sizeof` | `UNDEFINE = 0` … `BGRX = 9` |
| `ov_preprocess_resize_algorithm_e` 3 个值 | `RESIZE_LINEAR = 0` … `RESIZE_NEAREST = 2` |
| `ov_padding_mode_e` 4 个值 | `CONSTANT = 0` … `SYMMETRIC = 3` |
| 按值传递 `ov_partial_shape_t` 的函数签名 | smoke 中真实调用 `ov_partial_shape_to_string` 并比对 |

三个新枚举在 raw 层与 0.1 一致，用 `cint` 别名 + 常量表示，托管层再映射为 Nim enum。
raw 层枚举常量与 0.1 已有名称冲突时（例如 `CONSTANT`），按 0.1 的命名冲突规则处理并在 ADR
中记录；不得静默改名。

---

## 8. 所有权表增量（写入 `docs/ownership.md`）

| Native 类型 / 结果 | 释放函数 | 类别 | 备注 |
|---|---|---|---|
| `ov_partial_shape_t`（由 `ov_port_get_partial_shape` 填充） | `ov_partial_shape_free` | Owned | 成功后无条件释放；托管层写入路径在 Nim 中自建结构，不经 `_create*`，不得释放 |
| `ov_partial_shape_to_string` / `ov_layout_to_string` 返回值 | `ov_free` | Owned | 复制后释放 |
| `ov_layout_t*` | `ov_layout_free` | Owned | 传入 PPP 后被复制，可立即释放 |
| `ov_preprocess_prepostprocessor_t*` | `ov_preprocess_prepostprocessor_free` | Owned | 持有模型的 shared_ptr |
| PPP 子对象（6 种） | 各自 `_free` | Owned 包装壳 + Borrowed 内容 | 不得比父 PPP 活得久；托管层不外泄 |
| `ov_model_t*`（`_build` 返回） | `ov_model_free` | Owned | 与源模型共享同一张图（M-09） |
| `ov_callback_t` | 随 `RequestBox` 的 `deallocShared` | Nim 拥有，OpenVINO 借用指针 | 必须在 `ov_infer_request_free` 之后释放 |
| `CompletionQueue` 共享内存 | 引用计数归零时 `deallocShared` | Nim 拥有 | trampoline 只借用 |

---

## 9. 错误策略增量

| 状态 | 场景 | 托管行为 |
|---|---|---|
| `RESULT_NOT_READY (-9)` | `waitFor` 超时 | 返回 `false`，不抛异常，不读取 last error |
| `REQUEST_BUSY (-8)` | 忙请求上的启动/推理/绑定 | `OpenVinoBusyError` |
| `INFER_CANCELLED (-13)` | 取消后的 `wait` | `OpenVinoCancelledError` |
| `PARAMETER_MISMATCH (-4)` | reshape 或 PPP 不兼容 | `OpenVinoError`，消息带输入名/步骤定位 |
| `INVALID_C_PARAM (-14)` | 托管层预检本应拦截的情况 | 视为包缺陷：测试必须证明托管层先抛 `OpenVinoArgumentError` |

必测错误路径：负超时；非法维度（`lo > hi`、`< -1`）；动态 shape 调 `toShape`；对动态端口调
`shape`；reshape 不存在的输入名；不兼容 reshape；在运行中关闭请求；在运行中 `attach`；
`CompletionQueue` 关闭后 `next`；非法 layout 字符串；`mean` 通道数与模型不符；空 `crop`；
已关闭 `Model` 调 `applyPreprocessing`。

---

## 10. 测试计划与 fixture

### 10.1 新增 fixture（手写 IR，遵循 `tests/fixtures/README.md` 规则并登记 SHA-256）

| 文件 | 输入 | 用途 |
|---|---|---|
| `relu_dyn_x4_f32.xml` | `input`，`f32`，`[?, 4]` | 无界批量动态推理、reshape |
| `relu_bounded_f32.xml` | `input`，`f32`，`[1..8, 4]` | 有界维度读取、越界 shape 失败 |
| `relu_1x3x4x4_f32.xml` | `input`，`f32`，`[1, 3, 4, 4]`（NCHW） | PPP：类型转换、layout 转换、mean/scale、reverse channels、resize、crop、pad 的数值验证 |

全部为无权重 ReLU，期望输出可心算；PPP 期望值由测试中的 Nim 参考实现计算（resize 用
`raNearest` 保证可精确比对，`raLinear` 只做 shape 与容差检查）。

### 10.2 测试文件

| 层次 | 文件 | 内容 |
|---|---|---|
| 单元（无 runtime） | `tests/unit/tpartial_shape.nim` | 构造校验、规范化 `{-1,-1}→{0,-1}`、`$`、`==`、`accepts`、`toShape` |
| 单元（无 runtime） | `tests/unit/tpreprocess_plan.nim` | 计划构建、链式调用、全部 Nim 侧校验 |
| ABI | `tests/abi/*` | §7 全部条目 |
| Smoke（raw） | `tests/abi/tsmoke_runtime.nim` | 新符号可解析；M-01…M-10 的固定化回归 |
| 集成 | `tests/integration/tdynamic_shape.nim` | 读取部分 shape；同一编译模型以 batch 1/3/7 推理；reshape 为静态后推理；有界越界失败 |
| 集成 | `tests/integration/tasync_inference.nim` | start/wait、waitFor 超时与完成、cancel、Busy、4 请求流水线 1000 轮结果正确 |
| 集成 | `tests/integration/tpreprocess.nim` | 各步骤数值验证、别名语义、错误定位消息 |
| 生命周期 | `tests/lifecycle/tasync_lifetime.nim` | 运行中 `close`、析构兜底、queue 先于请求关闭、请求先于 queue 关闭、重复 attach |
| 硬件 | `tests/hardware/thardware_inference.nim` | GPU 动态 shape 与异步；NPU reshape 为静态后编译与异步；记录 M-11 |

`nimble testLifecycle` 与 `testIntegration` 覆盖 ORC/ARC × debug/release；`memcheck` 纳入
异步与 PPP 测试。不新增必须的 nimble 任务；如增加 `testStress`，它只能是可选任务。

### 10.3 示例

`examples/dynamic_shape.nim`、`examples/async_infer.nim`（含 `CompletionQueue` 流水线）、
`examples/preprocess.nim`；全部纳入 `nimble examples` 并只使用仓库 fixture。

---

## 11. 文档

| 文件 | 更新 |
|---|---|
| `docs/c-api-coverage.md` | 新模块移入 “Bound”；保留 deferred：可变参数 PPP、`set_memory_type`（托管层）、可变端口、remote context |
| `docs/ownership.md` | §8 全部行 |
| `docs/api-overview.md` | 三个新能力的入口与最小示例 |
| `docs/architecture.md` | 回调 trampoline 与 `RequestBox` 一节 |
| `docs/troubleshooting.md` | `REQUEST_BUSY`、`RESULT_NOT_READY`、动态端口调 `shape`、NPU 动态 shape、PPP 别名 |
| `docs/roadmap.md` | 前三项移至 “Available in 0.2.0” |
| `docs/decisions/0003-async-completion.md` | §5 决定与 M-01…M-05 证据 |
| `docs/decisions/0004-partial-shape-representation.md` | §4 决定、上游 quirk 与 M-06…M-08 证据 |
| `docs/decisions/0005-preprocessing-api.md` | §6 决定与 M-09、M-10 证据 |
| `README.md` / `README_zh-CN.md` | 能力列表与链接 |
| `CHANGELOG.md` / `RELEASE_NOTES.md` / `DEVLOG.md` | 按 0.1 规则（DEVLOG 双语） |

---

## 12. 开发阶段与验收门禁

```text
Phase 0 ──> Phase 1 ──┬──> Phase 2 (动态 Shape) ──> Phase 4 (Layout + PPP) ──┐
                      └──> Phase 3 (异步推理) ─────────────────────────────────┴──> Phase 5 (RC)
```

### Phase 0：上游复核、实测与 ADR

- 复核 §2 所有事实；确认本机与 CI 的 header SHA-256 未变化。
- 在临时分支或 `tests/abi` 下完成 M-01…M-10 的实测（M-11 在硬件主机上补充，不阻断）。
- 起草 ADR 0003、0004、0005，状态为 “Proposed”。

**Gate 0**：§2.6 表格中 M-01…M-10 全部有证据；三个 ADR 已提交评审；没有修改任何公共 API。

### Phase 1：Raw 层与 ABI

- 实现 §2.1 / §7 全部 raw 声明；不绑定可变参数函数。
- 扩展 ABI probe 与 smoke。

**Gate 1**：`nimble lint`、`nimble testAbi`、`nimble testSmoke` 在 Windows 与 Linux 通过；
`src/openvino.nim` 未导出 raw；`docs/c-api-coverage.md` 草稿更新。

### Phase 2：动态 Shape（Track S）

- `partial_shape.nim`、`private/partial_shapes.nim`、`Port.partialShape`、`Model.reshape`。
- `tpartial_shape.nim`、`tdynamic_shape.nim`、两个动态 fixture、`examples/dynamic_shape.nim`。

**Gate 2**：`nimble test`、`testIntegration`、`testLifecycle`、`examples` 通过；同一动态编译模型
三种 batch 推理结果正确；valgrind 无新增泄漏；ADR 0004 改为 “Accepted”。

### Phase 3：异步推理（Track A）

- 3a：`RequestBox` 迁移（行为对 0.1 测试零差异）→ `startAsync`/`wait`/`waitFor`/`cancel` →
  新错误子类型。
- 3b：trampoline、`CompletionQueue`、`tasync_lifetime.nim`、`examples/async_infer.nim`。
- 3c（可选）：`openvino/asyncdispatch`，需单独证据。

**Gate 3**：0.1 的全部测试无修改通过（证明 `RequestBox` 迁移无回归）；异步集成与生命周期测试在
ORC/ARC × debug/release 通过；1000 轮 × 4 请求压力测试稳定；Linux valgrind 无错误；trampoline
模块通过 lint 规则；ADR 0003 改为 “Accepted”。

### Phase 4：Layout 与预处理（Track P）

- `Layout`、三个枚举、`PreprocessPlan`、`applyPreprocessing`。
- `tpreprocess_plan.nim`、`tpreprocess.nim`、NCHW fixture、`examples/preprocess.nim`。

**Gate 4**：每种步骤至少一个数值验证用例通过；别名语义有测试；错误消息含步骤定位；valgrind
无泄漏；ADR 0005 改为 “Accepted”。

### Phase 5：硬件、文档与 0.2.0 RC

- `testHardware` 补充 GPU/NPU 动态与异步用例，记录 M-11。
- §11 全部文档；版本号 `0.2.0` 在 `openvino.nimble`、`version.nim`、文档中一致（`releaseCheck`）。
- `nimble docs`、`packagingCheck`、`releaseArchive`（dry run）。

**Gate 5**：CI 全绿；硬件结果写入 `docs/compatibility.md`；`CHANGELOG`/`RELEASE_NOTES` 完成；
等待项目所有者授予 tag 与发布权限。

### 12.1 每阶段报告模板

沿用 0.1 计划 §17.1：完成项、证据（命令与输出摘要）、Gate 结果、发现的偏差、下一步。

---

## 13. 可执行 Checklist

### Z. Phase 0 复核与实测

- [x] Z-01 复核 18 个头文件 SHA-256 与 `docs/c-api-coverage.md` 一致。证据：本机 `openvino_2026.4.0\runtime\include\openvino\c\` 顶层 18 个头文件 `Get-FileHash` 结果与文档逐一相同（`gpu/` 子目录 2 个头文件不在固定集合内）
- [x] Z-02 复核 §2.2–§2.4 源码事实（附上游文件与行号）。证据：tag `2026.4.0` 的 C 绑定源码，行号写入 ADR 0003–0005；发现并修正两处计划偏差（`_create*` 拒绝 `{0,-1}`；动态 rank/rank 0 reshape 变为 `[?]`），见 §2.3、§4.3
- [x] Z-03 M-01 … M-10 实测并记录。证据：§2.6 结果列与 ADR 0003–0005 Evidence 节；probe 位于会话产物目录，Phase 1 固化进 `tests/abi/tsmoke_runtime.nim`
- [x] Z-04 ADR 0003 / 0004 / 0005 草案。证据：`docs/decisions/0003-async-completion.md`、`docs/decisions/0004-partial-shape-representation.md`、`docs/decisions/0005-preprocessing-api.md`，状态均为 proposed；`tools/mdcheck.nim` 通过

### R. Raw 层与 ABI

- [x] R-01 `raw/infer_request.nim`：`start_async`、`wait`、`wait_for`、`cancel`、`set_callback`、`ov_callback_t`。证据：文件（另补 6 个非阻断的单输入/输出与 const port 函数）；`ov_callback_func` 类型带 `cdecl, gcsafe, raises: []`；smoke “asynchronous inference” 5 项
- [x] R-02 `raw/dimension.nim`：`ov_dimension_t`、`ov_rank_t`、两个 `_is_dynamic`（doc comment 写明 quirk）。证据：文件；smoke “the is_dynamic predicates misreport…”
- [x] R-03 `raw/partial_shape.nim`：类型与 8 个函数。证据：文件；smoke “partial shapes and their quirks” 6 项
- [x] R-04 `raw/node.nim`：`ov_port_get_partial_shape`。证据：smoke 读回测试
- [x] R-05 `raw/model.nim`：4 个 reshape 函数。证据：smoke “the batch reshape and the by-index reshape apply atomically”
- [x] R-06 `raw/layout.nim`：3 个函数。证据：smoke “layouts (0.2.0)”
- [x] R-07 `raw/prepostprocess.nim`：39 个非可变参数函数、7 个不透明类型、3 个枚举。证据：文件；smoke 符号解析 + “every child object, step and output setter can be driven”
- [x] R-08 ABI probe：§7 全部条目。证据：`tests/abi/abi_probe.c`、`tabi_layout.nim` 新增 3 个 suite（callback、dimension/partial shape 的 size/align/offset、3 个枚举逐值）；Windows（gcc，2026.4.0 头文件）与 Linux（Ubuntu 26.04，gcc 15.2，2026.4.1 头文件）`nimble testAbi` 通过。Linux 上发现 Nim 2.2.4 + gcc 15 对泛型元组表的 C 指针类型不兼容，测试辅助改为 template
- [x] R-09 smoke：新符号解析 + 真实调用。证据：`nimble testSmoke` 29/29（Windows 2026.4.0、Linux 2026.4.1），含 M-01…M-03、M-05…M-10 的固化回归
- [x] R-10 `lint`：raw 未被 `openvino.nim` 导出；无可变参数声明。证据：`openvino.nimble` lint 新增规则（忽略注释行），用临时 `{.varargs.}` 声明验证会失败，删除后 `nimble lint` 两平台通过

### S. 动态 Shape

- [x] S-01 `Dimension` 构造、校验、规范化、`$`、`==`。证据：`src/openvino/partial_shape.nim`；`tests/unit/tpartial_shape.nim` “dimensions” 6 项；`{-1,-1}` 的归一化在 `private/partial_shapes.nim` 读取路径
- [x] S-02 `PartialShape` 构造、rank 查询、`toShape`、`accepts`、`$`、`==`。证据：同上 “partial shapes”“accepts” 两个 suite
- [x] S-03 `private/partial_shapes.nim`：读取/写入转换，所有路径释放。证据：读取在 `finally` 中 `ov_partial_shape_free`；写入借用 Nim 数组、无分配；Linux `memcheck` 新增 dynamic 目标 0 errors / 0 definitely lost
- [x] S-04 `Port.partialShape`、`Port.isDynamic`；`Port.shape` 错误消息改进。证据：`tdynamic_shape.nim` “reading partial shapes” 6 项（含消息含 `partialShape`）
- [x] S-05 `Model.reshape` 四个重载；批量 reshape 原子。证据：“reshape”“reshape errors” suite，含“a batch reshape naming a missing input changes no input”
- [x] S-06 rank 0 / 0 维度按 M-07 结论处理。证据：rank 0 与动态 rank 在进入 C 前抛 `OpenVinoArgumentError`；`[0,4]` reshape/编译/推理测试通过
- [x] S-07 fixture `relu_dyn_x4_f32.xml`、`relu_bounded_f32.xml` 与校验和。证据：`tests/fixtures/README.md`；`nimble lint` 中 fixturecheck 通过（3 个 fixture）
- [x] S-08 单元 + 集成测试；`examples/dynamic_shape.nim`。证据：Gate 2 在 Windows（2026.4.0）与 Linux（2026.4.1）上 formatCheck、lint、test、testAbi、testSmoke、testLifecycle、testIntegration、examples、docs（仅 Windows）、memcheck（仅 Linux）全部通过；ADR 0004 已 Accepted

### A. 异步推理

- [x] A-01 `RequestBox` 迁移，0.1 测试零修改通过。证据：`InferRequest` 改持 `Handle[RequestBox]`（`allocShared0`）；`git status` 显示 0.1 的 unit/lifecycle/integration/hardware 测试文件未修改，`test`、`testLifecycle`、`testIntegration`、`examples` 两平台通过
- [x] A-02 `OpenVinoBusyError`、`OpenVinoCancelledError` 与状态映射。证据：`errors.nim` 在 `newOpenVinoError` 中按状态选子类型（全包生效）；集成测试检查 `err of OpenVinoBusyError`
- [x] A-03 `startAsync`、`wait`、`waitFor`（`Duration`）、`cancel`。证据：`tasync_inference.nim` “start, wait and waitFor”“busy and cancelled”；`waitFor` 毫秒向上取整，负值/溢出预先拒绝，未启动直接返回 `true`
- [x] A-04 `close`/析构兜底的 cancel → wait → free → 解除 queue → dealloc 顺序。证据：`releaseRequest`；`tasync_lifetime.nim` 运行中 close 与析构兜底用例（ORC/ARC × debug/release）
- [x] A-05 请求持有最近绑定张量的引用 → **以上游为准取消**：上游自行持有张量引用，见 §5.3 修订与 ADR 0003 决定 6；证据测试 “a bound tensor may be closed before the run; OpenVINO keeps it”
- [x] A-06 trampoline（`cdecl`、`raises: []`、`gcsafe`、无分配）与 lint 规则。证据：`src/openvino/private/trampoline.nim` 直接调用 OS 锁/条件变量，模块关闭 stackTrace/lineTrace/checks；lint 规则在植入 `echo` 时报错、清理后通过
- [x] A-07 `CompletionQueue`：容量、引用计数、`attach`/`next`/`pending`/`close`。证据：`tasync_inference.nim` “completion queue” 7 项；`queued` 标志保证每请求至多一条，环不会溢出
- [x] A-08 集成、生命周期、压力测试；valgrind；可选 TSan 作业。证据：4 请求 × 1000 轮全部结果正确；Linux `memcheck` 新增 async 目标 0 errors / 0 definitely lost；TSan 因 OpenVINO 以 `RTLD_DEEPBIND` 加载 `libtbbbind` 无法运行（已记录于 ADR 0003）
- [x] A-09 `examples/async_infer.nim`。证据：`nimble examples` 两平台通过
- [ ] A-10（可选）`openvino/asyncdispatch` 与线程安全证据 —— 未纳入 0.2.0（无可从外部线程安全调用 `trigger` 的证据）

### P. Layout 与预处理

- [x] P-01 `Layout`（`initLayout` 验证、`$`）。证据：`src/openvino/preprocess.nim`；`tpreprocess.nim` “layouts” 2 项（规范形式、非法描述、NUL）
- [x] P-02 `ColorFormat`、`ResizeAlgorithm`、`PaddingMode` 与 raw 映射表。证据：`rawColorFormats` 等数组映射，不用 `ord` 强转；raw 值由 ABI 测试校验
- [x] P-03 `PreprocessStep`、`InputPreprocess`、`OutputPostprocess`、`PreprocessPlan` 与链式 API。证据：`tpreprocess_plan.nim` “building a plan” 5 项；builder 为 `var` + `{.discardable.}`
- [x] P-04 Nim 侧全部校验。证据：`tpreprocess_plan.nim` “argument checks” 4 项（索引/名称、mean/scale、crop/pad、spatial/sub-name）
- [x] P-05 `applyPreprocessing`：创建、应用、build、逆序释放、错误定位。证据：子对象在嵌套 `finally` 中逆序释放；Linux `memcheck` preprocess 目标 0 errors / 0 definitely lost；单次调用失败定位到 `input[i]…`，build 期失败附整个计划摘要（以上游为准，见 §6.3 修订与 ADR 0005 决定 5）
- [x] P-06 别名语义按 M-09 实现并文档化。证据：`tpreprocess.nim` “the source model is modified and shares its graph with the result”；doc comment 明确
- [x] P-07 fixture `relu_1x3x4x4_f32.xml` 与校验和。证据：`tests/fixtures/README.md`；fixturecheck 通过（4 个 fixture）
- [x] P-08 单元 + 集成数值测试；`examples/preprocess.nim`。证据：每种步骤至少一个数值用例；Gate 4 在 Windows 与 Linux 全部 nimble 任务通过；ADR 0005 已 Accepted

### D. 文档、硬件与发布

- [x] D-01 §11 全部文档更新。证据：`docs/c-api-coverage.md`、`ownership.md`、`api-overview.md`、`architecture.md`、`troubleshooting.md`、`roadmap.md`、`compatibility.md`、`README.md`、`README_zh-CN.md`；`tools/mdcheck.nim` 通过
- [x] D-02 ADR 0003–0005 定稿为 Accepted。证据：三份 ADR 的 Status 行与 “Verification at acceptance” 节；ADR 0003 另含 Phase 5 硬件证据（NPU 不支持 cancel）
- [x] D-03 `testHardware` GPU/NPU 动态与异步用例，`docs/compatibility.md` 更新。证据：Windows 主机 ORC/ARC × debug/release 共 244 项通过；M-11：GPU/GPU.0/GPU.1 支持无界与有界动态，NPU 拒绝无界、接受有界与静态，NPU 不支持 `cancel`；写入 compatibility.md 设备表
- [x] D-04 版本号 `0.2.0` 全仓一致，`releaseCheck` 通过。证据：`version.nim`、`openvino.nimble`；`nimble releaseCheck` 两平台通过
- [x] D-05 `docs`、`packagingCheck`、`releaseArchive` dry run 通过。证据：Windows `docs`、两平台 `packagingCheck` 通过；在 Linux 从 git bundle 克隆的提交 `d7c9933` 上 `ci/release-archive.py --date 2026-10-18 --dry-run` 生成 `openvino-nim-0-2-0-2026-10-18-ov2026-4-1` 的 4 个资产并校验，两次构建逐字节一致；`--self-test` 通过
- [x] D-06 `CHANGELOG.md`、`RELEASE_NOTES.md`、`DEVLOG.md`（双语）。证据：三文件已更新，DEVLOG 中英条目数一致（mdcheck 校验）

Gate 5（2026-10-18）：本机 Windows 与 Linux 全部任务、`testHardware`、`docs`、`packagingCheck`、`releaseCheck`、`releaseArchive` dry run 均通过；项目所有者已授权提交、推送、打 tag 与发布，GitHub Actions CI 全绿后发布 `v0.2.0`。

---

## 14. 风险清单

| 风险 | 影响 | 缓解 |
|---|---|---|
| 回调在非 Nim 线程执行时触发 GC 分配或异常 | 随机崩溃、内存损坏 | trampoline 白名单操作 + lint 规则 + ORC/ARC/TSan/valgrind |
| `ov_callback_t` 被按指针捕获 | 栈地址或移动后的对象导致悬空调用 | `RequestBox` 中稳定地址，释放顺序固定在请求之后 |
| 运行中关闭请求 | 释放仍在使用的张量或请求 | `close` 先 cancel+wait；请求持有绑定张量引用 |
| 上游 `*_is_dynamic` 把 0 当作动态 | 标量与 0 维被误判 | 托管层自行判定，不调用这些函数 |
| 上游 `ov_partial_shape_to_shape` 泄漏 | 内存泄漏 | 托管层不调用；纯 Nim 实现 |
| PPP `build` 原地修改源模型 | 用户以为源模型未变 | 文档、doc comment、测试三处明确 |
| PPP 子对象借用父对象内部指针 | 悬空访问 | 子对象不出 `applyPreprocessing` |
| NPU 不支持无界动态 shape | 硬件用例失败 | 先 reshape 为静态；记录为兼容性说明而非缺陷 |
| `asyncdispatch` 的跨线程 `trigger` 未被证明安全 | 偶发死锁或崩溃 | A3 设为可选，无证据不合入 |
| `RequestBox` 迁移破坏 0.1 行为 | 回归 | Gate 3 要求 0.1 测试零修改通过 |

---

## 15. 参考

- 本机头文件：`C:\Program Files (x86)\Intel\openvino_2026.4.0\runtime\include\openvino\c\`
  （`ov_infer_request.h`、`ov_partial_shape.h`、`ov_dimension.h`、`ov_rank.h`、`ov_layout.h`、
  `ov_prepostprocess.h`、`ov_model.h`、`ov_node.h`、`ov_common.h`）
- 上游 C 绑定源码（tag `2026.4.0`）：
  [`ov_infer_request.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_infer_request.cpp)、
  [`ov_partial_shape.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_partial_shape.cpp)、
  [`ov_dimension.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_dimension.cpp)、
  [`ov_rank.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_rank.cpp)、
  [`ov_node.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_node.cpp)、
  [`ov_model.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_model.cpp)、
  [`ov_layout.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_layout.cpp)、
  [`ov_prepostprocess.cpp`](https://github.com/openvinotoolkit/openvino/blob/2026.4.0/src/bindings/c/src/ov_prepostprocess.cpp)
- 仓库内：`OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md`、`docs/roadmap.md`、`docs/c-api-coverage.md`、
  `docs/ownership.md`、`docs/decisions/0001-symbol-loading.md`、`docs/decisions/0002-handle-model.md`
