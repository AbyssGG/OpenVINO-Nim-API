# SPDX-License-Identifier: Apache-2.0

## Partial shapes: dimensions that may be unknown, bounded or open-ended, and
## ranks that may themselves be unknown.
##
## Everything here is plain Nim and needs no OpenVINO runtime, so every
## construction, comparison and compatibility rule is unit-tested without one.
## Conversion to and from the C representation lives in
## `private/partial_shapes`.
##
## The rules for what is static are decided here rather than by OpenVINO's
## `ov_dimension_is_dynamic` and `ov_rank_is_dynamic`, which report a static
## zero-length dimension and a rank-0 scalar as dynamic. See
## `docs/decisions/0004-partial-shape-representation.md`.

import std/strutils

import errors
import shape

type
  Dimension* = object
    ## One dimension as an inclusive interval `[minLength, maxLength]`.
    ##
    ## `maxLength == -1` means there is no upper bound. Validated on
    ## construction, so a `Dimension` that exists is always well formed:
    ## `minLength >= 0`, and `maxLength` is `-1` or at least `minLength`.
    lo: int64
    hi: int64

  PartialShape* = object
    ## A shape whose rank and dimensions may be dynamic.
    ##
    ## When the rank is known, there is one `Dimension` per axis; rank 0 is a
    ## scalar. When the rank itself is unknown, there are no dimensions.
    rankKnown: bool
    dimensions: seq[Dimension]

const unbounded = -1'i64
  ## Upper bound meaning "no limit", the same encoding OpenVINO uses.

proc staticDim*(length: int64): Dimension =
  ## A dimension of exactly `length`. Zero is allowed.
  ##
  ## Raises `OpenVinoArgumentError` for a negative length.
  if length < 0:
    raiseArgumentError("a static dimension cannot be negative: " & $length)
  Dimension(lo: length, hi: length)

proc dynamicDim*(): Dimension =
  ## A dimension of any length, written `?`.
  Dimension(lo: 0, hi: unbounded)

proc boundedDim*(lo, hi: int64): Dimension =
  ## A dimension between `lo` and `hi` inclusive, written `lo..hi`.
  ##
  ## Raises `OpenVinoArgumentError` unless `0 <= lo <= hi`. Use `atLeastDim`
  ## for an interval without an upper bound.
  if lo < 0:
    raiseArgumentError("a dimension's lower bound cannot be negative: " & $lo)
  if hi < lo:
    raiseArgumentError("a dimension's upper bound " & $hi &
      " is below its lower bound " & $lo)
  Dimension(lo: lo, hi: hi)

proc atLeastDim*(lo: int64): Dimension =
  ## A dimension of at least `lo` with no upper bound, written `lo..`.
  ##
  ## `atLeastDim(0)` is the same as `dynamicDim()`. Raises
  ## `OpenVinoArgumentError` for a negative bound.
  if lo < 0:
    raiseArgumentError("a dimension's lower bound cannot be negative: " & $lo)
  Dimension(lo: lo, hi: unbounded)

proc minLength*(dimension: Dimension): int64 =
  ## Returns the inclusive lower bound.
  dimension.lo

proc maxLength*(dimension: Dimension): int64 =
  ## Returns the inclusive upper bound, or `-1` when there is none.
  dimension.hi

proc hasUpperBound*(dimension: Dimension): bool =
  ## Reports whether the dimension has an upper bound.
  dimension.hi != unbounded

proc isStatic*(dimension: Dimension): bool =
  ## Reports whether the dimension has exactly one possible length.
  ##
  ## Decided in Nim: a static zero-length dimension is static, unlike what
  ## `ov_dimension_is_dynamic` reports.
  dimension.lo == dimension.hi and dimension.hi >= 0

proc isDynamic*(dimension: Dimension): bool =
  ## The opposite of `isStatic`.
  not dimension.isStatic

proc contains*(dimension: Dimension; length: int64): bool =
  ## Reports whether `length` is a possible value of the dimension, so that
  ## `4 in dim` reads naturally.
  length >= dimension.lo and (dimension.hi == unbounded or
    length <= dimension.hi)

proc `$`*(dimension: Dimension): string =
  ## Formats the dimension as `4`, `?`, `1..8` or `2..`.
  if dimension.isStatic:
    $dimension.lo
  elif dimension.hi == unbounded:
    if dimension.lo == 0: "?" else: $dimension.lo & ".."
  else:
    $dimension.lo & ".." & $dimension.hi

proc `==`*(a, b: Dimension): bool =
  ## Two dimensions are equal when their bounds are equal.
  a.lo == b.lo and a.hi == b.hi

proc initPartialShape*(dimensions: openArray[Dimension]): PartialShape =
  ## A partial shape with a known rank and the given dimensions.
  ##
  ## An empty list is a scalar. Each `Dimension` is already valid, so this
  ## cannot fail.
  PartialShape(rankKnown: true, dimensions: @dimensions)

proc initPartialShape*(shape: Shape): PartialShape =
  ## The fully static partial shape equal to `shape`.
  result = PartialShape(rankKnown: true,
                        dimensions: newSeq[Dimension](shape.rank))
  for index, length in shape.dims:
    result.dimensions[index] = staticDim(length)

proc dynamicRankShape*(): PartialShape =
  ## A partial shape whose rank is unknown, written `[...]`.
  PartialShape(rankKnown: false, dimensions: @[])

proc hasStaticRank*(shape: PartialShape): bool =
  ## Reports whether the number of dimensions is known.
  shape.rankKnown

proc rank*(shape: PartialShape): int =
  ## Returns the number of dimensions.
  ##
  ## Raises `OpenVinoArgumentError` when the rank is dynamic; check
  ## `hasStaticRank` first.
  if not shape.rankKnown:
    raiseArgumentError("this partial shape has a dynamic rank, [...]")
  shape.dimensions.len

proc dims*(shape: PartialShape): seq[Dimension] =
  ## Returns a copy of the dimensions.
  ##
  ## Raises `OpenVinoArgumentError` when the rank is dynamic, rather than
  ## returning an empty list that would look like a scalar.
  if not shape.rankKnown:
    raiseArgumentError("a shape with a dynamic rank has no dimension list")
  shape.dimensions

proc isStatic*(shape: PartialShape): bool =
  ## Reports whether the rank and every dimension are static.
  if not shape.rankKnown:
    return false
  for dimension in shape.dimensions:
    if not dimension.isStatic:
      return false
  true

proc isDynamic*(shape: PartialShape): bool =
  ## The opposite of `isStatic`.
  not shape.isStatic

proc `$`*(shape: PartialShape): string =
  ## Formats the shape as `[?, 4]`, `[1..8, 3, 224, 224]`, `[...]` for a
  ## dynamic rank, or `[] (scalar)`.
  if not shape.rankKnown:
    return "[...]"
  if shape.dimensions.len == 0:
    return "[] (scalar)"
  var parts = newSeq[string](shape.dimensions.len)
  for index, dimension in shape.dimensions:
    parts[index] = $dimension
  result = "[" & parts.join(", ") & "]"

proc toShape*(shape: PartialShape): Shape =
  ## Converts a fully static partial shape to a `Shape`.
  ##
  ## Raises `OpenVinoArgumentError` when any part is dynamic. Implemented in
  ## Nim; `ov_partial_shape_to_shape` leaks on that error path.
  if not shape.isStatic:
    raiseArgumentError("partial shape " & $shape &
      " is not static, so it has no static Shape")
  var lengths = newSeq[int64](shape.dimensions.len)
  for index, dimension in shape.dimensions:
    lengths[index] = dimension.lo
  result = initShape(lengths)

proc accepts*(shape: PartialShape; candidate: Shape): bool =
  ## Reports whether a tensor of shape `candidate` fits this partial shape,
  ## for checking an input before inference.
  ##
  ## A dynamic rank accepts any shape. Otherwise the ranks must match and each
  ## length must lie within its dimension.
  if not shape.rankKnown:
    return true
  if candidate.rank != shape.dimensions.len:
    return false
  for index, length in candidate.dims:
    if length notin shape.dimensions[index]:
      return false
  true

proc `==`*(a, b: PartialShape): bool =
  ## Two partial shapes are equal when both ranks are dynamic, or both ranks
  ## are known and every dimension is equal.
  if a.rankKnown != b.rankKnown:
    return false
  a.dimensions == b.dimensions
