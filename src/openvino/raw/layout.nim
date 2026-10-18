# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: layouts.
##
## Source of truth: `ov_layout.h` from OpenVINO `2026.4.0`, SHA-256
## `812efb23a0aa81aebdbde7ade704fc8476861a7a0e2fb2efb015744b7af88282`.
##
## The preprocessing functions that accept a layout copy it, so an
## `ov_layout_t` may be released immediately after the call that uses it.

import common
import loader

{.push styleChecks: off.}

type ov_layout_t* = object
  ## Opaque layout handle. Released with `ov_layout_free`.
  ##
  ## Declared incomplete on purpose: the layout is private to OpenVINO.

proc ov_layout_create*(layout_desc: cstring;
                       layout: ptr ptr ov_layout_t): ov_status_e
  {.openvinoImport.}
  ## Parses `layout_desc`, for example `"NCHW"`, `"NC?"` or `"[N,C,H,W]"`.
  ##
  ## The handle is owned by the caller. Measured in Phase 0: lower case is
  ## accepted and upper-cased, the empty string is accepted as `[...]`, and a
  ## repeated name fails with `GENERAL_ERROR`.

proc ov_layout_free*(layout: ptr ov_layout_t) {.openvinoImport.}
  ## Releases a layout.

proc ov_layout_to_string*(layout: ptr ov_layout_t): cstring {.openvinoImport.}
  ## Formats the layout in bracket form, for example `[N,C,H,W]`.
  ##
  ## Returns an allocated string that the caller must copy and release with
  ## `ov_free`. A `nil` layout yields an allocated error text, not `nil`.

{.pop.}
