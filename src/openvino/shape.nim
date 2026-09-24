# SPDX-License-Identifier: Apache-2.0

## The static description of a tensor: its element type and its dimensions.
##
## Both live here because neither is useful alone. A shape without an element
## type cannot be sized in bytes, and an element type without a shape cannot be
## counted. Keeping them together puts every size computation, and every
## overflow check, in one place.
##
## `ElementType` is a real Nim enum, unlike the raw layer's `cint` alias. The
## managed layer only ever holds a value it has validated, so an enum is safe
## here and gives exhaustive `case` coverage. Converting from the raw value is
## the validating step and rejects anything unknown.

import std/strutils

import errors
import private/conversions
import raw/common

type
  ElementType* = enum
    ## Tensor element type, mirroring `ov_element_type_e` from the pinned
    ## headers.
    ##
    ## The names match the upstream spellings so that a value read from
    ## OpenVINO documentation can be found here. That includes `etF8E5M3`,
    ## whose upstream symbol disagrees with its own header comment; the symbol
    ## wins.
    etDynamic
    etBoolean
    etBF16
    etF16
    etF32
    etF64
    etI4
    etI8
    etI16
    etI32
    etI64
    etU1
    etU2
    etU3
    etU4
    etU6
    etU8
    etU16
    etU32
    etU64
    etNF4
    etF8E4M3
    etF8E5M3
    etString
    etF4E2M1
    etF8E8M0

  Shape* = object
    ## A static shape: zero or more non-negative dimensions.
    ##
    ## An empty shape denotes a scalar and has one element, matching
    ## `ov_tensor_get_size`.
    ##
    ## Validated on construction, so a `Shape` that exists is always usable:
    ## no negative dimension, and an element count that fits in `int64`.
    dimensions: seq[int64]

const rawElementTypes: array[ElementType, ov_element_type_e] = [
  DYNAMIC, BOOLEAN, BF16, F16, F32, F64, I4, I8, I16, I32, I64,
  U1, U2, U3, U4, U6, U8, U16, U32, U64,
  NF4, F8E4M3, F8E5M3, STRING, F4E2M1, F8E8M0]
  ## Managed to raw mapping. Index order must match the `ElementType`
  ## declaration; the ABI test verifies the raw values themselves.

const bitsPerElementTable: array[ElementType, int] = [
  0,                # etDynamic, no fixed width
  8,                # etBoolean
  16, 16, 32, 64,   # etBF16, etF16, etF32, etF64
  4, 8, 16, 32, 64, # etI4, etI8, etI16, etI32, etI64
  1, 2, 3, 4, 6,    # etU1, etU2, etU3, etU4, etU6
  8, 16, 32, 64,    # etU8, etU16, etU32, etU64
  4,                # etNF4
  8, 8,             # etF8E4M3, etF8E5M3
  0,                # etString, variable length
  4,                # etF4E2M1
  8]                # etF8E8M0
  ## Width in **bits**, not bytes, because several types are sub-byte. A zero
  ## means the type has no fixed width and cannot be sized arithmetically.

proc toRaw*(elementType: ElementType): ov_element_type_e =
  ## Returns the raw ABI value for `elementType`.
  rawElementTypes[elementType]

proc toElementType*(raw: ov_element_type_e): ElementType =
  ## Converts a raw element type reported by OpenVINO.
  ##
  ## Raises `OpenVinoArgumentError` for a value this package does not know,
  ## which is why the raw layer keeps a `cint` rather than an enum: an unknown
  ## value stays representable long enough to be reported properly instead of
  ## becoming an illegal enum.
  for candidate in ElementType:
    if rawElementTypes[candidate] == raw:
      return candidate
  raiseArgumentError("OpenVINO reported element type " & $raw &
    ", which this build of openvino-nim does not know. The installed runtime " &
    "is probably newer than the version this package pins.")

proc bitsPerElement*(elementType: ElementType): int =
  ## Returns the width of one element in bits.
  ##
  ## Zero for `etDynamic` and `etString`, which have no fixed width.
  bitsPerElementTable[elementType]

proc hasFixedWidth*(elementType: ElementType): bool =
  ## Reports whether elements of this type can be sized arithmetically.
  bitsPerElementTable[elementType] > 0

proc isSubByte*(elementType: ElementType): bool =
  ## Reports whether one element occupies fewer than eight bits.
  ##
  ## Sub-byte types are packed, so an element count cannot be turned into a
  ## byte count by multiplication alone. Typed access to such a tensor is
  ## therefore refused rather than silently misinterpreted.
  let bits = bitsPerElementTable[elementType]
  bits > 0 and bits < 8

proc initShape*(dimensions: openArray[int64]): Shape =
  ## Builds a shape from `dimensions`.
  ##
  ## Raises `OpenVinoArgumentError` on a negative dimension, or when the
  ## element count would overflow `int64`. Validating here means every later
  ## use can rely on it.
  discard checkedElementCount(dimensions)
  result = Shape(dimensions: @dimensions)

proc initShape*(dimensions: varargs[int]): Shape =
  ## Convenience form for the common case of writing dimensions as `int`.
  ##
  ## Raises `OpenVinoArgumentError` on a negative dimension or on overflow.
  var widened = newSeq[int64](dimensions.len)
  for index, dimension in dimensions:
    widened[index] = int64(dimension)
  result = initShape(widened)

proc dims*(shape: Shape): seq[int64] =
  ## Returns a copy of the dimensions.
  ##
  ## A copy rather than a view, so a caller cannot reach in and invalidate the
  ## checks that `initShape` performed.
  shape.dimensions

proc rank*(shape: Shape): int =
  ## Returns the number of dimensions. Zero denotes a scalar.
  shape.dimensions.len

proc elementCount*(shape: Shape): int64 =
  ## Returns the number of elements, which is 1 for a scalar.
  ##
  ## Cannot overflow, because `initShape` already rejected shapes that would.
  checkedElementCount(shape.dimensions)

proc byteSize*(shape: Shape; elementType: ElementType): int64 =
  ## Returns the storage size in bytes for `shape` holding `elementType`.
  ##
  ## Raises `OpenVinoArgumentError` when the element type has no fixed width,
  ## when it is sub-byte, or when the product would overflow. Sub-byte types
  ## are refused rather than rounded, because a rounded answer would be used to
  ## size a buffer.
  if not hasFixedWidth(elementType):
    raiseArgumentError($elementType &
      " has no fixed element width, so a byte size cannot be computed")
  if isSubByte(elementType):
    raiseArgumentError($elementType &
      " packs several elements per byte, so a byte size cannot be computed " &
      "from the element count alone")
  result = checkedByteSize(shape.elementCount,
                           int64(bitsPerElement(elementType) div 8))

proc `$`*(shape: Shape): string =
  ## Returns a readable form such as `[1, 3, 224, 224]`, or `[] (scalar)`.
  if shape.dimensions.len == 0:
    return "[] (scalar)"
  var parts = newSeq[string](shape.dimensions.len)
  for index, dimension in shape.dimensions:
    parts[index] = $dimension
  result = "[" & parts.join(", ") & "]"

proc `==`*(a, b: Shape): bool =
  ## Two shapes are equal when their dimensions are equal.
  a.dimensions == b.dimensions
