# 自荐：OpenVINO Nim API v0.1.0，用 Nim 调用 OpenVINO Runtime

我发布了 [OpenVINO Nim API](https://github.com/AbyssGG/OpenVINO-Nim-API)
的 v0.1.0：基于 Apache-2.0 许可证的 OpenVINO Runtime C API Nim 绑定。
这是社区项目，不是 Intel / OpenVINO 官方项目，也没有官方背书。

项目提供两层接口：

- `import openvino`：Nim 风格的托管句柄、异常、形状校验和张量操作；
- `import openvino/raw`：显式导入、忠实于 C 头文件的原始 ABI 声明。

目前实现了同步推理、模型元信息、设备发现、属性配置、节点 profiling，
以及编译模型 blob 的显式导入/导出。句柄提供幂等的 `close()`，
析构作为兜底；借用调用者内存的接口明确标为 unsafe。

为什么选择 Nim？它编译为原生程序，推理应用无需 Python 运行时，
可以减少小型部署中的应用栈。不过仍需 OpenVINO 动态库、插件和模型文件，
不是“单文件部署”，也没有尚未测量的性能或体积数据。

当前要求 Nim >= 2.0.0、OpenVINO 2026.4.x，已经在 Windows/Linux x86_64
上使用 2026.4.0 验证 CPU 推理。GPU、NPU、macOS 尚未验证；
异步回调、动态形状 API 和预处理仍在路线图中。

Nimble 索引尚未提交，可直接从 Git 安装：

```shell
nimble install https://github.com/AbyssGG/OpenVINO-Nim-API
```

OpenVINO 运行时需单独安装并配置加载路径。README 提供快速开始，
仓库包含无需下载的无权重 ReLU 模型及托管层示例。
图片解码、归一化和结果解释由应用负责，不是现成的图像分类工具。

欢迎反馈 API 使用体验、文档问题和可复现的错误。

- 仓库：https://github.com/AbyssGG/OpenVINO-Nim-API
- 发布：https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.1.0

## 发布前提示（不作为正文）

V2EX 可按节点规则发布到“分享创造”；掘金可补充实际复现的操作步骤；
HelloGitHub 自荐可将以上项目简介填入其当前模板。发布前检查各平台规则，
不要批量重复投放，也不要加入没有实测的性能数字。
