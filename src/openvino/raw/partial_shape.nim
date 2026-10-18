# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: partial shapes.
##
## Source of truth: `ov_partial_shape.h` from OpenVINO `2026.4.0`, SHA-256
## `a242870caaef1ec9f6a50d01883fbc6d8721ead2b30e6dd4aa32ce9ce077bf7b`.
##
## Most functions here take `ov_partial_shape_t` **by value**. Several have
## upstream defects measured in Phase 0 of the 0.2 plan and recorded in
## `docs/decisions/0004-partial-shape-representation.md`; each doc comment
## below names the one that applies. The managed layer reads partial shapes
## through `ov_port_get_partial_shape` and writes them by filling the struct
## itself, so it calls none of the constructors or converters in this module
## except `ov_partial_shape_free`.

import common
import dimension
import loader
import shape

{.push styleChecks: off.}

type ov_partial_shape_t* = object
  ## A shape whose rank and dimensions may be dynamic.
  ##
  ## When the rank is static (`rank.min == rank.max >= 0`), `dims` points to
  ## `rank.max` dimensions; otherwise `dims` is `nil`. When OpenVINO fills
  ## this struct it allocates `dims`, and the caller must release it with
  ## `ov_partial_shape_free`. A struct the caller built itself, pointing at its
  ## own memory, must not be passed to `ov_partial_shape_free`.
  ##
  ## Layout is verified by the ABI test.
  rank*: ov_rank_t
  dims*: ptr ov_dimension_t

proc ov_partial_shape_create*(rank: int64; dims: ptr ov_dimension_t;
                              partial_shape_obj: ptr ov_partial_shape_t):
    ov_status_e {.openvinoImport.}
  ## Creates a static-rank partial shape by copying `rank` dimensions.
  ##
  ## **Quirk**: rejects `rank <= 0`, and rejects any dimension with
  ## `max < min`, which includes the unbounded form `{0, -1}` that ports
  ## report. Only `{-1, -1}` passes as "unbounded".

proc ov_partial_shape_create_dynamic*(rank: ov_rank_t;
                                      dims: ptr ov_dimension_t;
                                      partial_shape_obj:
                                        ptr ov_partial_shape_t):
    ov_status_e {.openvinoImport.}
  ## Creates a partial shape whose rank may itself be dynamic.
  ##
  ## **Quirk**: applies the same dimension check as `ov_partial_shape_create`,
  ## so `{0, -1}` and `{2, -1}` are rejected with `INVALID_C_PARAM`.

proc ov_partial_shape_create_static*(rank: int64; dims: ptr int64;
                                     partial_shape_obj:
                                       ptr ov_partial_shape_t):
    ov_status_e {.openvinoImport.}
  ## Creates a fully static partial shape.
  ##
  ## **Quirk**: rejects any dimension `<= 0`, after it has already allocated
  ## and stored `dims` in the output, so a failed call must still be followed
  ## by `ov_partial_shape_free`.

proc ov_partial_shape_free*(partial_shape: ptr ov_partial_shape_t)
  {.openvinoImport.}
  ## Releases the dimension storage OpenVINO allocated inside
  ## `partial_shape`. Safe when `dims` is `nil`.

proc ov_partial_shape_to_shape*(partial_shape: ov_partial_shape_t;
                                shape: ptr ov_shape_t): ov_status_e
  {.openvinoImport.}
  ## Converts a static partial shape to `ov_shape_t`.
  ##
  ## **Quirk**: on a dynamic dimension it returns `PARAMETER_MISMATCH` without
  ## releasing the `ov_shape_t` it already allocated, which leaks. It also
  ## treats a zero-length dimension as dynamic.

proc ov_shape_to_partial_shape*(shape: ov_shape_t;
                                partial_shape: ptr ov_partial_shape_t):
    ov_status_e {.openvinoImport.}
  ## Converts a static shape to a partial shape. Rejects rank 0.
  ##
  ## Allocates `dims`; release a successful result with
  ## `ov_partial_shape_free`.

proc ov_partial_shape_is_dynamic*(partial_shape: ov_partial_shape_t): bool
  {.openvinoImport.}
  ## Reports whether any part of the shape is dynamic.
  ##
  ## Inherits the `ov_dimension_is_dynamic` and `ov_rank_is_dynamic` quirks.

proc ov_partial_shape_to_string*(partial_shape: ov_partial_shape_t): cstring
  {.openvinoImport.}
  ## Formats the shape, for example `{?,4}` or `{1..8,4}`.
  ##
  ## Returns an allocated string that the caller must copy and release with
  ## `ov_free`.

{.pop.}
