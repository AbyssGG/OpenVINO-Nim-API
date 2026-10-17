# Troubleshooting

Start with the section that matches the failing operation. Check library
loading before device discovery, model reading and inference.

## The library will not load

Symptom: `OpenVinoLibraryError` before anything else happens.

The exception lists the library names tried. Use the reported loader failure
to choose the next check:

| Message says | Meaning | Fix |
|---|---|---|
| no such file | The loader never found a candidate | Put the runtime's library directory on the search path |
| the file exists but failed to load | A candidate was found and the OS refused it | A dependency of the library is missing, or the architecture does not match |

`openvino_c.dll` depends on oneTBB, which can live in a different directory
from the runtime libraries.
On Windows both of these must be on `PATH`:

```text
<openvino>\runtime\bin\intel64\Release
<openvino>\runtime\3rdparty\tbb\bin
```

With only the first, `LoadLibrary` fails even when given the full path to
`openvino_c.dll`, and the error looks exactly like a missing file. The official
`setupvars.bat` sets both. Run it in CMD and run inference in that same
session. A batch file launched from PowerShell does not update the parent
PowerShell environment.

On Linux the equivalent is `LD_LIBRARY_PATH` covering `runtime/lib/intel64` and
the oneTBB directory, or an `ldconfig` entry. `ldd libopenvino_c.so` names what
is missing.

A Linux pip wheel provides only `libopenvino_c.so.2641` (or
`libopenvino_c.so.2640`), without an unversioned `libopenvino_c.so` symlink.
The package tries the unversioned name first and then the verified `2026.4.x`
SONAMEs. Add the wheel's library directory to the loader path, using the
Python environment where OpenVINO is installed:

```shell
OV_LIB_DIR=$(python -c 'import openvino, os; print(os.path.join(os.path.dirname(openvino.__file__), "libs"))')
export LD_LIBRARY_PATH="$OV_LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

Check that oneTBB is also available in that layout. If neither candidate is
found, verify the Python environment and loader path before reinstalling.

Architecture mismatch is the other case: a 32-bit Nim build cannot load a 64-bit
runtime. Nothing in the message will say "architecture", so check it if the path
is definitely right.

## `newCore()` fails although the library loaded

Loading `openvino_c` needs one file. Creating a `Core` additionally needs
`plugins.xml`, the device plugin libraries and the model frontend libraries, all
from the same installation layout.

This is what a partial copy looks like: the library loads, then `Core` fails. Fix
it by using a complete OpenVINO installation rather than selected files from one.

## No devices are found

`examples/list_devices.nim` prints the runtime version and every device. If the
list is empty, the C API library loaded but no plugin did. Same cause as above: a
layout that is missing `plugins.xml` or the plugin libraries.

If `CPU` is missing, check the CPU plugin and its dependencies in the selected
installation. A listed device confirms discovery; it does not verify that a
model can compile and run on that device.

## A symbol cannot be resolved

Symptom: `OpenVinoLibraryError` naming one symbol.

Check whether the loader selected an older or mixed OpenVINO installation.
The non-variadic property entry points this package requires are unavailable
in runtimes before `2026.4`. See [Compatibility](compatibility.md) for the
baseline and fallback policy. `runtimeVersion()` reports the loaded runtime;
`requireSupportedRuntime()` checks its major/minor against the baseline.

`nimble testSmoke` checks all 55 required symbols at once and names the first
that is missing, which is faster than finding out one call at a time.

## The model will not read

| Cause | What you see | Note |
|---|---|---|
| Path typo | `OpenVinoArgumentError` naming the file | Checked before the C call, so the message names your path rather than the runtime's opinion of it |
| Missing `.bin` | `OpenVinoError` from the frontend | An IR pair needs both files next to each other, unless the model has no weights |
| Wrong format | `OpenVinoError` | The frontend for that format may not be installed |
| Non-ASCII path | Works | Non-ASCII paths go through the wide-character entry point on Windows. Measured on a host with code page 936: the narrow entry point also accepted UTF-8 in 2026.4 |

## Inference returns the wrong numbers

Check these in order, because each is cheaper to rule out than the next:

1. **Element type.** `port.elementType()` is what the model declares. Binding an
   `f32` tensor to an `f16` input is not validated by checking shape alone.
   Typed tensor access checks width and size, but does not convert data or
   distinguish integers from floats of the same width.
2. **Shape and layout.** A shape of `[1, 3, 224, 224]` and one of
   `[1, 224, 224, 3]` hold the same number of elements. Nothing will complain;
   the output will simply be wrong.
3. **Input order.** `setInputTensor(0, ...)` binds by position. Use the name form
   when a model has several inputs.
4. **Reused tensor after `setShape`.** Any pointer from `unsafeDataPointer` is
   invalid after a reshape, because the storage may have moved.
5. **An unsafe external buffer.** `unsafeTensorFromPointer` does not own or copy
   anything. If the buffer was a `seq` that grew, or a local that went out of
   scope, the tensor is reading memory that no longer belongs to it.

If `sync_infer.nim` reports unexpected output for your own model, check its
verification code too. The example supplies four `float32` values and expects
ReLU output; adapt both the input preparation and output check to your model.

## A crash rather than an exception

The managed layer rejects closed objects, negative indexes and invalid shapes
before calling into C. For a crash, first check these lifetime conditions:

- An `unsafe` entry point whose contract was not met. That is what the name is
  for; the documented conditions are address stability, alignment, capacity and
  lifetime.
- Direct use of `openvino/raw`, where the caller releases native resources.
  [Ownership rules](ownership.md) lists the release function for each result.
- One `InferRequest` used from several threads. Not supported and not tested.

## Profiling shows nodes that are not in the model

Profiling names come from the plugin after fusion and other graph
transformations, so they need not match the IR. A fused node may account for
several IR nodes.

Also measured across plugins when `enableProfiling()` was **not** set at
compilation time:

- The `CPU` plugin returns a node list with `status = psNotRun` and `0 us`.
- The `NPU` plugin returns an empty list (`@[]`).
- The `GPU` plugin (`GPU`, `GPU.0`, `GPU.1`) raises `OpenVinoError` stating
  that profiling data was not collected because `enable_profiling` was not set.

When compiled with `[enableProfiling()]`, all three plugins return timed
execution entries. On CPU for the ReLU fixture the two runs differ like this:

| Run | Entries | Executed | Total real time |
|---|---|---|---|
| No `enableProfiling()` | 3 | 0 | 0 us |
| With `enableProfiling()` | 3 | 1 | 2 us |

`examples/profiling.nim` prints both runs side by side, so the comparison is
reproducible rather than quoted.

## A task fails on a clean checkout

| Task | Needs |
|---|---|
| `check`, `formatCheck`, `lint`, `test`, `releaseCheck`, `checkFixtures`, `docs` | Nim only |
| `testAbi` | The OpenVINO **headers**: `OPENVINO_INCLUDE_DIR` or `INTEL_OPENVINO_DIR` |
| `testSmoke`, `testLifecycle`, `testIntegration`, `examples`, `packagingCheck` | A loadable runtime, oneTBB included |
| `testHardware` | A loadable runtime plus at least one GPU or NPU device |
| `memcheck` | Linux, and valgrind. It fails rather than skipping on other platforms |
| `releaseArchive` | Python, a clean working tree, and `OPENVINO_NIM_RELEASE_DATE` |

`testAbi` passes the include directory through `CPATH` and `INCLUDE` rather than
`--passC`. Nim forwards `--passC` verbatim, so a real Windows path such as
`C:/Program Files (x86)/Intel/...` is split on its spaces and the compiler
reports `Files: No such file or directory`.

## Reporting a problem

Include: the output of `examples/list_devices.nim`, your OpenVINO version and
installation path, your Nim version, the exact exception message, and which of
the tasks above pass. The first of those answers most questions on its own.
