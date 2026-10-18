# Roadmap

This roadmap separates work that is already usable from work that needs a
design and tests. It is not a promise of a release date.

## Available in 0.2.0

Released on 2026-10-18 as `v0.2.0`.

- Dynamic and partial shapes: `Dimension`, `PartialShape`,
  `Port.partialShape`, and `Model.reshape` by input, index, name or several
  names at once; one compiled dynamic model infers several batch sizes.
- Asynchronous inference: `startAsync`, `wait`, `waitFor`, `cancel`,
  `OpenVinoBusyError`, `OpenVinoCancelledError`, and `CompletionQueue` for
  completion notification without running Nim code on OpenVINO threads.
- Layout and preprocessing: `Layout` and a declarative `PreprocessPlan`
  applied in one call, covering element type, layout, color, resize, mean,
  scale, crop, pad and channel reversal.
- Raw declarations for `ov_dimension.h`, `ov_rank.h`, `ov_partial_shape.h`,
  `ov_layout.h`, the non-variadic `ov_prepostprocess.h`, reshape and the
  asynchronous request functions, all covered by ABI probes and smoke tests.
- Verified on CPU (Windows and Linux) and on Windows GPU (`GPU.0`, `GPU.1`)
  and NPU; the NPU plugin needs bounded or static shapes and cannot cancel.

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
| Request pools and concurrency | Sharing rules need measured thread tests rather than assumptions; a simple pool over `CompletionQueue` is the natural start |
| `asyncdispatch` integration | Needs evidence that waking an event loop from a non-Nim thread is safe on IOCP and epoll |
| Remote contexts | Device-specific memory ownership cannot be represented by a generic pointer |
| Mutable ports | Needed only for `reshape_by_ports` and port-based tensor binding |
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
