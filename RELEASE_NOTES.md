# OpenVINO Nim API 0.2.1

This patch release fixes correctness and memory safety issues in the
community-maintained Nim bindings for the OpenVINO Runtime C API.

## Fixes

- Reject tensor byte copies of Nim types containing managed references.
- Validate every shape dimension even when a zero dimension is present.
- Reject embedded NUL characters in C-bound names, properties, devices and
  file paths rather than silently truncating them.
- Avoid overflowing a completion queue's deadline for very long timeouts.

## Compatibility

The package targets OpenVINO `2026.4.1` and requires Nim `2.0.0` or newer.
The changes reject inputs that could previously cause incorrect behaviour.
The 0.2.1 changes have not been tested on GPU or NPU hardware.
See [the compatibility matrix](docs/compatibility.md) for previous releases.

For the complete change list, see [CHANGELOG.md](CHANGELOG.md).
