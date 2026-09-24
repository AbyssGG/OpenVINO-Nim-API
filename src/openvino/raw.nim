# SPDX-License-Identifier: Apache-2.0

## Explicit entry point for the OpenVINO C ABI layer.
##
## `import openvino/raw` gives access to declarations that mirror the pinned
## OpenVINO `2026.4.0` C headers. Nothing here is safe by construction: the
## types are raw pointers, ownership is the caller's problem, and failures
## arrive as `ov_status_e` values rather than exceptions.
##
## Prefer `import openvino`, which exposes the managed API. Reach for this
## layer only when the managed API cannot express what you need. The `0.x`
## series promises that these declarations match the pinned headers; it does
## **not** promise source stability for them.
##
## The one place this layer raises is symbol resolution, in
## `openvino/raw/loader`. The reason is recorded in
## `docs/decisions/0001-symbol-loading.md`.
##
## Coverage, including what is deliberately not bound, is listed in
## `docs/c-api-coverage.md`.

import raw/common
import raw/compiled_model
import raw/core
import raw/error
import raw/infer_request
import raw/loader
import raw/model
import raw/node
import raw/property
import raw/shape
import raw/tensor

export common
export compiled_model
export core
export error
export infer_request
export loader
export model
export node
export property
export shape
export tensor
