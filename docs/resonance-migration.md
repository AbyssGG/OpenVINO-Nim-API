# Migrating from the Resonance prototype

`openvino-nim` grew out of a prototype called Resonance. The prototype is
preserved at the Git tag `archive/resonance-before-openvino-nim` and is not part
of this package any more. This document maps its API onto the current one and
says what changed behind each name.

Read this if you have code written against Resonance. If you are starting fresh,
you do not need it.

## What is not a rename

Three of the prototype's behaviours are absent on purpose, not renamed. If your
code depends on one of them, you keep that logic in your own project.

| Prototype | Why it is gone |
|---|---|
| `compileOrImportModel` | It bundled a policy: if a blob exists at `blobCachePath`, import it; otherwise read, compile, `createDir` and export. Whether a blob is stale, whether the hardware still matches, and where a cache belongs are all application decisions |
| `blobCachePath`, `cacheHit` | Same reason. A binding that invents cache filenames and creates directories is deciding something it cannot know |
| `compileModelWithProfiling` | Profiling is a property. A separate compilation entry point suggests it changes the kind of thing a compiled model is |

The replacement for all three is composition you can read:

```nim
let compiled =
  if fileExists(blobPath) and blobIsStillValid():
    core.importModel(readFile(blobPath), device)
  else:
    let fresh = core.compileModel(modelPath, device, @[enableProfiling()])
    fresh.exportTo(blobPath)
    fresh
```

Longer than one call, and every decision in it is yours and visible.

## Name-by-name

| Resonance | `openvino-nim` | Behaviour change |
|---|---|---|
| `import resonance` | `import openvino` | The raw layer is no longer re-exported; `import openvino/raw` explicitly if you need it |
| `newCore()` | `newCore()` | Returns a value type over a shared handle, not a `ref`; `close()` is available and idempotent |
| `core.getAvailableDevices()` | `core.availableDevices()` | Same result |
| `core.readModel(path, binPath)` | `core.readModel(path, weightsPath)` | Checks the path first, so a typo names your file. On Windows a non-ASCII path takes the wide entry point |
| `core.compileModel(model, device)` | `core.compileModel(model, device, properties)` | Properties are a parameter; no separate profiling entry point |
| `core.importModel(path, device)` | `core.importModel(blob, device)` | Takes bytes, not a path. Reading the file is your visible step |
| `newTensor(type, dims, data)` | `newTensor(type, shape)`, `tensorFrom(type, shape, data)`, `unsafeTensorFromPointer(type, shape, pointer)` | One entry point became three. See below |
| `tensor.getData(T)` | `tensor.toSeq(T)`, `tensor.copyFrom(data)`, `tensor.unsafeDataPointer` | The checked forms are the default; the raw pointer is named `unsafe` |
| `tensor.getShape()` | `tensor.shape()` returning `Shape` | Was `seq[int64]`. `Shape` is validated when built |
| `tensor.setShape(dims)` | `tensor.setShape(shape)` | Any previously obtained data pointer is invalid afterwards; this is now documented |
| `tensor.getSize()` | `tensor.elementCount`, `tensor.byteSize` | The prototype's single "size" merged two different numbers |
| `request.setInputTensor(idx, t)` | `request.setInputTensor(index, value)` and a by-name form | Index is range-checked before conversion |
| `request.getOutputTensor(idx)` | `request.outputTensor(index)` | Same |
| `request.infer()` | `request.infer()` | Same |
| `request.getProfilingInfo()` | `request.profilingInfo()` | Every field is a Nim-owned copy, and the native list is released whenever the call succeeded |
| `=destroy` only | `close()` plus a destructor backstop | Destruction time is no longer the only way a handle is released |

## The three tensor entry points

The prototype had one constructor, `newTensor(typ, dims, data)`, which wrapped a
caller's pointer. It was the only path, so every caller took on a lifetime
obligation whether or not they knew it. The current API splits that by ownership:

| Call | Who owns the memory | When to use it |
|---|---|---|
| `newTensor(type, shape)` | OpenVINO | You are about to fill it, or it is an output |
| `tensorFrom(type, shape, data)` | OpenVINO, contents copied from your data | The default for input. One copy, no lifetime rules |
| `unsafeTensorFromPointer(type, shape, pointer)` | You, entirely | Only after a measurement shows the copy matters |

The `unsafe` name is the point. Its documentation states what you must
guarantee: address stability, alignment, capacity and a lifetime that outlives
the tensor. A `seq` is the classic mistake here, because growing one moves its
storage and the tensor keeps the old address.

## Errors

| Prototype | Now |
|---|---|
| `requireStatus(status, "Create OpenVINO core")` internally, raising one error type | `OpenVinoError`, `OpenVinoLibraryError`, `OpenVinoVersionError`, `OpenVinoArgumentError` |
| A missing library ended the process during module initialisation | `OpenVinoLibraryError` you can catch, naming every library name tried |
| Argument mistakes reached the C API | Refused before the call, in Nim |

`OpenVinoError` carries the operation name, the numeric status, the stable status
description and the native detail captured at the moment of failure. Catch
`OpenVinoLibraryError` first if you want to tell "OpenVINO is not installed"
apart from "OpenVINO said no".

## Defects the rewrite fixed

These are why the binding layer was rewritten rather than ported. Each was
verified against the installed 2026.4 headers, and each is now covered by
`nimble testAbi`.

| Defect in the prototype | Consequence |
|---|---|
| Element type enum shifted from `U2` onward; `U8` bound as 13 instead of 16 | Every `u8` tensor was interpreted as `U3` |
| `ov_tensor_set_shape` declared as taking `ptr ov_shape_t` | The header passes `ov_shape_t` **by value**; the call read the wrong memory |
| Status code `-10` named incorrectly | A real failure reported the wrong cause |
| `ov_tensor_create` not bound at all | No OpenVINO-allocated tensor was available, forcing every caller onto the external-pointer path |
| Last-error message never released | A leak on every failure |
| Profiling list released only when `size > 0` | A leak on the zero-node case the CPU plugin can return |
| `PERF_COUNT` written as a string literal | Silently stops matching after an upstream rename; the key now comes from the runtime's own exported symbol |
| A Windows-only C shim with `__attribute__((ms_abi))` for variadic properties | Could not build on Linux. Replaced by 2026.4's non-variadic property entry points, which is why that version is the floor |

Full detail, with header checksums: `docs/resonance-audit.md`.

## Porting checklist

1. Change `import resonance` to `import openvino`. Add `import openvino/raw` only
   if you called `ov_*` functions directly.
2. Replace `compileOrImportModel` with explicit `compileModel` or `importModel`,
   and move the cache decision into your own code.
3. Replace `compileModelWithProfiling` with
   `compileModel(..., @[enableProfiling()])`.
4. Replace `newTensor(type, dims, data)` with `tensorFrom` unless you have
   measured that the copy matters.
5. Replace `getData` with `toSeq`, `copyFrom`, or `unsafeDataPointer` if you
   really need the pointer.
6. Add `close()` calls, or `defer: x.close()`, where the prototype relied on
   destruction.
7. Re-check element types. If your code moved `u8` data, the prototype was
   mislabelling it and the corrected binding may change what you see.
