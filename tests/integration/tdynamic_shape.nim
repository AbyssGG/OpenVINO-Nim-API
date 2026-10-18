# SPDX-License-Identifier: Apache-2.0

## Dynamic and bounded shapes through the public API: reading partial shapes,
## reshaping, and running one compiled model with several input shapes.
##
## Fixtures: `relu_dyn_x4_f32.xml` (input `[?, 4]`), `relu_bounded_f32.xml`
## (input `[1..8, 4]`) and `relu_1x4_f32.xml` (static `[1, 4]`). All three
## compute `max(0, x)`, so every expected output is computed here by hand.
##
## Run with `nimble testIntegration`.

import std/[os, strutils, unittest]

import openvino

const
  fixtureDirectory = currentSourcePath().parentDir.parentDir / "fixtures"
  dynamicPath = fixtureDirectory / "relu_dyn_x4_f32.xml"
  boundedPath = fixtureDirectory / "relu_bounded_f32.xml"
  staticPath = fixtureDirectory / "relu_1x4_f32.xml"
  device = "CPU"

proc batchInput(batch: int): seq[float32] =
  ## Alternating negative and positive values, so ReLU has work to do.
  result = newSeq[float32](batch * 4)
  for index in 0 ..< result.len:
    result[index] = (if index mod 2 == 0: -float32(index) - 0.5
      else: float32(index) + 0.25)

proc relu(values: openArray[float32]): seq[float32] =
  result = newSeq[float32](values.len)
  for index, value in values:
    result[index] = max(0'f32, value)

proc runBatch(request: InferRequest; batch: int): tuple[shape: Shape;
                                                      values: seq[float32]] =
  ## Binds a `[batch, 4]` tensor, infers, and copies the output out.
  let input = batchInput(batch)
  let tensor = tensorFrom(etF32, initShape(batch, 4), input)
  defer: tensor.close()
  request.setInputTensor(0, tensor)
  request.infer()
  let output = request.outputTensor(0)
  defer: output.close()
  result = (output.shape, output.toSeq(float32))

suite "reading partial shapes":
  test "a dynamic batch reads as [?, 4] on the model and its output":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(dynamicPath)
    defer: model.close()
    check model.isDynamic
    let input = model.input(0)
    defer: input.close()
    check input.partialShape == initPartialShape([dynamicDim(), staticDim(4)])
    check $input.partialShape == "[?, 4]"
    check input.isDynamic
    let output = model.output(0)
    defer: output.close()
    check $output.partialShape == "[?, 4]"

  test "a bounded batch reads back its bounds":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(boundedPath)
    defer: model.close()
    let input = model.input("input")
    defer: input.close()
    check input.partialShape ==
      initPartialShape([boundedDim(1, 8), staticDim(4)])
    check $input.partialShape == "[1..8, 4]"

  test "a static port reads the same through shape and partialShape":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    let input = model.input(0)
    defer: input.close()
    check not input.isDynamic
    check input.partialShape.toShape == input.shape

  test "shape on a dynamic port still raises, and now says what to use":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(dynamicPath)
    defer: model.close()
    let input = model.input(0)
    defer: input.close()
    try:
      discard input.shape
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "partialShape" in err.msg

  test "a compiled dynamic model reports its partial shape":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(dynamicPath, device)
    defer: compiled.close()
    let input = compiled.input(0)
    defer: input.close()
    check $input.partialShape == "[?, 4]"

  test "partialShape on a closed port raises before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    let input = model.input(0)
    input.close()
    expect OpenVinoArgumentError:
      discard input.partialShape

suite "dynamic inference":
  test "one compiled model infers batches of 1, 3 and 7 on one request":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(dynamicPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    for batch in [1, 3, 7]:
      let (shape, values) = request.runBatch(batch)
      checkpoint("batch " & $batch & " -> " & $shape)
      check shape == initShape(batch, 4)
      check values == relu(batchInput(batch))

  test "an unbound dynamic input reads as an empty [0, 4] tensor":
    # Measured in Phase 0 (M-08) and documented: there is nothing to write
    # into until a tensor of a concrete shape is bound or set.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(dynamicPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let unbound = request.inputTensor(0)
    defer: unbound.close()
    check unbound.shape == initShape(0, 4)
    check unbound.elementCount == 0

  test "setShape on the request's own input tensor also drives a new batch":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(dynamicPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let own = request.inputTensor(0)
    defer: own.close()
    own.setShape(initShape(2, 4))
    own.copyFrom(batchInput(2))
    request.infer()
    let output = request.outputTensor(0)
    defer: output.close()
    check output.shape == initShape(2, 4)
    check output.toSeq(float32) == relu(batchInput(2))

  test "a bounded model accepts batches inside its bounds and refuses 9":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(boundedPath)
    defer: model.close()
    let input = model.input(0)
    let declared = input.partialShape
    input.close()
    check declared.accepts(initShape(8, 4))
    check not declared.accepts(initShape(9, 4))
    let compiled = core.compileModel(model, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    check request.runBatch(8).shape == initShape(8, 4)
    let tooLarge = tensorFrom(etF32, initShape(9, 4), batchInput(9))
    defer: tooLarge.close()
    expect OpenVinoError:
      request.setInputTensor(0, tooLarge)

suite "reshape":
  test "a static model reshaped to a dynamic batch infers several batches":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    model.reshape(initPartialShape([dynamicDim(), staticDim(4)]))
    check model.isDynamic
    let input = model.input(0)
    defer: input.close()
    check $input.partialShape == "[?, 4]"
    let compiled = core.compileModel(model, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    for batch in [1, 5]:
      check request.runBatch(batch).values == relu(batchInput(batch))

  test "a dynamic model reshaped to static compiles a static model":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(dynamicPath)
    defer: model.close()
    model.reshape("input", initPartialShape(initShape(3, 4)))
    check not model.isDynamic
    let input = model.input(0)
    defer: input.close()
    check input.shape == initShape(3, 4)
    let compiled = core.compileModel(model, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    check request.runBatch(3).values == relu(batchInput(3))

  test "reshape by index and by a batch of names write the same shape":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    model.reshape(0, initPartialShape([boundedDim(1, 8), staticDim(4)]))
    var input = model.input(0)
    check $input.partialShape == "[1..8, 4]"
    input.close()
    model.reshape([("input", initPartialShape([atLeastDim(2),
                                                staticDim(4)]))])
    input = model.input(0)
    check $input.partialShape == "[2.., 4]"
    input.close()

  test "a zero-length batch reshapes, compiles and infers":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    model.reshape(initPartialShape(initShape(0, 4)))
    let compiled = core.compileModel(model, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    request.infer()
    let output = request.outputTensor(0)
    defer: output.close()
    check output.shape == initShape(0, 4)

  test "an existing compiled model is not affected by a later reshape":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    let compiled = core.compileModel(model, device)
    defer: compiled.close()
    model.reshape(initPartialShape(initShape(5, 4)))
    let input = compiled.input(0)
    defer: input.close()
    check input.shape == initShape(1, 4)

suite "reshape errors":
  test "a dynamic rank and a scalar are refused before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    try:
      model.reshape(dynamicRankShape())
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "dynamic rank" in err.msg
    try:
      model.reshape("input", initPartialShape(initShape()))
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "scalar" in err.msg
    let input = model.input(0)
    defer: input.close()
    check input.shape == initShape(1, 4)

  test "an unknown input name is reported by OpenVINO with the name":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    try:
      model.reshape("no-such-input", initPartialShape(initShape(2, 4)))
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "no-such-input" in err.msg

  test "a bad index, an empty or repeated batch and odd names are refused":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    let shape = initPartialShape(initShape(2, 4))
    expect OpenVinoArgumentError:
      model.reshape(1, shape)
    expect OpenVinoArgumentError:
      model.reshape(-1, shape)
    expect OpenVinoArgumentError:
      model.reshape(newSeq[(string, PartialShape)]())
    expect OpenVinoArgumentError:
      model.reshape([("input", shape), ("input", shape)])
    expect OpenVinoArgumentError:
      model.reshape("", shape)
    expect OpenVinoArgumentError:
      model.reshape("in\0put", shape)

  test "a batch reshape naming a missing input changes no input":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    defer: model.close()
    # The batch form is one OpenVINO call; OpenVINO resolves every name before
    # reshaping, so one bad name must leave the valid one untouched too.
    try:
      model.reshape([("input", initPartialShape(initShape(2, 4))),
                     ("missing", initPartialShape(initShape(2, 4)))])
      check false
    except OpenVinoError:
      discard
    let input = model.input(0)
    defer: input.close()
    check input.shape == initShape(1, 4)

  test "reshape on a closed model raises before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(staticPath)
    model.close()
    expect OpenVinoArgumentError:
      model.reshape(initPartialShape(initShape(2, 4)))
