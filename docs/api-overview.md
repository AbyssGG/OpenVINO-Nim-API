# API overview

OpenVINO Nim API has a small managed surface and an explicit raw C layer. The
managed surface is the compatibility target for application code; raw modules
mirror the pinned OpenVINO 2026.4 C headers and are intentionally less safe.

## Managed modules

| Module | Main symbols | Responsibility |
|---|---|---|
| `openvino` | `newCore`, `RuntimeVersion`, exceptions | Stable import root; raw declarations are not re-exported |
| `openvino/core` | `Core`, `runtimeVersion`, `availableDevices` | Runtime loading, model reading, compiling and import |
| `openvino/model` | `Model`, `inputCount`, `outputCount`, `reshape` | Model metadata, const ports and reshaping |
| `openvino/node` | `Port`, `name`, `elementType`, `shape`, `partialShape`, `isDynamic` | Read-only input and output port metadata |
| `openvino/compiled_model` | `CompiledModel`, `createInferRequest` | Device-specific compiled graph and explicit blob export |
| `openvino/infer_request` | `InferRequest`, `infer`, `startAsync`, `wait`, `waitFor`, `cancel`, `CompletionQueue` | Blocking and asynchronous inference, completion notification and profiling |
| `openvino/tensor` | `Tensor`, `tensorFrom`, `toSeq` | Typed tensor creation, copying and data access |
| `openvino/shape` | `Shape`, `initShape` | Static, validated dimensions |
| `openvino/partial_shape` | `Dimension`, `PartialShape`, `staticDim`, `dynamicDim`, `boundedDim`, `atLeastDim` | Dynamic, bounded and unknown-rank shapes, runtime-free |
| `openvino/preprocess` | `Layout`, `PreprocessPlan`, `applyPreprocessing` | Declarative layout, element type, color, resize and normalisation steps |
| `openvino/properties` | `Property`, `enableProfiling`, `cacheDirectory` | Safe string-valued runtime properties |
| `openvino/errors` | `OpenVinoError`, `OpenVinoBusyError`, `OpenVinoCancelledError`, `OpenVinoArgumentError`, `OpenVinoLibraryError`, `OpenVinoVersionError` | Runtime, busy, cancelled, argument, loader and version failures |
| `openvino/version` | `PackageVersion`, `TargetOpenVinoVersion` | Package metadata and the pinned runtime baseline |

All managed handles have an idempotent `close()` and a destructor backstop.
Copying a managed value shares the native handle and closed state; it does not
make a second native owner. See [ownership](ownership.md) for the exact rules.

`runtimeVersion()` queries the loaded runtime without creating a `Core`.
Call `requireSupportedRuntime()` to reject a runtime whose major/minor version
does not match `2026.4`, or whose build string cannot be parsed. This check
does not compare patch versions and is not called automatically.

`Model.input()` and `Model.output()` return `Port` handles that you must close.
`Port.shape()` returns a copy of the static dimensions and raises
`OpenVinoError` on a dynamic port; `Port.partialShape()` reads any port,
including dynamic and bounded dimensions. `Port.name()` returns one associated
name and can fail if the port is unnamed.

## Dynamic shapes

```nim
let model = core.readModel("tests/fixtures/relu_1x4_f32.xml")
model.reshape(initPartialShape([dynamicDim(), staticDim(4)]))   # [?, 4]
let compiled = core.compileModel(model, "CPU")
model.close()
let request = compiled.createInferRequest()
for batch in [1, 3, 7]:
  let input = tensorFrom(etF32, initShape(batch, 4), newSeq[float32](batch * 4))
  request.setInputTensor(0, input)
  request.infer()
  input.close()
  let output = request.outputTensor(0)   # [batch, 4]; fetch it again each run
  output.close()
```

`reshape` modifies the `Model` in place; a `CompiledModel` built earlier keeps
its shape. The OpenVINO 2026.4 C API cannot express a scalar or an unknown rank
in a reshape, so both are refused with `OpenVinoArgumentError`. An unbound
dynamic input reads as an empty tensor (`[0, 4]` above) until one is bound.
See [ADR 0004](decisions/0004-partial-shape-representation.md).

## Asynchronous inference

```nim
let queue = newCompletionQueue(capacity = requests.len)
for id, request in requests:
  queue.attach(request, id)
  request.startAsync()
while running:
  let id = queue.next(initDuration(seconds = 5)).get
  requests[id].wait()        # returns at once; raises if the run failed
  # read outputs, bind the next input, then requests[id].startAsync()
```

`startAsync` returns immediately; `wait` and `waitFor` are the only places a
failed run is reported. `waitFor` returns `false` on a timeout rather than
raising. A request that is running raises `OpenVinoBusyError` for a second
start, `infer`, and binding or reading tensors; after `cancel`, `wait` raises
`OpenVinoCancelledError`. Not every device can cancel: the Intel NPU plugin
reports `OpenVinoError`. Closing a running request is safe; it is cancelled
where possible and waited for.

No Nim code runs on OpenVINO's threads: `CompletionQueue` installs one
package-internal C callback that only records which request finished, and you
collect it on your own thread with `next`. There is no API to register a Nim
procedure as a callback. See [ADR 0003](decisions/0003-async-completion.md).

## Layout and preprocessing

```nim
var plan = initPreprocessPlan()
plan.input(0)
  .tensorElementType(etU8).tensorLayout(initLayout("NHWC"))
  .tensorSpatialStaticShape(480, 640)
  .convertElementType(etF32).resize(raLinear)
  .mean([float32(123.675), 116.28, 103.53]).scale([float32(58.395), 57.12, 57.375])
  .modelLayout(initLayout("NCHW"))
let prepared = model.applyPreprocessing(plan)
model.close()   # the source model was modified too
```

A plan is a plain value that can be reused and needs no runtime until it is
applied. `applyPreprocessing` creates and releases every OpenVINO
preprocessing object itself. Many mistakes, such as a channel count that does
not match, are only detected by OpenVINO when the plan is built; the error
message then includes a summary of the whole plan. See
[ADR 0005](decisions/0005-preprocessing-api.md).

## Raw modules

`import openvino/raw` is an explicit opt-in. It exposes raw pointers, C status
codes and the ownership contracts from the pinned headers. The raw layer is
useful when a managed wrapper is not yet available, but callers must release
native allocations and must not let Nim exceptions cross a C callback boundary.

The binding covers Core, model and port metadata, static and partial shapes,
reshape, tensors, compiled models, synchronous and asynchronous inference
requests with `ov_callback_t`, layouts, the non-variadic pre/post-processing
API, profiling and non-variadic properties. It deliberately excludes variadic
entry points, mutable ports and remote contexts. A raw caller who installs a
callback must keep the `ov_callback_t` alive and at a fixed address for as long
as the request exists, and its function must not allocate, raise or touch Nim
memory. The exact symbol list and header checksums are in
[C API coverage](c-api-coverage.md).

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

Keep memory given to `unsafeTensorFromPointer` valid until inference has
completed. Tensors created by OpenVINO, including by `tensorFrom`, may be
closed once bound: the request keeps its own reference. Tensor getters return
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
