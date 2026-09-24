# OpenVINO-Nim-API

[English](README.md) | **简体中文**

OpenVINO Runtime C API 的 Nim 绑定。项目主文档以英文维护，本页提供中文
入口和关键说明；API 名称、代码示例和兼容性结论以英文文档为准。

**本项目由社区维护，不是 Intel 或 OpenVINO 官方项目，也没有得到 Intel
Corporation 的认可或附属关系。** OpenVINO 是 Intel Corporation 的商标。

## 项目状态

版本 `0.1.0` 仍在开发中，尚未发布。当前已经验证的范围是：

- Windows x86_64 和 Linux x86_64；
- Nim 2.2.12 和 2.2.4；
- OpenVINO Runtime `2026.4.0`；
- CPU 上的同步推理、生命周期、ABI、集成和示例测试。

GPU、NPU、macOS、异步回调、动态 shape 和预处理不在当前已验证声明中。
请查看英文的[兼容性矩阵](docs/compatibility.md)和[路线图](docs/roadmap.md)。

## 快速开始

1. 安装 OpenVINO Runtime `2026.4.x`，并在当前 shell 执行官方环境配置脚本。
2. 克隆仓库并安装本地 Nim 包：

   ```shell
   git clone https://github.com/AbyssGG/OpenVINO-Nim-API.git
   cd OpenVINO-Nim-API
   nimble install
   ```

3. 运行仓库内的验证示例：

   ```shell
   nimble examples
   ```

英文[入门指南](docs/getting-started.md)包含 Windows/Linux 的动态库检查、
测试命令和常见故障处理。

## 名称约定

| 名称 | 用途 |
|---|---|
| `OpenVINO-Nim-API` | 项目显示名和 GitHub 仓库名 |
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
