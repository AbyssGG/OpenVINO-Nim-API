# OpenVINO Nim API 0.2.1 (in development)

This patch release is being prepared. It fixes correctness and memory safety
issues in the community-maintained Nim bindings for the OpenVINO Runtime C API.
It has not been published.

## Fixes

- Reject tensor byte copies of Nim types containing managed references.
- Validate every shape dimension even when a zero dimension is present.
- Reject embedded NUL characters in C-bound names, properties, devices and
  file paths rather than silently truncating them.
- Avoid overflowing a completion queue's deadline for very long timeouts.

## Compatibility

The package targets OpenVINO `2026.4.1` and requires Nim `2.0.0` or newer.
The changes reject inputs that could previously cause incorrect behaviour.
The release's full platform and hardware validation has not yet been completed.
See [the compatibility matrix](docs/compatibility.md) for previous releases.

For the complete change list, see [CHANGELOG.md](CHANGELOG.md).
