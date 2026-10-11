# r/nim: OpenVINO Runtime bindings for Nim — v0.1.0

I've released [OpenVINO Nim API](https://github.com/AbyssGG/OpenVINO-Nim-API),
an Apache-2.0 community project with an idiomatic managed layer
(`import openvino`) and a separate raw C ABI layer (`import openvino/raw`).
It is not official or affiliated with Intel/OpenVINO.

The managed API covers synchronous inference, model metadata, tensors,
properties, device discovery, profiling and explicit compiled-model blob I/O.
Native handles have idempotent `close()` methods and a destructor backstop.

Nim lets the inference application run without Python, although OpenVINO
libraries/plugins and models are still required. The current baseline is
Nim >= 2.0.0 and OpenVINO 2026.4.x, verified against 2026.4.0 on CPU with
Windows/Linux x86_64. GPU, NPU and macOS are unverified; async callbacks,
dynamic-shape APIs and preprocessing are planned, not implemented.

```shell
nimble install https://github.com/AbyssGG/OpenVINO-Nim-API
```

That is a Git install: the Nimble registry entry is not published yet.
Configure OpenVINO separately using the README instructions.
The checkout has managed examples and a tiny weight-free ReLU model.

I'd welcome Nim-specific feedback on ownership, errors, documentation and
example use cases. [Release](https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.1.0).
