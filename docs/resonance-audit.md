# Resonance 原型审计（Phase 0 基线）

本文记录 `openvino-nim` 0.1.0 重构开始前，对 `D:\nim\openvino-nim`
工作树的只读审计结果，对应开发计划 Phase 0 与 Checklist 项 A01–A09。

审计时间：2026-09-24。审计者：AI 开发代理（Kiro）。

本文只描述现状与处理决定，不代表已经执行删除或重命名。Phase 0 Gate
通过前，`src/resonance/` 与 `resonance.nimble` 必须原样保留。

## 1. 仓库状态（A01）

通过 `git rev-parse`、`git log`、`git remote -v` 和 `git status` 实测：

| 项目 | 实测结果 |
|---|---|
| 分支 | `main` |
| 提交 | 无提交（`HEAD` 为 unborn，`git log` 报 "does not have any commits yet"） |
| remote | 无（`git remote -v` 输出为空） |
| 工作树状态 | 全部为未跟踪项 |

`git status --porcelain` 的完整输出：

```text
?? .kiro/
?? OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md
?? examples/
?? resonance.nimble
?? src/
```

结论：仓库尚无任何可恢复的 Git 基线。开发计划 §18.1 要求在审计来源与
secrets 之后才建立基线提交，因此 A08 需要项目所有者的明确授权。

## 2. 文件清单与体积（A02）

排除 `.git/` 后的全部文件：

| 相对路径 | 字节数 | 类型判定 |
|---|---:|---|
| `OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md` | 87997 | 手写文档 |
| `resonance.nimble` | 343 | 手写清单 |
| `src/resonance.nim` | 341 | 手写 Nim |
| `src/resonance/c_api.nim` | 5471 | 手写 Nim（raw 绑定） |
| `src/resonance/compiled_model.nim` | 744 | 手写 Nim |
| `src/resonance/core.nim` | 3677 | 手写 Nim |
| `src/resonance/errors.nim` | 719 | 手写 Nim |
| `src/resonance/infer_request.nim` | 1781 | 手写 Nim |
| `src/resonance/model.nim` | 195 | 手写 Nim |
| `src/resonance/perf_count_wrapper.c` | 2213 | 手写 C |
| `src/resonance/tensor.nim` | 1592 | 手写 Nim |
| `examples/basic_infer.nim` | 651 | 手写 Nim |
| `.kiro/settings/cli.json` | 349 | 本机编辑器设置 |
| `.kiro/settings/.kirocrew-cli-settings.lock` | 0 | 本机锁文件 |

审计判定：

- 没有 runtime 二进制、DLL/SO、SDK、模型权重、cache blob 或归档。
- 没有构建产物（无 `nimcache/`、无 `.exe`、无 `.o`）。
- 没有 credentials。对 `.kiro/` 做了 `token|secret|password|api_key|credential`
  的大小写不敏感扫描，唯一命中为 `cli.json` 中的 `toolSearch.minTokens`
  配置项，属于编辑器工具预算设置，不是凭据。
- `.kiro/` 属于本机编辑器状态而非库源码，应由 Phase 1 的 `.gitignore`
  排除，不进入发布归档。

## 3. 来源与许可证（A04）

| 来源 | 结论 |
|---|---|
| `resonance.nimble` 声明 | `author = "WANG"`，`license = "Apache-2.0"` |
| 源码文件头 | 全部缺少 SPDX 标识，无第三方版权头 |
| `LICENSE` 文件 | 不存在（仅 `.nimble` 元数据声明 Apache-2.0） |
| 第三方代码痕迹 | 未发现从其他项目复制的实现片段 |

### 3.1 上游归属已确认

原型代码并非孤立的未发布副本。它对应已发布仓库
[AbyssGG/Resonance](https://github.com/AbyssGG/Resonance)，描述为
"Resonance: A Nim OpenVINO C API wrapper / binding library with Intel
NPU-oriented runtime helpers."，许可证 Apache-2.0，主要语言 Nim，默认分支
`main`，最后推送 2026-08-20。该描述与本地 `resonance.nimble` 的
`description` 字段逐字相同。

对全部 11 个原型文件做了本地与 `AbyssGG/Resonance@main` 的 SHA-256 比对，
结果全部为**字节级一致**：

```text
resonance.nimble                       IDENTICAL-BYTES  343
src/resonance.nim                      IDENTICAL-BYTES  341
src/resonance/c_api.nim                IDENTICAL-BYTES  5471
src/resonance/errors.nim               IDENTICAL-BYTES  719
src/resonance/core.nim                 IDENTICAL-BYTES  3677
src/resonance/model.nim                IDENTICAL-BYTES  195
src/resonance/compiled_model.nim       IDENTICAL-BYTES  744
src/resonance/infer_request.nim        IDENTICAL-BYTES  1781
src/resonance/tensor.nim               IDENTICAL-BYTES  1592
src/resonance/perf_count_wrapper.c     IDENTICAL-BYTES  2213
examples/basic_infer.nim               IDENTICAL-BYTES  651
```

由此得到三个结论：

1. **许可证与作者归属确认。** 代码是项目所有者自有、已以 Apache-2.0 公开
   发布的作品，不存在需要 NOTICE 或第三方归属的成分。A04 由此关闭，不再
   需要"无法确认即列为重写"的兜底判断。
2. **基线丢失风险接近于零。** 本地工作树与已发布版本零分叉，没有任何未
   发布改动会因删除本地文件而丢失。`AbyssGG/Resonance` 的 Git 历史本身
   就是可恢复基线。§8 的 Gate 判断据此下调严重度。
3. **重写决定不变，但理由改变。** `c_api.nim` 与 `perf_count_wrapper.c`
   仍然列为**重写**，原因不再是来源不明，而是 §7 记录的实测 ABI 缺陷：
   元素类型枚举偏移、状态码命名错误、`ov_tensor_set_shape` 签名错误、
   last-error 泄漏和 Windows-only variadic 桥接。

### 3.2 下游消费者

同一账户下另有两个依赖 Resonance 的已发布项目，可作为 §7 边界划分的实证：

| 仓库 | 描述要点 | 许可证 |
|---|---|---|
| [AbyssGG/Isvik](https://github.com/AbyssGG/Isvik) | 面向 Intel AI PC 的本地 AI 推理运行时平台，100% Nim + OpenVINO | Apache-2.0 |
| [AbyssGG/NimVoice](https://github.com/AbyssGG/NimVoice) | 完全离线的 Nim 本地 TTS，使用 OpenVINO C API 与 Intel NPU，并声明 attribution to Resonance | MIT |

这证实了开发计划 §7 的依赖方向假设：Isvik 与 NimVoice 是下游，
`openvino-nim` 必须保持通用，不得反向依赖二者，也不得把它们的设备策略、
缓存策略或业务流程并入公共 API。

`openvino-nim` 目前在该账户下**没有**对应仓库。因此未来任何推送都需要先
创建新仓库，属于 §17 规则 13 要求单独授权的动作。

## 4. OpenVINO 基线（A05）

本机安装（仅作为首次核对依据，**不得写入库代码**）：

| 项目 | 实测值 |
|---|---|
| 安装根目录 | `C:\Program Files (x86)\Intel\openvino_2026.4.0` |
| 版本符号链接 | `openvino_2026` → `openvino_2026.4.0`（SymbolicLink） |
| C header 目录 | `runtime\include\openvino\c` |
| Release 运行库目录 | `runtime\bin\intel64\Release` |
| C API 动态库 | `openvino_c.dll`（234248 字节） |
| 可见 device plugin | CPU、GPU、NPU、AUTO、AUTO_BATCH、HETERO |
| 可见 frontend | IR、ONNX、PaddlePaddle、PyTorch、TensorFlow、TFLite、GGUF |

固定上游事实来源（开发计划 §8.1、§22.1）：

- 上游 tag：`2026.4.0`
- 上游发布 commit：`99c8149`
- header 集合：`runtime/include/openvino/c/*.h`

本机 header 的 SHA-256（小写十六进制）：

```text
4f0848514cbd06361e8b3b933ceb810f82dade251cf546dd9f23e46a0bd3111b  deprecated.h
d5e92d0f526199c46d288c07ae82c4dc4e074f5adde1d5ce836c72a47220b1a0  openvino.h
a5dd4572f231054e3f2a8c7f77558f257f43b8bc9dbc2c1ffc2b3999dd9e50fd  ov_common.h
f49bbf08a264d06d834b3c2bd43bff826d255766e90e64092d27037bac07e218  ov_compiled_model.h
f2f8dfcd7e29cc16a9780b33b929f656fc8ad7e38248cd7ac38c154668617cb3  ov_core.h
6902eef9978a7ea551e2c562e76f66cf04611fb52225fb4863d3fbcbd5afd6ab  ov_dimension.h
094d1373417110201add3a9474d65017114fee051000a9dd842f50a67553d47c  ov_infer_request.h
812efb23a0aa81aebdbde7ade704fc8476861a7a0e2fb2efb015744b7af88282  ov_layout.h
c30d0f655c3065197fbec3a7575a65214bb75b8b51984351ff54ac0f74232ae6  ov_model.h
d3bf280719c445139680347fc411dbf3088dcd510bfc3b5faa765f0430b04ab9  ov_node.h
a242870caaef1ec9f6a50d01883fbc6d8721ead2b30e6dd4aa32ce9ce077bf7b  ov_partial_shape.h
7643323d197dd17068f01f75669d299297fc3d82891b35532ebea17fa3f518cb  ov_prepostprocess.h
22b8d5366cf57cd6fd41c224a26368cc6d399ac9b34ee5f67d9b9c39f5a18fec  ov_property.h
10ff53b49b5911b92edd96004711639003aeb577ab9a26d783e1812d1ee99267  ov_rank.h
cc3ae68e51e3161bd7f2bc443a2ba38071d22e3325e43b0084f7064aa1fe78bd  ov_remote_context.h
a12a4c241bccbc9cd3cf68f39b13c91701a78cd062a97004ae8f1612b10d4650  ov_shape.h
01c3e0de53079e6c099a078b1ca166eaf10b7fdf604124666a04e7657e6a7240  ov_tensor.h
1602a78a8a3e29c4810629d5a362177f988fe2889a2fb0da07ff7493bb068846  ov_util.h
```

这些 checksum 是本机安装包的证据。Phase 2 建立
`docs/c-api-coverage.md` 时，必须同时记录实际下载的官方发布物 URL 及其
checksum，并与上述值交叉核对；若不一致必须记录 ADR 而非静默采用。

## 5. 平台与工具链（A06、A07）

| 项目 | 决定 | 证据/说明 |
|---|---|---|
| Tier 1 平台 | Windows x86_64、Linux x86_64 | 开发计划 §11.1，本次确认不变 |
| 发布基线设备 | CPU | GPU/NPU 不作为构建或发布前置条件 |
| 本机 Nim | 2.2.12（Windows amd64） | `nim --version` 实测 |
| 最低 Nim 候选 | 2.0.0 | 发布前以 CI 实测为准 |
| 内存管理器范围 | ORC 与 ARC 为阻断；refc 仅记录结论 | 对应 D14 |

### 5.1 与开发计划的偏差记录

开发计划 §2.1 记载“本机已发现 Nim 2.2.10”。实测为 **Nim 2.2.12**。这是
本机工具链升级造成的漂移，不影响任何 ABI 结论。处理方式：Phase 1 固定
`nimpretty`/Nim 版本时以实测版本为基准，并在 CI 中显式 pin，不沿用文档中
的 2.2.10。

## 6. 逐文件处理决定（A03）

分类含义：

- **保留概念**：职责进入新包，但代码重写。
- **重写**：按固定 2026.4.0 header 重新实现，不做机械改名。
- **迁出**：职责不属于通用 OpenVINO 绑定，留给 Resonance/Isvik 下游。
- **删除**：新架构中不再存在。

| 现有文件 | 分类 | 处理决定 |
|---|---|---|
| `src/resonance.nim` | 重写 | 由 `src/openvino.nim` 取代；不再无差别 `export c_api` |
| `src/resonance/c_api.nim` | 重写 | 按 header 拆为 `src/openvino/raw/*.nim`，逐项核对 |
| `src/resonance/errors.nim` | 保留概念 | 保留“状态转异常”；重写 last-error 复制与 `ov_free` |
| `src/resonance/core.nim` | 保留概念 + 迁出 | 通用 Core 能力重写；缓存/profiling 策略迁出 |
| `src/resonance/model.nim` | 保留概念 | 重写为私有 handle + 幂等 close + port metadata |
| `src/resonance/compiled_model.nim` | 保留概念 | 重写；`exportModelToFile` 改为显式 export/import |
| `src/resonance/infer_request.nim` | 保留概念 | 重写；profiling 列表释放合约与 index 校验 |
| `src/resonance/tensor.nim` | 重写 | 重写外部 buffer 生命周期、dtype/容量/溢出检查 |
| `src/resonance/perf_count_wrapper.c` | 删除 | 由 2026.4 非 variadic properties API 取代 |
| `examples/basic_infer.nim` | 重写 | 拆为 `list_devices` / `sync_infer` / `tensor_basics` |
| `resonance.nimble` | 重写 | 由 `openvino.nimble` 取代（Nimble 标识 `openvino`） |
| `.kiro/` | 排除 | 本机编辑器状态，加入 `.gitignore` |

### 6.1 必须迁出的具体业务职责

`src/resonance/core.nim` 中以下内容**不得**进入 `openvino` 包的稳定 API：

- `compileOrImportModel`：“blob 存在就 import，否则 read + compile +
  `createDir` + export”的整套策略。
- `blobCachePath` 参数及其隐含的 cache 命名与目录创建行为。
- 返回值中的 `cacheHit` 标志。
- `enableProfiling` 布尔参数触发的 `nv_enable_perf_count` 重新开启逻辑。
- `compileModelWithProfiling`：与通用 properties 功能重复的入口。

替代方案：Phase 4 只提供显式的 `readModel`、`compileModel`（接受
properties）、`importModel`、`exportModel`，由下游自行组合缓存策略。

## 7. 必须修复的已知 ABI 问题

本节是 Phase 0 Gate 的强制内容。以下结论已通过读取本机
`ov_common.h`（SHA-256 `a5dd4572…`）直接核对，不是推测。

### 7.1 状态码错误

旧 `c_api.nim` 把 `-10` 命名为 `ALLOCATED`，并且枚举在 `-13` 截止。

`ov_common.h` 中 `ov_status_e` 的实际定义包含：

```text
NOT_ALLOCATED = -10
INFER_NOT_STARTED = -11
NETWORK_NOT_READ = -12
INFER_CANCELLED = -13
INVALID_C_PARAM = -14
UNKNOWN_C_ERROR = -15
NOT_IMPLEMENT_C_METHOD = -16
UNKNOW_EXCEPTION = -17
```

处理：raw 层重新绑定全部 18 个值，逐值 probe。`UNKNOW_EXCEPTION` 的上游
拼写必须原样保留，属于 ABI 例外。

### 7.2 元素类型枚举错位

旧 `c_api.nim` 为 `U1 = 11`、`U4 = 12`、`U8 = 13`，并在 `U64 = 16` 截止。

`ov_common.h` 中 `ov_element_type_e` 从 `DYNAMIC = 0U` 起隐式递增，实际序列为：

```text
DYNAMIC BOOLEAN BF16 F16 F32 F64 I4 I8 I16 I32 I64
U1 U2 U3 U4 U6 U8 U16 U32 U64
NF4 F8E4M3 F8E5M3 STRING F4E2M1 F8E8M0
```

即 `U1 = 11`、`U2 = 12`、`U3 = 13`、`U4 = 14`、`U6 = 15`、`U8 = 16`，共
26 个值（0–25）。旧绑定从 `U2` 起全部错位，`U8` 偏移 3。这会让任何
`u8` 输入 tensor 被当成 `U3` 处理。

补充 ABI 例外：header 中符号拼写为 `F8E5M3`，而其文档注释写的是
`f8e5m2`。raw 层必须保留符号名 `F8E5M3`，不得按注释“纠正”。

处理：不复制旧枚举；从 header 重建并对全部 26 个值做 probe。

### 7.3 `ov_tensor_set_shape` 签名错误

旧绑定声明为 `shape: ptr OvShape`。本机 `ov_tensor.h`（SHA-256
`01c3e0de…`）的实际声明为按值传递：

```c
OPENVINO_C_API(ov_status_e)
ov_tensor_set_shape(ov_tensor_t* tensor, const ov_shape_t shape);
```

同一 header 中 `ov_tensor_create`、`ov_tensor_create_from_host_ptr` 和
`ov_tensor_create_from_string_array` 同样按值接收 `const ov_shape_t`。
`ov_shape.h`（SHA-256 `a12a4c24…`）定义 `ov_shape_t` 为
`{ int64_t rank; int64_t* dims; }`，并提供 `ov_shape_create` /
`ov_shape_free` 管理 `dims` 的堆内存。

处理：Phase 2 全部改为按值签名，并加入真实 by-value 调用回归测试（C17）。
额外发现：`ov_tensor_create` 提供 OpenVINO 自有分配的 Tensor，旧代码完全
没有绑定，导致只能走外部 host pointer 路径；这正是计划 §6.4 要求的安全
默认入口，Phase 4 必须以它为 `newTensor` 的实现基础。

### 7.4 last error 泄漏

旧 `errors.nim` 的 `lastErrorDetail` 把 `ov_get_last_err_msg()` 转成 Nim
string 后直接返回，从不调用 `ov_free`，每次失败泄漏一块分配。

`ov_common.h` 明确区分两者：

- `ov_get_error_info(ov_status_e)` 的返回值是进程生命周期内的静态字符串，
  注释写明 **MUST NOT be passed to `ov_free()`**。
- `ov_free(const char*)` 用于释放需要调用者回收的字符串。

处理：失败后立即取指针、复制、在 `finally` 中 `ov_free`；`ov_get_error_info`
的结果绝不释放。

### 7.5 Windows-only variadic 桥接

`src/resonance/perf_count_wrapper.c` 的问题（逐项核对该文件后确认）：

- 无条件 `{.compile: "perf_count_wrapper.c".}`，Linux 构建必然失败。
- 依赖 `__declspec(dllimport)`、`LoadLibraryA`、`GetProcAddress`。
- 依赖 GCC 专有的 `__attribute__((ms_abi)))` 做 MinGW→MSVC variadic 桥接。
- 硬编码 `"openvino_c.dll"` 与 `"PERF_COUNT"` 字符串常量。
- 导出 `nv_*` 自定义符号，属于计划明令删除的对象。
- 失败时统一返回 `-1`（`GENERAL_ERROR`），丢失真实状态码。

处理：Phase 2 完成非 variadic properties 绑定后删除该文件；profiling 改用
官方 `ov_property_key_enable_profiling` 与 `*_props` / `*_set_properties`。

### 7.6 其他必须在 raw 层修复的问题

| 问题 | 旧实现 | 处理 |
|---|---|---|
| C enum 布局未验证 | 依赖 Nim 默认 enum 布局 | 使用明确 ABI 表示并 probe `sizeof`/值 |
| 库名写死 | `const dllName* = "openvino_c.dll"` | 集中到 `private/library.nim`，支持编译期覆盖 |
| property key 手写 | `OvPropertyKeyEnableProfiling = "PERF_COUNT"` | 绑定官方导出的 `const char*` 数据符号 |
| raw 与安全层混导出 | `src/resonance.nim` 直接 `export c_api` | raw 只能由 `openvino/raw` 显式导入 |
| 公开裸指针 | `pCore*`、`pTensor*` 等字段均为 `*` 导出 | handle 字段改为私有 |
| profiling 列表释放 | `if infoList.size > 0` 才释放 | 成功即按合约释放，不以 size 判断 |
| `OvProfilingInfo.status` | 声明为 `int32`，与枚举分离 | 按 header 核对实际类型并 probe offset |

## 8. Phase 0 Gate 结论

| Gate 条目 | 状态 | 证据 |
|---|---|---|
| 所有旧文件都有处理结论和许可证结论 | 通过 | 本文 §3、§3.1、§6 |
| 用户现有改动没有被覆盖 | 通过 | 只新增文件；11 个原型文件内容未被触碰，见 §3.1 的字节级比对 |
| 可恢复的 Resonance 基线存在 | 通过 | 双重保障：`AbyssGG/Resonance@main` 与本地零分叉（§3.1），且已按所有者授权建立本地基线提交与 `archive/resonance-before-openvino-nim` 分支/标签 |
| 审计文档列出三个已知 ABI 错误与 Windows 桥接 | 通过 | 本文 §7.1–§7.5 |
| Gate 通过前不删除 `src/resonance`、不改包入口 | 遵守 | `resonance.nimble` 的删除发生在基线提交之后；`src/resonance/` 完整保留至 Phase 2 重写完成 |

Phase 0 Gate 全部关闭。基线一项的风险等级在 §3.1 确认上游归属后大幅下调：
即使本地基线不存在，`AbyssGG/Resonance` 的发布历史也足以完整恢复原型。
本地基线提交的价值因此从"防止丢失"变为"让本仓库历史自洽"。
