# Troubleshooting

Ordered by how early the failure happens. Work down the list: each step rules
out everything above it.

## The library will not load

Symptom: `OpenVinoLibraryError` before anything else happens.

The message already names every library name that was tried and distinguishes
two cases. Read which one you have.

| Message says | Meaning | Fix |
|---|---|---|
| no such file | The loader never found a candidate | Put the runtime's library directory on the search path |
| the file exists but failed to load | A candidate was found and the OS refused it | A dependency of the library is missing, or the architecture does not match |

**The dependency that catches almost everyone is oneTBB.** `openvino_c.dll`
depends on it, and it lives in a different directory from the runtime libraries.
On Windows both of these must be on `PATH`:

```text
<openvino>\runtime\bin\intel64\Release
<openvino>\runtime\3rdparty\tbb\bin
```

With only the first, `LoadLibrary` fails even when given the full path to
`openvino_c.dll`, and the error looks exactly like a missing file. The official
`setupvars.bat` sets both; copying one DLL out of an installation sets neither.

On Linux the equivalent is `LD_LIBRARY_PATH` covering `runtime/lib/intel64` and
the oneTBB directory, or an `ldconfig` entry. `ldd libopenvino_c.so` names what
is missing.

**A pip installation has no file called `libopenvino_c.so`.** The wheel ships
`libopenvino_c.so.2640`, with that as its SONAME, and no unversioned symlink,
because a wheel has no reason to carry a link that only a linker would use. This
package tries both names, so a pip install works, but the directory still has to
be on the loader path:

```shell
export LD_LIBRARY_PATH="$(python -c 'import openvino,os;print(os.path.join(os.path.dirname(openvino.__file__),"libs"))')${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

oneTBB ships in that same directory in the wheel layout, so one path covers
both. If the failure message lists two names tried and neither was found, the
directory is what is missing, not the library.

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

If `CPU` is missing specifically, the installation is not a runtime installation.
CPU is always present in a complete one.

## A symbol cannot be resolved

Symptom: `OpenVinoLibraryError` naming one symbol.

The installed runtime is older than `2026.4`. The non-variadic property entry
points this package requires do not exist in earlier versions. See
`docs/compatibility.md` for why there is no fallback.

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
   `f32` tensor to an `f16` input is not refused by the shapes.
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

## A crash rather than an exception

The managed layer raises before calling into C for a closed object, a negative
index or an invalid shape, so a hard crash points at one of these:

- An `unsafe` entry point whose contract was not met. That is what the name is
  for; the documented conditions are address stability, alignment, capacity and
  lifetime.
- Direct use of `openvino/raw`, where releasing is yours to do. `docs/ownership.md`
  lists what each call returns and who releases it.
- One `InferRequest` used from several threads. Not supported and not tested.

## Profiling shows nodes that are not in the model

Expected. The names are the plugin's, after fusion and other graph
transformations, so they need not match the IR. A fused node may account for
several IR nodes.

Also measured: the CPU plugin returns a node list even when profiling was never
requested. The presence of entries does not prove profiling is on; timings above
zero do. On this fixture the two runs differ like this:

| Run | Entries | Executed | Total real time |
|---|---|---|---|
| No `enableProfiling()` | 3 | 0 | 0 us |
| With `enableProfiling()` | 3 | 1 | 2 us |

`examples/profiling.nim` prints both runs side by side, so the comparison is
reproducible rather than quoted.

## A task fails on a clean checkout

| Task | Needs |
|---|---|
| `check`, `formatCheck`, `lint`, `test`, `releaseCheck`, `checkFixtures` | Nim only |
| `testAbi` | The OpenVINO **headers**: `OPENVINO_INCLUDE_DIR` or `INTEL_OPENVINO_DIR` |
| `testSmoke`, `testLifecycle`, `testIntegration`, `examples`, `docs` | A loadable runtime, oneTBB included |

`testAbi` passes the include directory through `CPATH` and `INCLUDE` rather than
`--passC`. Nim forwards `--passC` verbatim, so a real Windows path such as
`C:/Program Files (x86)/Intel/...` is split on its spaces and the compiler
reports `Files: No such file or directory`.

## Reporting a problem

Include: the output of `examples/list_devices.nim`, your OpenVINO version and
installation path, your Nim version, the exact exception message, and which of
the tasks above pass. The first of those answers most questions on its own.
