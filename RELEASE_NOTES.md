# OpenVINO-Nim-API 0.1.0

OpenVINO-Nim-API 0.1.0 is the first release of the community-maintained Nim
bindings for the OpenVINO Runtime C API. It is not an official Intel or
OpenVINO project.

## Highlights

- A managed, idiomatic Nim API for synchronous inference with `Core`, `Model`,
  `CompiledModel`, `InferRequest`, `Tensor`, ports and properties.
- A separate header-faithful raw C ABI layer available through
  `import openvino/raw`; the default `import openvino` does not expose it.
- Explicit ownership and idempotent `close()` operations, with ORC and ARC
  lifetime coverage and a destructor backstop.
- Safe copied tensors by default, plus an explicitly named unsafe external
  buffer path for callers that need zero-copy access.
- Model compilation, compiled-model export/import, profiling, device
  discovery and non-ASCII Windows paths.

## Compatibility

This release targets OpenVINO `2026.4.0` and requires Nim `2.0.0` or newer.
The release gate exercises Windows x86_64 and Linux x86_64 with CPU inference.
GPU, NPU and macOS support are not claimed. See
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
sha256sum -c openvino-nim-0-1-0-YYYY-M-D-ov2026-4-0.zip.sha256
sha256sum -c openvino-nim-0-1-0-YYYY-M-D-ov2026-4-0.tar.gz.sha256
```

For the complete change list, see [CHANGELOG.md](CHANGELOG.md). For deployment
and loader problems, see [the troubleshooting guide](docs/troubleshooting.md).
