# Compatibility

What has actually been run, and what has not. A combination appears in the
verified table only if a test was executed on it and passed.

## Verified

| Component | Version | How it was verified |
|---|---|---|
| Nim | 2.2.12 | Every task in the list below, on this machine |
| OpenVINO Runtime | 2026.4.0 | `nimble testSmoke` resolves 55 required symbols; `nimble testIntegration` runs real inference |
| Operating system | Windows 11 x86_64 | Same |
| C compiler | The one Nim 2.2.12 uses by default on this host | `nimble testAbi` compiles a C probe against the OpenVINO headers |
| Device | CPU | `nimble testIntegration`: ReLU output matches a hand-computed value |
| Memory managers | ORC, ARC | `nimble testLifecycle` runs the lifetime suites under both |
| Build modes | debug, release | `nimble testIntegration` runs both |

The OpenVINO installation used was `C:\Program Files (x86)\Intel\openvino_2026`,
which is a symlink to `openvino_2026.4.0`, with active code page 936 on the host.

## Not verified

These are not claimed. Some are expected to work and simply have not been run;
others are known to be missing.

| Combination | Status |
|---|---|
| Linux x86_64 | Builds in CI. Not yet counted as verified, because the first CI run that exercises the ABI and smoke jobs has not been reviewed |
| macOS | Never run. No claim either way |
| GPU | The plugin is discovered on this host and reports a full device name. No inference has been run on it |
| NPU | Discovered on this host. No inference has been run on it |
| `--mm:refc` | Never run. The handle model is written for ORC and ARC; refc is not claimed |
| Nim 2.0.x | The manifest requires `>= 2.0.0` and nothing older than 2.2.12 has been tested. The minimum is a floor, not a verified version |
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
