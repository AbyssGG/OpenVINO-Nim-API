# API overview

OpenVINO-Nim-API has a small managed surface and an explicit raw C layer. The
managed surface is the compatibility target for application code; raw modules
mirror the pinned OpenVINO 2026.4 C headers and are intentionally less safe.

## Managed modules

| Module | Main symbols | Responsibility |
|---|---|---|
| `openvino` | `newCore`, `RuntimeVersion`, exceptions | Stable import root; raw declarations are not re-exported |
| `openvino/core` | `Core`, `runtimeVersion`, `availableDevices` | Runtime loading, model reading, compiling and import |
| `openvino/model` | `Model`, `inputCount`, `outputCount` | Model metadata and const ports |
| `openvino/compiled_model` | `CompiledModel`, `createInferRequest` | Device-specific compiled graph and explicit blob export |
| `openvino/infer_request` | `InferRequest`, `infer`, `inputTensor`, `outputTensor` | Blocking inference and profiling |
| `openvino/tensor` | `Tensor`, `tensorFrom`, `toSeq` | Typed tensor creation, copying and data access |
| `openvino/shape` | `Shape`, `initShape` | Static, validated dimensions |
| `openvino/properties` | `Property`, `enableProfiling`, `cacheDirectory` | Safe string-valued runtime properties |
| `openvino/errors` | `OpenVinoError`, `OpenVinoLibraryError` | Actionable exceptions instead of raw status codes |

All managed handles have an idempotent `close()` and a destructor backstop.
Copying a managed value shares the native handle and closed state; it does not
make a second native owner. See [ownership](ownership.md) for the exact rules.

## Raw modules

`import openvino/raw` is an explicit opt-in. It exposes raw pointers, C status
codes and the ownership contracts from the pinned headers. The raw layer is
useful when a managed wrapper is not yet available, but callers must release
native allocations and must not let Nim exceptions cross a C callback boundary.

The binding covers the synchronous path: Core, model and const-port metadata,
static shapes, tensors, compiled models, inference requests, profiling and
non-variadic properties. It deliberately excludes variadic entry points,
dynamic shapes, preprocessing, remote contexts and callbacks. The exact symbol
list and header checksums are in [C API coverage](c-api-coverage.md).

## Typical call sequence

```text
Core -> readModel/compileModel -> CompiledModel
                                    -> InferRequest
Tensor -> setInputTensor -> infer -> outputTensor -> copy values
```

`infer()` blocks until the request completes. There is no implicit device
selection, fallback, cache directory, model download or postprocessing policy.
Those belong in the application layer.

## Stability

The managed API is the supported 0.x application surface. The raw layer is
header-faithful but may change when its pinned OpenVINO baseline changes. New
features should be added to the managed layer only after an ownership and
lifetime design, a success test, a failure-path test and a coverage update.
