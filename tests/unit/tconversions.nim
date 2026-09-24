# SPDX-License-Identifier: Apache-2.0

## Tests for the checked arithmetic and index conversion helpers.
##
## These need no OpenVINO runtime. They cover the cases that turn a silent
## memory error into a reported one: a negative dimension, a product that
## overflows, and a negative index that would become an enormous `csize_t`.

import std/[strutils, unittest]

import openvino/errors
import openvino/private/conversions

suite "element count":
  test "an empty shape is a scalar with one element":
    check checkedElementCount([]) == 1

  test "a normal shape multiplies out":
    check checkedElementCount([int64(1), 3, 224, 224]) == 150528

  test "a zero dimension yields zero rather than one":
    check checkedElementCount([int64(2), 0, 5]) == 0

  test "a negative dimension is rejected and names its position":
    try:
      discard checkedElementCount([int64(2), -1, 5])
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "dimension 1" in err.msg

  test "a product that would overflow is rejected before it wraps":
    # Two dimensions whose product exceeds int64. Detecting this afterwards is
    # impossible: the wrapped value looks like a plausible small count and would
    # be used to size a buffer.
    let huge = high(int64) div 4
    expect OpenVinoArgumentError:
      discard checkedElementCount([huge, int64(8)])

  test "a product that exactly fits is accepted":
    check checkedElementCount([high(int64), int64(1)]) == high(int64)

suite "byte size":
  test "a normal element count and size multiply out":
    check checkedByteSize(24, 4) == 96

  test "a zero element count gives zero bytes":
    check checkedByteSize(0, 4) == 0

  test "a zero element size gives zero bytes":
    check checkedByteSize(24, 0) == 0

  test "a negative element count is rejected":
    expect OpenVinoArgumentError:
      discard checkedByteSize(-1, 4)

  test "a negative element size is rejected":
    expect OpenVinoArgumentError:
      discard checkedByteSize(24, -4)

  test "an overflowing byte size is rejected":
    expect OpenVinoArgumentError:
      discard checkedByteSize(high(int64) div 2, 4)

suite "index conversion":
  test "an in-range index converts":
    check checkedIndex(0, 3, "input") == csize_t(0)
    check checkedIndex(2, 3, "input") == csize_t(2)

  test "a negative index is rejected before it becomes a huge csize_t":
    # This is the whole point of the helper. Converting -1 to csize_t yields
    # 18446744073709551615, and OpenVINO would index far outside its arrays.
    try:
      discard checkedIndex(-1, 3, "input")
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "negative" in err.msg

  test "an index at the count is rejected and reports the count":
    try:
      discard checkedIndex(3, 3, "output")
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "output" in err.msg
      check "there are 3" in err.msg

  test "any index into an empty collection is rejected":
    expect OpenVinoArgumentError:
      discard checkedIndex(0, 0, "input")

suite "argument errors are catchable as ValueError":
  test "an OpenVinoArgumentError is a ValueError":
    # Chosen so that existing handlers for bad arguments keep working.
    var caughtAsValueError = false
    try:
      raiseArgumentError("example")
    except ValueError:
      caughtAsValueError = true
    check caughtAsValueError
