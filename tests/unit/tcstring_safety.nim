# SPDX-License-Identifier: Apache-2.0

## C strings must not silently truncate caller-supplied names or paths.

import std/[strutils, unittest]

import openvino

suite "C string safety":
  test "public entry points reject embedded NUL before native calls":
    var model: Model
    var compiled: CompiledModel
    var request: InferRequest
    var core: Core
    var tensor: Tensor
    for operation in 0 .. 12:
      try:
        case operation
        of 0: discard model.input("input\0bad")
        of 1: discard model.output("output\0bad")
        of 2: request.setInputTensor("input\0bad", tensor)
        of 3: discard core.getProperty("CPU\0bad", "key")
        of 4: discard core.getProperty("CPU", "key\0bad")
        of 5: core.setProperties("CPU\0bad", [])
        of 6: discard core.readModel("model\0bad")
        of 7: discard core.compileModel(model, "CPU\0bad")
        of 8: discard core.compileModel("model", "CPU\0bad")
        of 9: discard compiled.getProperty("key\0bad")
        of 10: compiled.exportTo("path\0bad")
        of 11: discard core.readModel("model", "weights\0bad")
        else: discard core.importModel("blob", "CPU\0bad")
        check false
      except OpenVinoArgumentError as err:
        check "NUL" in err.msg
