# Show: OpenVINO Runtime bindings for Nim — v0.1.0

I've released [OpenVINO Nim API](https://github.com/AbyssGG/OpenVINO-Nim-API),
a community-maintained, Apache-2.0 binding to the OpenVINO Runtime C API.
It is not an official Intel/OpenVINO project.

There are two entry points:

- `import openvino`: managed handles, Nim exceptions, validated shapes,
  tensors, model metadata and synchronous inference.
- `import openvino/raw`: explicit, header-faithful C ABI declarations.

The managed layer also exposes device discovery, properties, per-node
profiling and explicit compiled-model blob export/import. Each handle offers
an idempotent `close()`; borrowed-memory operations are explicitly unsafe.

Why Nim? Native applications without a Python inference runtime. OpenVINO
libraries, plugins and models are still separate deployment dependencies.
There are no benchmark or single-file deployment claims.

The current baseline is Nim >= 2.0.0 and OpenVINO 2026.4.x, verified against
2026.4.0 on CPU with Windows/Linux x86_64. GPU, NPU and macOS inference are
not verified. Async callbacks, dynamic-shape APIs and preprocessing are roadmap
items, not features of this release.

Install from Git while the Nimble registry submission is pending:

```shell
nimble install https://github.com/AbyssGG/OpenVINO-Nim-API
```

Install OpenVINO separately and configure its loader path. The README has
a quick start, and the checkout includes a tiny weight-free ReLU model and
managed examples, so the first inference does not require a model download.

[Source and quick start](https://github.com/AbyssGG/OpenVINO-Nim-API) ·
[v0.1.0 release](https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.1.0)

I'd welcome feedback on the Nim API, ownership ergonomics and documentation.
Reproducible reports and small example/documentation improvements are useful
contributions. What would you want from an OpenVINO binding for Nim?
