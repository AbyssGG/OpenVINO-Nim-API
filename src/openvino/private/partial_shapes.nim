# SPDX-License-Identifier: Apache-2.0

## Conversion between `PartialShape` and the C `ov_partial_shape_t`.
##
## Both directions are deliberately asymmetric, because upstream is:
##
## - **Reading** copies a struct OpenVINO filled and allocated, then releases
##   it with `ov_partial_shape_free` in a `finally`.
## - **Writing** fills a struct in Nim whose `dims` points at a Nim-owned
##   array that lives for the duration of one C call. OpenVINO allocates
##   nothing on this path, so nothing is released, and the struct must never
##   reach `ov_partial_shape_free`. The `ov_partial_shape_create*` functions
##   are not used because they reject `{0, -1}` and `{2, -1}`.
##
## The C reshape functions turn a dynamic rank, and rank 0, into the rank-1
## shape `[?]` without reporting an error, so `checkReshapeable` refuses both
## before any C call. The evidence is in
## `docs/decisions/0004-partial-shape-representation.md`.

import ../errors
import ../partial_shape
import ../raw/dimension
import ../raw/partial_shape as rawPartialShape

proc dimensionFromRaw(raw: ov_dimension_t; axis: int): Dimension =
  ## Converts one dimension read from OpenVINO.
  ##
  ## `{-1, -1}` and `{0, -1}` both mean "any length". Anything malformed is
  ## reported rather than trusted, because it came from foreign memory.
  if raw.max == -1:
    if raw.min <= 0:
      return dynamicDim()
    return atLeastDim(raw.min)
  if raw.min < 0 or raw.max < raw.min:
    raiseArgumentError("OpenVINO reported a malformed dimension {" &
      $raw.min & ", " & $raw.max & "} at axis " & $axis)
  if raw.min == raw.max:
    return staticDim(raw.min)
  boundedDim(raw.min, raw.max)

proc takePartialShape*(raw: var ov_partial_shape_t): PartialShape =
  ## Copies a partial shape OpenVINO filled, then releases it.
  ##
  ## The rank is known when `rank.min == rank.max >= 0`, which includes a
  ## scalar; anything else is a dynamic rank and `dims` is ignored. The struct
  ## is released in a `finally`, so a malformed value does not also leak.
  try:
    let rank = raw.rank
    if rank.min != rank.max or rank.max < 0:
      return dynamicRankShape()
    var dimensions = newSeq[Dimension](int(rank.max))
    if rank.max > 0:
      if raw.dims == nil:
        raiseArgumentError("OpenVINO reported rank " & $rank.max &
          " without any dimensions")
      # invariant: for a static rank, OpenVINO allocated `dims` with exactly
      # `rank.max` `ov_dimension_t` entries (verified in the upstream C
      # binding and by the ABI test for the element layout). The loop is
      # bounded by that rank and the view does not outlive the `finally`
      # below, which releases the storage.
      let view = cast[ptr UncheckedArray[ov_dimension_t]](raw.dims)
      for axis in 0 ..< dimensions.len:
        dimensions[axis] = dimensionFromRaw(view[axis], axis)
    result = initPartialShape(dimensions)
  finally:
    ov_partial_shape_free(addr raw)

proc checkReshapeable*(shape: PartialShape; target: string) =
  ## Refuses shapes that the C reshape functions would silently misread.
  ##
  ## Raises `OpenVinoArgumentError` naming the upstream limitation for a
  ## dynamic rank or rank 0. `target` names the input in the message.
  if not shape.hasStaticRank:
    raiseArgumentError("cannot reshape " & target & " to " & $shape &
      ": the OpenVINO 2026.4 C API turns a dynamic rank into the rank-1 " &
      "shape [?], so a dynamic rank cannot be requested through it")
  if shape.rank == 0:
    raiseArgumentError("cannot reshape " & target & " to a scalar: the " &
      "OpenVINO 2026.4 C API turns rank 0 into the rank-1 shape [?], so a " &
      "scalar cannot be requested through it")

proc toRawDimensions*(shape: PartialShape): seq[ov_dimension_t] =
  ## Returns the C dimensions for `shape`, which must have a known rank.
  ##
  ## Unbounded upper limits are written as `-1`, the same encoding OpenVINO
  ## reads back; the reshape path passes it straight to `ov::Dimension`.
  let dimensions = shape.dims
  result = newSeq[ov_dimension_t](dimensions.len)
  for index, dimension in dimensions:
    result[index] = ov_dimension_t(min: dimension.minLength,
                                   max: dimension.maxLength)

proc borrowRawShape*(dimensions: var seq[ov_dimension_t]): ov_partial_shape_t =
  ## Builds a struct that **borrows** `dimensions`.
  ##
  ## The result is valid only while `dimensions` is alive and unmodified, and
  ## must never be passed to `ov_partial_shape_free`. `dimensions` must not be
  ## empty; `checkReshapeable` guarantees that for the reshape path.
  let rank = int64(dimensions.len)
  result = ov_partial_shape_t(rank: ov_rank_t(min: rank, max: rank),
                              dims: addr dimensions[0])
