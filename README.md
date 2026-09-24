# OpenVINO-Nim-API

[![CI](https://github.com/AbyssGG/OpenVINO-Nim-API/actions/workflows/ci.yml/badge.svg)](https://github.com/AbyssGG/OpenVINO-Nim-API/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Nim](https://img.shields.io/badge/Nim-%E2%89%A52.0.0-yellow.svg)](https://nim-lang.org/)
[![OpenVINO](https://img.shields.io/badge/OpenVINO-2026.4.x-6b4fbb.svg)](https://docs.openvino.ai/)
[![Status](https://img.shields.io/badge/status-pre--release-orange.svg)](CHANGELOG.md)

**English** | [简体中文](README_zh-CN.md)

Nim bindings for the [OpenVINO](https://docs.openvino.ai/) Runtime C API.

OpenVINO-Nim-API provides two layers. The managed API is idiomatic Nim with
private native handles, Nim exceptions and documented ownership rules. The
raw layer is a header-faithful binding to the OpenVINO C ABI for callers who
need it.

**This is a community-maintained project. It is not an official Intel or
OpenVINO project, and it is not endorsed by or affiliated with Intel
Corporation.** OpenVINO is a trademark of Intel Corporation.

## Status

Version `0.1.0` is under active development and is not released yet. The
work is tracked phase by phase in
[OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md).

Synchronous inference works. `Core`, `Model`, `CompiledModel`,
`InferRequest`, `Tensor`, properties, profiling and explicit blob
export/import are implemented and covered by tests that run real inference on
CPU, including a thousand-iteration lifetime loop.

Verified on two hosts: Windows 11 x86_64 with Nim 2.2.12, and Ubuntu 26.04
x86_64 with Nim 2.2.4, both against OpenVINO `2026.4.0` on CPU. On each host
the ABI, smoke, lifetime, integration and example suites all pass. No claim is
made for GPU, NPU or macOS. See [compatibility](docs/compatibility.md) for what
was and was not run. Nothing in this README should be read as a claim that a
feature already works unless it says so.

## Feature overview

| Capability | 0.1.0 status | Notes |
|---|---|---|
| Managed Nim API | Available | `Core`, `Model`, `CompiledModel`, `InferRequest`, `Tensor`, shapes and properties |
| Raw C ABI layer | Available | Import it explicitly with `openvino/raw`; pinned to OpenVINO 2026.4 headers |
| Synchronous CPU inference | Available | Windows and Linux x86_64 are verified in CI and on clean hosts |
| Runtime discovery and diagnostics | Available | Version, device listing, symbol checks and actionable loader errors |
| Profiling and explicit blob I/O | Available | No implicit cache directory or device policy is added |
| Async inference and callbacks | Roadmap | Needs a Nim-safe callback and thread-lifetime design |
| Dynamic shapes and preprocessing | Roadmap | The corresponding C headers are intentionally not in the 0.1.0 surface |
| GPU/NPU inference | Not claimed | Device discovery is not evidence of a verified inference path |

The roadmap is deliberately explicit about what is not implemented. See
[the API overview](docs/api-overview.md) and [the roadmap](docs/roadmap.md)
before designing an application around a future feature.

## Quick start

1. Install OpenVINO Runtime `2026.4.x` and run its official environment setup
   script for the current shell.
2. Clone this repository and install the local Nim package:

   ```shell
   git clone https://github.com/AbyssGG/OpenVINO-Nim-API.git
   cd OpenVINO-Nim-API
   nimble install
   ```

3. Run the verified examples against the included four-value ReLU fixture:

   ```shell
   nimble examples
   ```

The [getting started guide](docs/getting-started.md) has platform-specific
loader checks and troubleshooting. The complete inference snippet is kept
below and is compiled from the same source as `examples/minimal.nim`.

## Six naming roles

These names are deliberately different. Mixing them up is the most common
source of confusion when installing the package.

| Name | Where it is used | Why |
|---|---|---|
| `OpenVINO-Nim-API` | Project title, prose, repository description | The display name. Mixed case, for reading |
| `OpenVINO-Nim-API` | GitHub repository name | The exact public repository name requested by the project owner |
| `openvino-nim` | Release archive prefix and distribution references | Lowercase because file systems and package indexes disagree about case |
| `openvino` | Nimble package identifier | Nimble package identifiers may not contain a hyphen |
| `openvino.nimble` | Manifest file name | Nimble requires the manifest name to match the package identifier |
| `import openvino` | Nim source code | The stable import root, kept identical to the package identifier |

The project title and GitHub repository deliberately match exactly. Package
and archive tooling still use their lowercase identifiers: `openvino-nim` for
release assets and `openvino` for Nimble and imports. A Git tag remains a
SemVer tag such as `v0.1.0`; it is not derived from any of these names.

`nimble releaseCheck` asserts that this README mentions the repository,
display and distribution names, that the first two match, and that the
distribution name stays lowercase, so none can quietly drift from
`src/openvino/version.nim`.

Release archives use the base name
`openvino-nim-{version}-{date}-ov{openvino-version}` with dots replaced by
hyphens. For version `0.1.0` released against OpenVINO `2026.4.0`, the
archive base name is generated by the release tooling rather than written by
hand, so that the Git tag, release title, archive name and checksums cannot
drift apart.

## Requirements

| Component | Requirement |
|---|---|
| Nim | 2.0.0 or newer; CI pins the exact versions that are verified |
| OpenVINO Runtime | `2026.4.x`, verified against `2026.4.0` |
| Tier 1 platforms | Windows x86_64, Linux x86_64 |
| Baseline device | CPU |

The `2026.4` requirement is not arbitrary. This package uses the
non-variadic properties API (`ov_property_t`, `ov_core_compile_model_props`,
`ov_compiled_model_set_properties` and friends) that avoids passing property
pairs through C varargs. The package does not silently fall back to older
runtimes.

GPU and NPU devices are discovered dynamically when the corresponding
OpenVINO plugins are installed. They are not build or release prerequisites,
and support for them is not claimed beyond what CI verifies.

## Installing the OpenVINO runtime

The package binds to the OpenVINO runtime at run time and never ships it.
Install OpenVINO `2026.4.x` separately, then make sure the C API library is
visible to the dynamic loader:

| Platform | Library | Loader notes |
|---|---|---|
| Windows | `openvino_c.dll` | Must be on the DLL search path |
| Linux | `libopenvino_c.so`, or `libopenvino_c.so.2640` | Must be on the loader search path. A pip installation ships only the versioned name; both are tried |

Loading `openvino_c` alone is not enough to run inference. `Core` also needs
`plugins.xml`, the device plugins and the model frontends from the same
official runtime layout. Copying a single library out of an OpenVINO
installation will fail at model load time, not at library load time.

The official setup scripts (`setupvars.bat` on Windows, `setupvars.sh` on
Linux) configure the environment for the current shell. This package never
modifies environment variables or the process search path on your behalf.

## Installing the package

```shell
nimble install openvino
```

The Nimble package index entry may not exist yet while `0.1.0` is
unreleased. Until then, install from a local checkout:

```shell
nimble install
```

## Minimal synchronous inference

```nim
import openvino

const modelPath = "tests/fixtures/relu_1x4_f32.xml"

proc main() =
  let core = newCore()
  defer: core.close()

  let compiled = core.compileModel(modelPath, "CPU")
  defer: compiled.close()

  let request = compiled.createInferRequest()
  defer: request.close()

  let input = tensorFrom(etF32, initShape(1, 4),
                         [float32(-1.5), 2.0, -0.25, 4.0])
  defer: input.close()

  request.setInputTensor(0, input)
  request.infer()

  let output = request.outputTensor(0)
  defer: output.close()
  echo output.toSeq(float32)

main()
```

Prints `@[0.0, 2.0, 0.0, 4.0]`: the model is a ReLU, so the two negative
inputs become zero and the two positive ones pass through.

This is not a transcription. The same code is `examples/minimal.nim`, which
`nimble examples` compiles and runs, and `nimble lint` fails if the two drift
apart. Note what is absent: no device is chosen for you, no cache directory
appears, and every object is closed where it was created.

More examples, all using the public API only:

| Example | What it shows |
|---|---|
| `examples/list_devices.nim` | Runtime version and device discovery, useful first when a deployment misbehaves |
| `examples/minimal.nim` | The block above |
| `examples/sync_infer.nim` | The same loop with the model path and device taken from the command line, plus model metadata |
| `examples/tensor_basics.nim` | Shapes, element types, and the difference between the safe data paths and the unsafe one |
| `examples/profiling.nim` | Per-node timings, and what the numbers do and do not mean |

## Error diagnosis

Failures surface as distinguishable Nim exceptions rather than status codes:

| Exception | Meaning |
|---|---|
| `OpenVinoError` | An OpenVINO C call returned a non-OK status |
| `OpenVinoLibraryError` | The dynamic library or a required symbol is missing |
| `OpenVinoVersionError` | The detected runtime major/minor is unsupported |

`OpenVinoError` carries the operation name, the numeric status, the stable
status description and the native detail captured at the moment of failure.
Argument errors such as a negative index, an invalid shape or a call on a
closed object are raised before entering the C layer.

## Lifetime and zero-copy rules

Two rules cover most of what you need to know:

1. Every managed type owns exactly one native handle and offers an
   idempotent `close()`. Calling `close()` twice is harmless. Using an
   object after `close()` raises a Nim error instead of crashing in native
   code. Destructors are a backstop, not a replacement for `close()`.
2. Tensors allocated by OpenVINO or copied from Nim data are the safe
   default. Any entry point that borrows caller memory without owning it is
   named with `unsafe` and documents exactly what the caller must guarantee
   about address stability, alignment, capacity and lifetime.

## Documentation

The [documentation hub](docs/README.md) groups the English guides and the
generated API reference.

Start with whichever question you have:

| Question | Document |
|---|---|
| How is this put together, and why? | [Architecture](docs/architecture.md) |
| What has actually been tested? | [Compatibility](docs/compatibility.md) |
| Something does not work | [Troubleshooting](docs/troubleshooting.md) |
| Who releases what? | [Ownership rules](docs/ownership.md) |
| Which C entry points are bound? | [C API coverage](docs/c-api-coverage.md) |
| What is the public API shape? | [API overview](docs/api-overview.md) |
| How do I install and verify it? | [Getting started](docs/getting-started.md) |
| What is planned after 0.1.0? | [Roadmap](docs/roadmap.md) |
| I have Resonance code | [Migration guide](docs/resonance-migration.md) |
| Why was it done this way? | [Symbol loading](docs/decisions/0001-symbol-loading.md), [handle model](docs/decisions/0002-handle-model.md) |

Project documents: [notice and provenance](NOTICE),
[development plan](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md),
[development log in English and Chinese](DEVLOG.md),
[style guide](STYLE_GUIDE.md), [contributing](CONTRIBUTING.md),
[changelog](CHANGELOG.md),
[prototype audit](docs/resonance-audit.md).

## Project layout

| Path | Purpose |
|---|---|
| `src/openvino.nim` | Stable managed import root |
| `src/openvino/` | Managed handles, conversions and user-facing errors |
| `src/openvino/raw/` | Explicit, header-faithful C ABI declarations |
| `examples/` | Small runnable programs using only the public API |
| `tests/` | Unit, ABI, lifecycle, integration and packaging checks |
| `docs/` | Architecture, compatibility, API coverage and decisions |
| `.github/workflows/` | Static, runtime, documentation and release checks |

## Community and support

Bug reports should include the OpenVINO runtime version, Nim version, target
device and the smallest reproducible example. Start with
[Troubleshooting](docs/troubleshooting.md), then open a GitHub issue if the
problem is reproducible with the supported matrix. Security reports belong in
[SECURITY.md](SECURITY.md), not in a public issue.

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), keep the
managed/raw boundary intact, and update tests and documentation with any
public API change. The project is community maintained and is not an Intel
product.

## License

Apache-2.0. See [LICENSE](LICENSE), and [NOTICE](NOTICE) for how this package
relates to the OpenVINO C headers, why no upstream text is copied, and what is
and is not bundled.
