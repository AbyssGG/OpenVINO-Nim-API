# Roadmap

This roadmap separates work that is already usable from work that needs a
design and tests. It is not a promise of a release date.

## Available in 0.1.1

- Windows x86_64 and Linux x86_64 CPU inference with OpenVINO `2026.4.1` and
  `2026.4.0`.
- Verified Windows x86_64 GPU (`GPU`, `GPU.0` Intel iGPU, `GPU.1` NVIDIA dGPU)
  and NPU (`Intel(R) AI Boost`) inference, profiling and blob export/import via
  `nimble testHardware`.
- Managed Core, Model, CompiledModel, InferRequest, Tensor, Shape and Property
  types with explicit ownership and exceptions.
- Raw declarations for the verified synchronous C ABI path.
- Runtime version/device discovery, profiling and explicit compiled-model blob
  export/import.
- ABI probes, smoke tests, lifecycle tests under ORC and ARC, debug/release
  integration and hardware tests, examples and clean-directory packaging
  checks.
- Official GitHub Releases (`v0.1.0`, `v0.1.1`) and Nimble package index entry
  (`openvino`, [nim-lang/packages #3578](https://github.com/nim-lang/packages/pull/3578)).

## Next priorities

| Area | Why it needs design work |
|---|---|
| Asynchronous inference | Callbacks must not let Nim exceptions cross C and must define request/thread lifetime |
| Dynamic and partial shapes | Reshape and `ov_partial_shape_t` add ownership and validation cases |
| Layout and preprocessing | The C pre/post-processing API has a larger surface and variadic entry points |
| Request pools and concurrency | Sharing rules need measured thread tests rather than assumptions |
| Remote contexts | Device-specific memory ownership cannot be represented by a generic pointer |
| GenAI and task-specific helpers | These belong in separate layers, not in the small core binding |

## Non-goals

The core package will not choose a default device, download models, manage an
application cache directory, provide a CLI, or interpret model outputs. Those
features can live in downstream examples or companion packages without making
the base binding opinionated.

## How to propose work

Open an issue with the use case, the relevant OpenVINO C header and a proposed
ownership model. A pull request should include a test, documentation and an
entry in `CHANGELOG.md` when the public surface changes. See
[CONTRIBUTING.md](../CONTRIBUTING.md).
