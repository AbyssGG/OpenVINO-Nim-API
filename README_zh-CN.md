# OpenVINO Nim API

[English](README.md) | **简体中文**

OpenVINO Runtime C API 的 Nim 绑定。项目主文档以英文维护，本页提供中文
入口和关键说明；API 名称、代码示例和兼容性结论以英文文档为准。

Nim 编译为原生程序，推理应用不需要 Python 运行时，适合减少部署中的应用栈。
这不意味着单文件部署：OpenVINO 动态库、插件和模型仍需单独提供。

**本项目由社区维护，不是 Intel 或 OpenVINO 官方项目，也没有得到 Intel
Corporation 的认可或附属关系。** OpenVINO 是 Intel Corporation 的商标。

## 项目状态

版本 `0.1.0` 已于 2026-09-25 发布。请从
[GitHub Release](https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.1.0)
下载四个校验过的源码资产。当前已经验证的范围是：

- Windows x86_64 和 Linux x86_64；
- Nim 2.2.12 和 2.2.4；
- OpenVINO Runtime `2026.4.0`；
- CPU 上的同步推理、生命周期、ABI、集成和示例测试。

GPU、NPU 和 macOS 尚未验证。异步推理、回调、动态形状 API 和预处理尚未实现。
请查看英文的[兼容性矩阵](docs/compatibility.md)和[路线图](docs/roadmap.md)。

## 快速开始

1. 安装 OpenVINO Runtime `2026.4.x`。Windows 使用 CMD 调用 `setupvars.bat`；
   Linux 在 Bash 中使用 `source` 加载 `setupvars.sh`。后续命令在同一会话执行。
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

Nimble 索引条目尚未发布，因此目前从仓库安装。安装后的包名和导入名均为
`openvino`，代码中使用 `import openvino`。

不需要示例和模型文件时，也可以直接从 Git 安装：

```shell
nimble install https://github.com/AbyssGG/OpenVINO-Nim-API
```

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

- [生成的 API 文档站](https://abyssgg.github.io/OpenVINO-Nim-API/)（维护者启用 Pages 后可用）
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
