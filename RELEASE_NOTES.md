# OpenVINO Nim API 0.1.1

OpenVINO Nim API 0.1.1 is a minor update to the community-maintained Nim
bindings for the OpenVINO Runtime C API, adding verified OpenVINO `2026.4.1`
support and a full GPU and NPU hardware compatibility suite. It is not an
official Intel or OpenVINO project.

Published as [`v0.1.1`](https://github.com/AbyssGG/OpenVINO-Nim-API/releases/tag/v0.1.1)
on 2026-10-18.

## Highlights

- Retargeted and verified against OpenVINO `2026.4.1` (build `22982`, commit
  `e213a14`) while retaining full compatibility with `2026.4.0` (all 18 C
  headers are byte-identical across both releases, and the Linux loader tries
  both `libopenvino_c.so.2641` and `libopenvino_c.so.2640` after
  `libopenvino_c.so`).
- Verified GPU and NPU hardware compatibility on Windows 11 x86_64 across
  `GPU` / `GPU.0` (`Intel(R) Graphics (iGPU)`), `GPU.1` (`NVIDIA GeForce RTX
  5080 (dGPU)` via OpenCL) and `NPU` (`Intel(R) AI Boost`), alongside `CPU`
  (`Intel(R) Core(TM) Ultra 7 270K Plus`), via the new
  `tests/hardware/thardware_inference.nim` suite and `nimble testHardware`
  task under both `--mm:orc` and `--mm:arc` (debug and release).
- Documented measured plugin differences when calling `profilingInfo()` on a
  model compiled without `enableProfiling()` (`CPU` returns zero-time entries,
  `NPU` returns `@[]`, and `GPU` raises `OpenVinoError`, whereas all three
  return timed execution entries when compiled with `[enableProfiling()]`).

## Compatibility

This release targets OpenVINO `2026.4.1` (and supports `2026.4.0`) and requires
Nim `2.0.0` or newer. CI exercises Windows x86_64 and Linux x86_64 on CPU, and
the Windows 11 x86_64 host is verified across CPU, Intel iGPU (`GPU.0`), NVIDIA
dGPU (`GPU.1`) and Intel NPU (`NPU`). macOS support is not claimed. See
[the compatibility matrix](docs/compatibility.md) for the exact combinations
that were tested.

## Installation

Install OpenVINO Runtime `2026.4.x` separately and configure its library search
path, then install the Nim package:

```shell
nimble install openvino
```

Until the package is present in the Nimble package index, install from a local
checkout with `nimble install`.

## Release assets

The published `v0.1.1` assets are:

- `openvino-nim-0-1-1-2026-10-18-ov2026-4-1.zip`
- `openvino-nim-0-1-1-2026-10-18-ov2026-4-1.tar.gz`
- `openvino-nim-0-1-1-2026-10-18-ov2026-4-1.zip.sha256`
- `openvino-nim-0-1-1-2026-10-18-ov2026-4-1.tar.gz.sha256`

The release workflow uploads exactly these four canonical assets, all sharing
one generated base name:

| Asset | Purpose |
|---|---|
| `openvino-nim-{version}-{date}-ov{openvino-version}.zip` | Reproducible ZIP source archive |
| `openvino-nim-{version}-{date}-ov{openvino-version}.tar.gz` | Reproducible tarball source archive |
| `openvino-nim-{version}-{date}-ov{openvino-version}.zip.sha256` | SHA-256 sidecar for the ZIP |
| `openvino-nim-{version}-{date}-ov{openvino-version}.tar.gz.sha256` | SHA-256 sidecar for the tarball |

Each archive has exactly one top-level directory whose name is the generated
base name. It contains no OpenVINO runtime, SDK, model weights or credentials.
GitHub's automatically generated “Source code” archives are convenient mirrors
but are not the project's reproducible, checksummed release artifacts.

Verify a downloaded archive with the sidecar from the same Release:

```shell
sha256sum -c openvino-nim-0-1-1-2026-10-18-ov2026-4-1.zip.sha256
sha256sum -c openvino-nim-0-1-1-2026-10-18-ov2026-4-1.tar.gz.sha256
```

For the complete change list, see [CHANGELOG.md](CHANGELOG.md). For deployment
and loader problems, see [the troubleshooting guide](docs/troubleshooting.md).
