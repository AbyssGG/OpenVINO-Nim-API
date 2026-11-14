# SPDX-License-Identifier: Apache-2.0

## Managed values must never be overwritten or duplicated by tensor byte copies.
## The check runs before accessing a tensor or loading the OpenVINO runtime.

import std/[strutils, unittest]

import openvino

type ContainsString = object
  value: string

suite "tensor copy safety":
  test "managed values are rejected before accessing the runtime":
    var tensor: Tensor
    var strings = @["owned"]
    var records = @[ContainsString(value: "owned")]

    for operation in 0 .. 3:
      try:
        case operation
        of 0: tensor.copyFrom(strings)
        of 1: tensor.copyTo(strings)
        of 2: discard tensor.toSeq(ContainsString)
        else: discard tensorFrom(etU64, initShape(1), records)
        check false
      except OpenVinoArgumentError as err:
        check "safe for byte copying" in err.msg

    check strings == @["owned"]
    check records[0].value == "owned"

  test "ordinary numeric values still reach the tensor state check":
    var tensor: Tensor
    try:
      tensor.copyFrom([float32(1)])
      check false
    except OpenVinoArgumentError as err:
      check "closed" in err.msg
