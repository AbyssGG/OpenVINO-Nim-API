# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: static shapes.
##
## Source of truth: `ov_shape.h` from OpenVINO `2026.4.0`, SHA-256
## `a12a4c241bccbc9cd3cf68f39b13c91701a78cd062a97004ae8f1612b10d4650`.
##
## `ov_shape_t` is a plain struct that the tensor constructors and
## `ov_tensor_set_shape` take **by value**. The Resonance prototype passed a
## pointer instead, which is the third confirmed ABI defect from the audit.

import common
import loader

{.push styleChecks: off.}

type ov_shape_t* = object
  ## A static shape: a rank and a pointer to `rank` dimensions.
  ##
  ## Layout is verified against the header by the ABI test, not assumed.
  ##
  ## When OpenVINO fills this struct it also allocates `dims`, and the caller
  ## must release it with `ov_shape_free`. A struct the caller built itself,
  ## pointing at its own memory, must not be passed to `ov_shape_free`.
  rank*: int64
  dims*: ptr int64

proc ov_shape_create*(rank: int64; dims: ptr int64;
                      shape: ptr ov_shape_t): ov_status_e {.openvinoImport.}
  ## Initialises `shape` with `rank` dimensions copied from `dims`.
  ##
  ## Allocates the dimension storage inside `shape`, so a successful call must
  ## be paired with `ov_shape_free`. `rank` must be greater than zero.

proc ov_shape_free*(shape: ptr ov_shape_t): ov_status_e {.openvinoImport.}
  ## Releases the dimension storage inside `shape`.
  ##
  ## Returns a status, unlike most release functions. Only apply this to a
  ## shape OpenVINO allocated, whether through `ov_shape_create` or by filling
  ## it in a getter such as `ov_tensor_get_shape`.

{.pop.}
