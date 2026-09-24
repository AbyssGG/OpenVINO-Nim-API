# SPDX-License-Identifier: Apache-2.0

## Shapes, element types and string-valued properties.
##
## None of this needs an OpenVINO runtime: a `Shape` is validated in Nim, an
## `ElementType` is a Nim enum with a table of widths, and `initProperty` is a
## pair of strings. That is the point of checking them here rather than only
## through inference, where a shape mistake would surface as a wrong number
## instead of as a refused argument.
##
## `enableProfiling` and the other key-resolving constructors are deliberately
## absent: they read exported data symbols from the runtime, so they belong to
## the tests that load one.

import std/[strutils, unittest]

import openvino

suite "building a shape":
  test "dimensions are kept in order":
    let shape = initShape(1, 3, 224, 224)
    check shape.dims == @[int64(1), 3, 224, 224]
    check shape.rank == 4

  test "no arguments is a scalar holding one element":
    # `initShape([])` cannot compile: an empty array literal has no element
    # type, so both overloads match it. Written without arguments it is
    # unambiguous, and this test is what pins that spelling.
    let scalar = initShape()
    check scalar.rank == 0
    check scalar.elementCount == 1

  test "a zero dimension gives zero elements, not one":
    check initShape(2, 0, 5).elementCount == 0

  test "the int and int64 forms agree":
    check initShape(1, 4) == initShape([int64(1), 4])

  test "dims returns a copy, so a caller cannot invalidate the checks":
    let shape = initShape(1, 4)
    var borrowed = shape.dims
    borrowed[0] = -7
    check shape.dims == @[int64(1), 4]

  test "a negative dimension is refused and its position named":
    try:
      discard initShape(1, -4, 8)
      check false
    except OpenVinoArgumentError as err:
      check "dimension 1" in err.msg

  test "an element count that would overflow is refused":
    expect OpenVinoArgumentError:
      discard initShape([high(int64), int64(8)])

  test "the string form is readable and marks a scalar":
    check $initShape(1, 4) == "[1, 4]"
    check "scalar" in $initShape()

suite "element types":
  test "a fixed-width type reports its width in bits":
    check bitsPerElement(etF32) == 32
    check bitsPerElement(etU8) == 8
    check hasFixedWidth(etF32)

  test "dynamic and string have no fixed width":
    check bitsPerElement(etDynamic) == 0
    check not hasFixedWidth(etDynamic)
    check not hasFixedWidth(etString)

  test "sub-byte types are recognised as packed":
    check isSubByte(etU4)
    check isSubByte(etU1)
    check not isSubByte(etU8)

  test "a byte size multiplies elements by width":
    check initShape(1, 3, 224, 224).byteSize(etF32) == 602112
    check initShape(1, 3, 224, 224).byteSize(etU8) == 150528

  test "a sub-byte type refuses a byte size rather than rounding one":
    # A rounded answer would be used to size a buffer, so refusing is the only
    # safe response.
    try:
      discard initShape(1, 8).byteSize(etU4)
      check false
    except OpenVinoArgumentError as err:
      check "packs several elements per byte" in err.msg

  test "a type with no fixed width refuses a byte size":
    expect OpenVinoArgumentError:
      discard initShape(1, 4).byteSize(etDynamic)

suite "properties":
  test "a key and value are kept verbatim":
    let property = initProperty("CACHE_DIR", "/tmp/cache")
    check property.key == "CACHE_DIR"
    check property.value == "/tmp/cache"
    check $property == "CACHE_DIR=/tmp/cache"

  test "an empty key is refused":
    # OpenVINO would reject it too, with a less specific message.
    expect OpenVinoArgumentError:
      discard initProperty("", "YES")

  test "an empty value is allowed, because some keys accept one":
    check initProperty("SOME_KEY", "").value == ""

  test "a non-positive thread or stream count is refused":
    # These validate before touching the runtime, so they are checkable here.
    expect OpenVinoArgumentError:
      discard inferenceThreadCount(0)
    expect OpenVinoArgumentError:
      discard streamCount(-1)
