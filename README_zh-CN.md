# OpenVINO Nim API

[English](README.md) | **简体中文**

OpenVINO Runtime C API 的 Nim 绑定。项目主文档以英文维护，本页提供中文
入口和关键说明；API 名称、代码示例和兼容性结论以英文文档为准。

**本项目由社区维护，不是 Intel 或 OpenVINO 官方项目，也没有得到 Intel
Corporation 的认可或附属关系。** OpenVINO 是 Intel Corporation 的商标。

## 项目状态

版本 `0.1.1` 已于 2026-10-18 发布，针对 OpenVINO `2026.4.1`（同时兼容并已验证
`2026.4.0`）。请从
[GitHub Release](https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.1.1)
下载四个校验过的源码资产。当前已经实测验证的范围是：

- Windows 11 x86_64（Nim 2.2.12）与 Ubuntu 26.04 x86_64（Nim 2.2.4）；
- OpenVINO Runtime `2026.4.1`（build `22982`）与 `2026.4.0`（build `22959`）；
- **CPU**（`Intel(R) Core(TM) Ultra 7 270K Plus`）、**GPU.0**（`Intel(R)
  Graphics (iGPU)`）、**GPU.1**（`NVIDIA GeForce RTX 5080 (dGPU)`）与 **NPU**
  （`Intel(R) AI Boost`）上的模型编译、同步推理（位置参数、按名称绑定、请求内
  置输入 tensor）、外部零拷贝缓冲区（`unsafeTensorFromPointer`）、非 ASCII 模
  型路径、性能剖析（`enableProfiling()`）以及显式编译模型 Blob 导出/导入
  （`exportTo` / `importModel`），均在 `--mm:orc` 与 `--mm:arc`（debug 与
  release）下通过测试（`nimble testIntegration` 与 `nimble testHardware`）。

需要注意一处实测的插件差异：当编译模型时**未启用** `enableProfiling()`，调用
`request.profilingInfo()` 在 `CPU` 上返回耗时为 0 的节点列表，在 `NPU` 上返回空
列表 `@[]`，而在 `GPU`（`GPU`、`GPU.0`、`GPU.1`）上会抛出 `OpenVinoError`；当使
用 `[enableProfiling()]` 编译时，三类硬件插件均正常返回带计时的执行节点。

macOS 尚未验证。异步推理、回调、动态形状 API 和预处理尚未实现。请查看英文的
[兼容性矩阵](docs/compatibility.md)和[路线图](docs/roadmap.md)。

## 快速开始

1. 安装 OpenVINO Runtime `2026.4.x`。Windows 使用 CMD 调用 `setupvars.bat`；
   Linux 在 Bash 中使用 `source` 加载 `setupvars.sh`。后续命令在同一会话执行。
2. 使用 Nimble 安装包（或克隆仓库至本地以运行自带示例与测试套件）：

   ```shell
   # 通过 Nimble 官方包索引安装（nim-lang/packages #3578）：
   nimble refresh
   nimble install openvino

   # 或直接通过 GitHub 仓库 URL 安装：
   nimble install https://github.com/AbyssGG/OpenVINO-Nim-API

   # 或克隆仓库并在本地安装：
   git clone https://github.com/AbyssGG/OpenVINO-Nim-API.git
   cd OpenVINO-Nim-API
   nimble install
   ```

3. 在本地仓库目录中运行验证示例（若有 GPU/NPU 硬件，还可运行硬件兼容性套件）：

   ```shell
   nimble examples
   nimble testHardware
   ```

英文[入门指南](docs/getting-started.md)包含 Windows/Linux 的动态库检查、
测试命令和常见故障处理。

Nimble 官方包索引条目已提交（[nim-lang/packages #3578](https://github.com/nim-lang/packages/pull/3578)）。
安装后的包名和导入名均为 `openvino`，代码中使用 `import openvino`。

示例使用仓库自带的无权重 ReLU 模型，预期输出为 `@[0.0, 2.0, 0.0, 4.0]`。
接入自己的模型时，需要修改输入个数、元素类型、形状、数据准备和结果校验；
仅替换模型路径不足以完成适配。有权重的 IR 模型还需要对应的 `.bin` 文件。

## 名称约定

| 名称 | 用途 |
|---|---|
| `OpenVINO Nim API` | 项目显示名 |
| `OpenVINO-Nim-API` | GitHub 仓库名 |
| `openvino-nim` | 发布归档前缀 |
| `openvino` | Nimble 包标识和 `import` 根模块 |
| `openvino.nimble` | Nimble 清单文件 |

名称的详细约束、发布归档命名和 ABI 说明请阅读英文
[README](README.md)。

## 文档入口

- [英文 README](README.md)
- [英文入门指南](docs/getting-started.md)
- [英文 API overview](docs/api-overview.md)
- [英文 C API coverage](docs/c-api-coverage.md)
- [英文 compatibility matrix](docs/compatibility.md)
- [英文 troubleshooting](docs/troubleshooting.md)
- [贡献指南](CONTRIBUTING.md)
- [安全策略](SECURITY.md)

## 许可证

Apache-2.0，详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。
