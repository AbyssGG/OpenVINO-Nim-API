# API overview

OpenVINO Nim API has a small managed surface and an explicit raw C layer. The
managed surface is the compatibility target for application code; raw modules
mirror the pinned OpenVINO 2026.4 C headers and are intentionally less safe.

## Managed modules

| Module | Main symbols | Responsibility |
|---|---|---|
| `openvino` | `newCore`, `RuntimeVersion`, exceptions | Stable import root; raw declarations are not re-exported |
| `openvino/core` | `Core`, `runtimeVersion`, `availableDevices` | Runtime loading, model reading, compiling and import |
| `openvino/model` | `Model`, `inputCount`, `outputCount` | Model metadata and const ports |
| `openvino/node` | `Port`, `name`, `elementType`, `shape` | Read-only input and output port metadata |
| `openvino/compiled_model` | `CompiledModel`, `createInferRequest` | Device-specific compiled graph and explicit blob export |
| `openvino/infer_request` | `InferRequest`, `infer`, `inputTensor`, `outputTensor` | Blocking inference and profiling |
| `openvino/tensor` | `Tensor`, `tensorFrom`, `toSeq` | Typed tensor creation, copying and data access |
| `openvino/shape` | `Shape`, `initShape` | Static, validated dimensions |
| `openvino/properties` | `Property`, `enableProfiling`, `cacheDirectory` | Safe string-valued runtime properties |
| `openvino/errors` | `OpenVinoError`, `OpenVinoArgumentError`, `OpenVinoLibraryError`, `OpenVinoVersionError` | Runtime, argument, loader and version failures |
| `openvino/version` | `PackageVersion`, `TargetOpenVinoVersion` | Package metadata and the pinned runtime baseline |

All managed handles have an idempotent `close()` and a destructor backstop.
Copying a managed value shares the native handle and closed state; it does not
make a second native owner. See [ownership](ownership.md) for the exact rules.

`runtimeVersion()` queries the loaded runtime without creating a `Core`.
Call `requireSupportedRuntime()` to reject a runtime whose major/minor version
does not match `2026.4`, or whose build string cannot be parsed. This check
does not compare patch versions and is not called automatically.

`Model.input()` and `Model.output()` return `Port` handles that you must close.
`Port.shape()` returns a copy of the static dimensions. `Model.isDynamic()`
can detect dynamic dimensions, but `0.1.0` has no partial-shape or model
reshape API; querying a dynamic port with `shape()` raises `OpenVinoError`.
`Port.name()` returns one associated name and can fail if the port is unnamed.

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

1. Create a `Core` with `newCore()`.
2. Call `core.compileModel(modelPath, device)` to read and compile in one
   step. To inspect port metadata first, call `core.readModel(modelPath)` and
   then `core.compileModel(model, device)`. Both paths perform blocking work.
3. Create an `InferRequest` with `compiled.createInferRequest()`.
4. Use `tensorFrom` to copy prepared data into a tensor, then bind every input
   with `request.setInputTensor(index, tensor)` or the name overload. Indexes
   start at zero; names must exist in the model.
5. Call `request.infer()`. It blocks until inference completes.
6. Get the output with `request.outputTensor(index)` and copy its values with
   `toSeq`. Close the returned tensor handle after reading it.

Keep the input tensor open until inference completes. Tensor getters return
new handles that you must close, even when their storage belongs to the
request. `tensorFrom` copies input data; `toSeq` returns an independent Nim
sequence. Typed access checks element width and size, but does not convert
data or distinguish integer and floating-point types of the same width.
Match the Nim data type to the model's declared element type.

For repeated inference, keep the compiled model and request, update input
storage with `copyFrom`, and call `infer()` again. `copyFrom` requires exactly
the tensor's element count. Read or copy each output before the next inference
overwrites the request's storage.

Use `defer: object.close()` after creating each owned handle. Close tensor
and port handles when finished, then the request, compiled model and `Core`.
The uncompiled `Model` can be closed after compilation. Avoid closing an
object while another thread uses it, and use a separate request per thread;
concurrent use has not been verified by this project.

Specify the device explicitly. Device fallback, cache directories, model
downloads and postprocessing are application policies.

Pass properties such as `enableProfiling()` to `compileModel` explicitly.
Read `profilingInfo()` after inference; its strings and timings are Nim-owned
copies. `exportTo(path)` writes a compiled blob, while
`core.importModel(blob, device)` takes the blob's bytes rather than a path.
Import requires the same runtime version, device and compatible hardware.

## Stability

The managed API is the supported 0.x application surface. The raw layer is
header-faithful but may change when its pinned OpenVINO baseline changes. New
features should be added to the managed layer only after an ownership and
lifetime design, a success test, a failure-path test and a coverage update.
