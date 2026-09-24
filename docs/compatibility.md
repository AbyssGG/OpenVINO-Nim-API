# Compatibility

What has actually been run, and what has not. A combination appears in the
verified table only if a test was executed on it and passed.

## Verified

Two hosts, both running every task in the list at the end of this document.

| Component | Windows host | Linux host |
|---|---|---|
| Operating system | Windows 11 x86_64 | Ubuntu 26.04.1 LTS x86_64, kernel 7.0.0-34 |
| Nim | 2.2.12 | 2.2.4 |
| OpenVINO Runtime | 2026.4.0, archive install | 2026.4.0, pip install |
| OpenVINO build string | `2026.4.0-22959-99c81491cc3-releases/2026/4` | identical |
| C compiler | the one Nim 2.2.12 selects by default | gcc 15 |
| Device | CPU | CPU |
| Memory managers | ORC, ARC | ORC, ARC |
| Build modes | debug, release | debug, release |

What each check produced, the same on both hosts unless stated:

| Check | Result |
|---|---|
| `nimble testAbi` | 21 tests, driven from a C probe compiled against the installed headers |
| `nimble testSmoke` | 9 tests; 55 required symbols resolve against the real runtime |
| `nimble testLifecycle` | the lifetime and error-path suites under ORC and then ARC |
| `nimble testIntegration` | 50 tests in debug and 50 in release; ReLU on CPU gives `@[0.0, 2.0, 0.0, 4.0]`, matching a hand-computed value |
| `nimble examples` | all five examples compile and run |

Both hosts have the same upstream OpenVINO build, so the ABI comparison is one
ABI checked against two compilers and two C libraries rather than two versions
that happen to agree. The two Nim versions differ, which is deliberate: 2.2.4
and 2.2.12 are both exercised.

Host details worth recording because they affected a result. The Windows
installation is `C:\Program Files (x86)\Intel\openvino_2026`, a symlink to
`openvino_2026.4.0`, on a host whose active code page is 936. The Linux
installation is a pip wheel under
`<venv>/lib/python3.14/site-packages/openvino`, which ships only
`libopenvino_c.so.2640` and no unversioned symlink; that is what the second
Linux candidate library name exists for.

## Not verified

These are not claimed. Some are expected to work and simply have not been run;
others are known to be missing.

| Combination | Status |
|---|---|
| macOS | Never run. No claim either way |
| Linux memory checking | Partly done, and the gap is a tooling limit rather than a finding. AddressSanitizer with leak detection reports nothing on `tests/unit/thandle_lifetime.nim`, which touches only this package's own code. It cannot run over the OpenVINO call path at all: ASan aborts inside its own `__cxa_throw` interceptor, because the C++ ABI arrives with the `dlopen`ed runtime after ASan has set up its interceptors, and OpenVINO throws internally while probing plugins. `LD_PRELOAD`ing libasan gets six tests further and then hits the same assertion. valgrind, which the plan names, is not installed on the Linux host |
| GPU | The plugin is discovered on this host and reports a full device name. No inference has been run on it |
| NPU | Discovered on this host. No inference has been run on it |
| `--mm:refc` | Never run. The handle model is written for ORC and ARC; refc is not claimed |
| Nim 2.0.x and 2.1.x | The manifest requires `>= 2.0.0`; the oldest version actually run is 2.2.4. The minimum is a floor, not a verified version |
| OpenVINO 2026.5 and later | Not released at the time of writing |
| OpenVINO 2026.3 and earlier | Refused by design, see below |
| 32-bit targets | Never run |
| Multiple threads sharing one `InferRequest` | Not tested and not supported |

## Why 2026.4 is the floor

The package uses the non-variadic property entry points:
`ov_core_compile_model_props`, `ov_core_compile_model_from_file_props`,
`ov_core_set_properties`, `ov_compiled_model_set_properties`. The variadic forms
that older runtimes offer cannot be called safely from Nim, because a C variadic
call has no portable ABI for a caller that is not C.

`ov_core_compile_model_from_file_unicode_props` is in the same family and is
`2026.4` or newer as well.

The package does not fall back. `requireSupportedRuntime()` exists for callers
who would rather fail at startup with a clear message; it is not called
automatically, because a mismatched runtime often works and refusing to start
would be worse than letting the caller decide.

## What a version mismatch looks like

| Situation | What you see |
|---|---|
| No OpenVINO on the loader path | `OpenVinoLibraryError`, naming every library name tried and how to fix the search path |
| Library present, oneTBB missing | `OpenVinoLibraryError` distinguishing "no such file" from "the file exists but failed to load" |
| Library loads, plugins missing | `newCore()` raises `OpenVinoError`; the library alone is not enough |
| Older runtime, missing symbol | `OpenVinoLibraryError` naming the symbol that could not be resolved |
| Newer runtime, unknown element type | `OpenVinoArgumentError` saying the installed runtime is probably newer than the pinned version |

The last one is a deliberate choice. `ElementType` is a real Nim enum in the
managed layer, so an unknown value from a newer runtime is rejected at the
boundary rather than stored as an illegal enumerator that would later break `$`
and `case`.

## How to re-derive this table

```shell
nimble check
nimble formatCheck
nimble lint
nimble test
nimble releaseCheck
nimble testAbi
nimble testSmoke
nimble testLifecycle
nimble testIntegration
nimble examples
```

`testAbi` needs `OPENVINO_INCLUDE_DIR` or `INTEL_OPENVINO_DIR`. The tasks that
load the runtime need the C API library **and** oneTBB on the loader path; on
Windows that is `runtime/bin/intel64/Release` and `runtime/3rdparty/tbb/bin`.
Missing oneTBB is the failure that looks like a missing `openvino_c.dll`.
