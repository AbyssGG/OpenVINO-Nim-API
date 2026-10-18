# SPDX-License-Identifier: Apache-2.0

## Models read from disk, before compilation.
##
## A `Model` is the network as OpenVINO parsed it. It reports how many inputs
## and outputs it has, describes each one, and can be reshaped. Compiling it
## for a device is `Core.compileModel`.

import std/[sets, strutils]

import errors
import node
import partial_shape
import private/conversions
import private/handles
import private/partial_shapes
import raw/dimension
import raw/model as rawModel
import raw/node as rawNode
import raw/partial_shape as rawPartialShape

export node

type Model* = object
  ## A parsed but uncompiled model.
  ##
  ## Owns one `ov_model_t`. Copying shares the native object and the closed
  ## state.
  ##
  ## Threads: read-only queries on one `Model` from several threads are not
  ## tested and not claimed. Reading a model is cheap relative to compiling, so
  ## the simple answer is one `Model` per thread, and the plain answer is that
  ## concurrency here has not been measured.
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
  ## A dynamic model can be compiled. `Port.shape` fails for its dynamic
  ## ports; read them with `Port.partialShape`.
  ##
  ## Raises `OpenVinoArgumentError` if the model is closed.
  ov_model_is_dynamic(model.handle.native())

proc checkInputName(name: string) =
  ## Rejects names that cannot reach C intact.
  if name.len == 0:
    raiseArgumentError("an input name cannot be empty")
  if '\0' in name:
    raiseArgumentError("input name " & name.escape &
      " contains a NUL character")

proc reshape*(model: Model; inputIndex: int; shape: PartialShape) =
  ## Reshapes the input at `inputIndex` to `shape`. **Modifies the model in
  ## place**; a `CompiledModel` compiled earlier is not affected.
  ##
  ## Dynamic and bounded dimensions are allowed, so `[?, 4]` makes the batch
  ## dimension dynamic. A dynamic rank and rank 0 are refused, because the
  ## OpenVINO 2026.4 C API would silently reshape to `[?]` instead.
  ##
  ## Raises `OpenVinoArgumentError` for a bad index, a refused shape or a
  ## closed model, and `OpenVinoError` when OpenVINO rejects the new shape.
  let raw = checkedIndex(inputIndex, model.inputCount, "input")
  checkReshapeable(shape, "input " & $inputIndex)
  var dimensions = toRawDimensions(shape)
  var shapes = [borrowRawShape(dimensions)]
  var indexes = [raw]
  checkStatus(ov_model_reshape_by_port_indexes(model.handle.native(),
                                               addr indexes[0],
                                               addr shapes[0], 1),
              "reshape model input", "index=" & $inputIndex & " shape=" &
                $shape)

proc reshape*(model: Model; shape: PartialShape) =
  ## Reshapes the only input of a single-input model. See the by-index form.
  ##
  ## Raises `OpenVinoArgumentError` when the model does not have exactly one
  ## input, rather than silently reshaping input 0 of several.
  let count = model.inputCount
  if count != 1:
    raiseArgumentError("reshape without an input name or index needs a " &
      "model with exactly one input; this one has " & $count)
  model.reshape(0, shape)

proc reshape*(model: Model; inputName: string; shape: PartialShape) =
  ## Reshapes the input named `inputName`. See the by-index form.
  ##
  ## Raises `OpenVinoError` when no input has that name.
  checkInputName(inputName)
  checkReshapeable(shape, "input " & inputName.escape)
  var dimensions = toRawDimensions(shape)
  checkStatus(ov_model_reshape_input_by_name(model.handle.native(),
                                             inputName.cstring,
                                             borrowRawShape(dimensions)),
              "reshape model input", inputName & " shape=" & $shape)

proc reshape*(model: Model; shapes: openArray[(string, PartialShape)]) =
  ## Reshapes several inputs, by name, in **one** OpenVINO call, so either all
  ## of them change or none does. Useful when inputs must agree, for example
  ## on a batch size.
  ##
  ## Raises `OpenVinoArgumentError` for an empty list, a repeated name, or any
  ## refused shape, before calling OpenVINO.
  if shapes.len == 0:
    raiseArgumentError("reshape needs at least one input")
  var seen = initHashSet[string]()
  var dimensions = newSeq[seq[ov_dimension_t]](shapes.len)
  for index, (name, shape) in shapes:
    checkInputName(name)
    if seen.containsOrIncl(name):
      raiseArgumentError("input " & name.escape &
        " appears more than once in one reshape")
    checkReshapeable(shape, "input " & name.escape)
    dimensions[index] = toRawDimensions(shape)
  # The name strings and the dimension arrays are owned by `shapes` and
  # `dimensions`, both alive until the call returns.
  var names = newSeq[cstring](shapes.len)
  var rawShapes = newSeq[ov_partial_shape_t](shapes.len)
  for index in 0 ..< shapes.len:
    names[index] = shapes[index][0].cstring
    rawShapes[index] = borrowRawShape(dimensions[index])
  checkStatus(ov_model_reshape(model.handle.native(), addr names[0],
                               addr rawShapes[0], csize_t(shapes.len)),
              "reshape model inputs", $shapes.len & " inputs")

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
