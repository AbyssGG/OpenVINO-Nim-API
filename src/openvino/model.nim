# SPDX-License-Identifier: Apache-2.0

## Models read from disk, before compilation.
##
## A `Model` is the network as OpenVINO parsed it. It reports how many inputs
## and outputs it has and describes each one. Compiling it for a device is
## `Core.compileModel`.

import errors
import node
import private/conversions
import private/handles
import raw/model as rawModel
import raw/node as rawNode

export node

type Model* = object
  ## A parsed but uncompiled model.
  ##
  ## Owns one `ov_model_t`. Copying shares the native object and the closed
  ## state.
  handle: Handle[ov_model_t]

proc releaseModel(native: ptr ov_model_t) {.nimcall.} =
  ## Release function handed to the handle model.
  ov_model_free(native)

proc wrapModel*(native: ptr ov_model_t): Model =
  ## Takes ownership of `native`. Internal to the package.
  Model(handle: newHandle(native, releaseModel, "model"))

proc close*(model: Model) =
  ## Releases the model. Safe to call more than once.
  ##
  ## A compiled model does not depend on the `Model` it came from, so closing
  ## the model after compiling is both safe and the usual thing to do.
  model.handle.close()

proc isClosed*(model: Model): bool =
  ## Reports whether the model has been closed. Never raises.
  model.handle.isClosed()

proc inputCount*(model: Model): int =
  ## Returns the number of inputs.
  ##
  ## Raises `OpenVinoArgumentError` if the model is closed.
  var count: csize_t = 0
  checkStatus(ov_model_inputs_size(model.handle.native(), addr count),
              "get model input count")
  result = int(count)

proc outputCount*(model: Model): int =
  ## Returns the number of outputs.
  ##
  ## Raises `OpenVinoArgumentError` if the model is closed.
  var count: csize_t = 0
  checkStatus(ov_model_outputs_size(model.handle.native(), addr count),
              "get model output count")
  result = int(count)

proc input*(model: Model; index: int): Port =
  ## Returns the input port at `index`.
  ##
  ## The port is a new owner and must be closed.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or out-of-range index. The
  ## index is checked here rather than left to OpenVINO, because a negative
  ## `int` converted to `csize_t` becomes an enormous positive value.
  let raw = checkedIndex(index, model.inputCount, "input")
  var native: ptr ov_output_const_port_t = nil
  checkStatus(ov_model_const_input_by_index(model.handle.native(), raw,
                                           addr native),
              "get model input port", "index=" & $index)
  result = wrapPort(native)

proc output*(model: Model; index: int): Port =
  ## Returns the output port at `index`.
  ##
  ## The port is a new owner and must be closed.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or out-of-range index.
  let raw = checkedIndex(index, model.outputCount, "output")
  var native: ptr ov_output_const_port_t = nil
  checkStatus(ov_model_const_output_by_index(model.handle.native(), raw,
                                            addr native),
              "get model output port", "index=" & $index)
  result = wrapPort(native)

proc input*(model: Model; name: string): Port =
  ## Returns the input port named `name`.
  ##
  ## Raises `OpenVinoError` when no input has that name.
  var native: ptr ov_output_const_port_t = nil
  checkStatus(ov_model_const_input_by_name(model.handle.native(),
                                          name.cstring, addr native),
              "get model input port by name", name)
  result = wrapPort(native)

proc output*(model: Model; name: string): Port =
  ## Returns the output port named `name`.
  ##
  ## Raises `OpenVinoError` when no output has that name.
  var native: ptr ov_output_const_port_t = nil
  checkStatus(ov_model_const_output_by_name(model.handle.native(),
                                           name.cstring, addr native),
              "get model output port by name", name)
  result = wrapPort(native)

proc isDynamic*(model: Model): bool =
  ## Reports whether any dimension of the model is dynamic.
  ##
  ## A dynamic model can be compiled, but `Port.shape` will fail for its
  ## dynamic ports, because `0.1.0` has no partial-shape type.
  ##
  ## Raises `OpenVinoArgumentError` if the model is closed.
  ov_model_is_dynamic(model.handle.native())

proc friendlyName*(model: Model): string =
  ## Returns the model's own name.
  ##
  ## Copies the string and releases OpenVINO's allocation before returning.
  ##
  ## Raises `OpenVinoArgumentError` if the model is closed.
  var native: cstring = nil
  checkStatus(ov_model_get_friendly_name(model.handle.native(), addr native),
              "get model name")
  result = takeString(native)

proc unsafeRawHandle*(model: Model): ptr ov_model_t =
  ## Returns the borrowed native handle for use with `openvino/raw`.
  model.handle.native()
