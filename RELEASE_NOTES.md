# OpenVINO Nim API 0.2.0

OpenVINO Nim API 0.2.0 adds asynchronous inference, dynamic shapes and
declarative preprocessing to the community-maintained Nim bindings for the
OpenVINO Runtime C API. It is not an official Intel or OpenVINO project.

Published as [`v0.2.0`](https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.2.0)
on 2026-10-18.

## Highlights

- **Asynchronous inference.** `startAsync`, `wait`, `waitFor` and `cancel` on
  `InferRequest`, with `OpenVinoBusyError` and `OpenVinoCancelledError`.
  `CompletionQueue` tells one Nim thread which of many requests has finished.
  No Nim code runs on OpenVINO's threads: the package installs one internal C
  callback that only records the completion, so user callbacks are
  deliberately not offered. Closing a running request is safe.
- **Dynamic shapes.** `PartialShape` and `Dimension` describe dynamic, bounded
  and lower-bounded dimensions; `Port.partialShape` reads them; `Model.reshape`
  changes them by input, index, name or several names atomically. One compiled
  dynamic model infers different batch sizes.
- **Layout and preprocessing.** A `PreprocessPlan` describes element type,
  layout, color format, spatial size, resize, mean, scale, crop, pad and
  channel reversal as a plain Nim value, and `applyPreprocessing` builds the
  prepared model in one call that never lets an OpenVINO child object escape.
- **Measured, not assumed.** Ten upstream behaviours were measured before the
  design was fixed, and two corrected the plan. All are pinned by smoke tests
  and recorded in ADRs 0003 to 0005.

## Compatibility

Targets OpenVINO `2026.4.1` (and supports `2026.4.0`) and requires Nim `2.0.0`
or newer; `0.1.x` code compiles and behaves as before. Verified on Windows 11
x86_64 (CPU, Intel iGPU, NVIDIA dGPU, Intel NPU) and Ubuntu 26.04 x86_64 (CPU,
valgrind). The Intel NPU plugin needs bounded or static shapes and does not
support `cancel`. See [the compatibility matrix](docs/compatibility.md).

## Installation

Install OpenVINO Runtime `2026.4.x` separately and configure its library search
path, then install the Nim package:

```shell
nimble refresh
nimble install openvino
```

## Release assets

The published `v0.2.0` assets are the four canonical, checksummed files the
release workflow builds from the tagged commit:

- `openvino-nim-0-2-0-2026-10-18-ov2026-4-1.zip`
- `openvino-nim-0-2-0-2026-10-18-ov2026-4-1.tar.gz`
- `openvino-nim-0-2-0-2026-10-18-ov2026-4-1.zip.sha256`
- `openvino-nim-0-2-0-2026-10-18-ov2026-4-1.tar.gz.sha256`

Each archive has one top-level directory named after the base name and contains
no OpenVINO runtime, model weights or credentials. Verify a download with the
sidecar from the same Release:

```shell
sha256sum -c openvino-nim-0-2-0-2026-10-18-ov2026-4-1.zip.sha256
sha256sum -c openvino-nim-0-2-0-2026-10-18-ov2026-4-1.tar.gz.sha256
```

For the complete change list, see [CHANGELOG.md](CHANGELOG.md). For problems,
see [the troubleshooting guide](docs/troubleshooting.md).
