# SPDX-License-Identifier: Apache-2.0

## Compiled models: creating inference requests, reading port metadata, and
## explicit export.
##
## Export is explicit and nothing else. There is no "compile or import"
## convenience: deciding when a cached blob is valid, where it lives and when to
## discard it is application policy, and putting it here would make every
## consumer inherit one project's answer.

import errors
import infer_request
import node
import private/conversions
import private/handles
import properties
import raw/compiled_model as rawCompiled
import raw/infer_request as rawRequest
import raw/node as rawNode

export infer_request
export node
export properties

type CompiledModel* = object
  ## A model compiled for a specific device.
  ##
  ## Owns one `ov_compiled_model_t`. Copying shares the native object and the
  ## closed state.
  ##
  ## Threads: creating requests from one compiled model on several threads is
  ## the shape OpenVINO is built for, and each request then has its own tensors.
  ## This package adds no lock, and it has not been measured under concurrency;
  ## `setProperties` after requests exist is a change under other threads' feet
  ## and is not covered by anything here. Independent of the `Model` it was compiled from, which may be
  ## closed immediately afterwards.
  handle: Handle[ov_compiled_model_t]

proc releaseCompiledModel(native: ptr ov_compiled_model_t) {.nimcall.} =
  ## Release function handed to the handle model.
  ov_compiled_model_free(native)

proc wrapCompiledModel*(native: ptr ov_compiled_model_t): CompiledModel =
  ## Takes ownership of `native`. Internal to the package.
  CompiledModel(handle: newHandle(native, releaseCompiledModel,
                                  "compiled model"))

proc close*(model: CompiledModel) =
  ## Releases the compiled model. Safe to call more than once.
  ##
  ## Close the inference requests created from it first; releasing a compiled
  ## model while a request on it is alive is not something OpenVINO promises to
  ## survive.
  model.handle.close()

proc isClosed*(model: CompiledModel): bool =
  ## Reports whether the compiled model has been closed. Never raises.
  model.handle.isClosed()

proc inputCount*(model: CompiledModel): int =
  ## Returns the number of inputs.
  ##
  ## Raises `OpenVinoArgumentError` if the compiled model is closed.
  var count: csize_t = 0
  checkStatus(ov_compiled_model_inputs_size(model.handle.native(), addr count),
              "get compiled model input count")
  result = int(count)

proc outputCount*(model: CompiledModel): int =
  ## Returns the number of outputs.
  ##
  ## Raises `OpenVinoArgumentError` if the compiled model is closed.
  var count: csize_t = 0
  checkStatus(ov_compiled_model_outputs_size(model.handle.native(), addr count),
              "get compiled model output count")
  result = int(count)

proc input*(model: CompiledModel; index: int): Port =
  ## Returns the input port at `index`. The port must be closed.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or out-of-range index.
  let raw = checkedIndex(index, model.inputCount, "input")
  var native: ptr ov_output_const_port_t = nil
  checkStatus(ov_compiled_model_input_by_index(model.handle.native(), raw,
                                              addr native),
              "get compiled model input port", "index=" & $index)
  result = wrapPort(native)

proc output*(model: CompiledModel; index: int): Port =
  ## Returns the output port at `index`. The port must be closed.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or out-of-range index.
  let raw = checkedIndex(index, model.outputCount, "output")
  var native: ptr ov_output_const_port_t = nil
  checkStatus(ov_compiled_model_output_by_index(model.handle.native(), raw,
                                               addr native),
              "get compiled model output port", "index=" & $index)
  result = wrapPort(native)

proc createInferRequest*(model: CompiledModel): InferRequest =
  ## Creates an inference request. The request must be closed.
  ##
  ## Each request carries its own input and output tensors, so one request per
  ## thread is the way to infer concurrently. Pooling requests is an application
  ## concern and is not provided here.
  ##
  ## Raises `OpenVinoError` when the runtime refuses, and
  ## `OpenVinoArgumentError` if the compiled model is closed.
  let
    inputs = model.inputCount
    outputs = model.outputCount
  var native: ptr ov_infer_request_t = nil
  checkStatus(ov_compiled_model_create_infer_request(model.handle.native(),
                                                    addr native),
              "create infer request")
  result = wrapInferRequest(native, inputs, outputs)

proc setProperties*(model: CompiledModel;
                    values: openArray[Property]) =
  ## Applies `values` to the compiled model.
  ##
  ## Not every property can be changed after compilation; the runtime decides
  ## and reports.
  ##
  ## Raises `OpenVinoError` when the runtime refuses a property, and
  ## `OpenVinoArgumentError` if the compiled model is closed.
  let native = model.handle.native()
  withRawProperties(values, rawProperties, count):
    checkStatus(ov_compiled_model_set_properties(native, count, rawProperties),
                "set compiled model properties")

proc getProperty*(model: CompiledModel; key: string): string =
  ## Reads one property as a string.
  ##
  ## Copies the value and releases OpenVINO's allocation before returning.
  ##
  ## Raises `OpenVinoError` when the property is unknown to the device, and
  ## `OpenVinoArgumentError` if the compiled model is closed.
  var native: cstring = nil
  checkStatus(ov_compiled_model_get_property(model.handle.native(),
                                            key.cstring, addr native),
              "get compiled model property", key)
  result = takeString(native)

proc exportTo*(model: CompiledModel; path: string) =
  ## Writes the compiled model to `path`.
  ##
  ## **Performs file I/O** and **blocks**. Writes exactly the path given: no
  ## directory is created, no name is derived, and nothing is written unless
  ## this is called.
  ##
  ## Raises `OpenVinoError` when the path cannot be written or the device does
  ## not support export.
  checkStatus(ov_compiled_model_export_model(model.handle.native(),
                                            path.cstring),
              "export compiled model", path)

proc unsafeRawHandle*(model: CompiledModel): ptr ov_compiled_model_t =
  ## Returns the borrowed native handle for use with `openvino/raw`.
  model.handle.native()
