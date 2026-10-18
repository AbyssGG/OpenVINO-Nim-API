# SPDX-License-Identifier: Apache-2.0

## Layouts and preprocessing through the public API, with every step checked
## against a value computed here in Nim.
##
## The model is `relu_1x3x4x4_f32.xml`: input `[1, 3, 4, 4]` f32 in NCHW, and
## `output = max(0, input)`. Inputs are chosen non-negative wherever the step
## under test is not itself about signs, so the ReLU passes them through and
## the expected output is the reference transformation alone.
##
## Resize uses nearest-neighbour 2x upsampling, where OpenVINO's coordinate
## and rounding modes all agree on `source = destination div 2`; linear resize
## is checked only for shape and range.
##
## Run with `nimble testIntegration`.

import std/[os, strutils, unittest]

import openvino

const
  fixturePath = currentSourcePath().parentDir.parentDir / "fixtures" /
    "relu_1x3x4x4_f32.xml"
  device = "CPU"

proc nchw(c, h, w: int; height = 4; width = 4): int =
  (c * height + h) * width + w

proc run(core: Core; plan: PreprocessPlan; input: Tensor): seq[float32] =
  ## Applies `plan` to a fresh model, compiles it, infers `input`, and
  ## returns the f32 output.
  let source = core.readModel(fixturePath)
  let prepared = source.applyPreprocessing(plan)
  source.close()
  defer: prepared.close()
  let compiled = core.compileModel(prepared, device)
  defer: compiled.close()
  let request = compiled.createInferRequest()
  defer: request.close()
  request.setInputTensor(0, input)
  request.infer()
  let output = request.outputTensor(0)
  defer: output.close()
  check output.shape == initShape(1, 3, 4, 4)
  output.toSeq(float32)

proc ramp(count: int; start = 0.0'f32): seq[float32] =
  result = newSeq[float32](count)
  for index in 0 ..< count:
    result[index] = start + float32(index)

suite "layouts":
  test "layouts are validated and kept in OpenVINO's canonical form":
    check $initLayout("NCHW") == "[N,C,H,W]"
    check initLayout("nchw") == initLayout("[N,C,H,W]")
    check $initLayout("NC?") == "[N,C,?]"
    check $initLayout("...C") == "[...,C]"

  test "an invalid layout is reported with the description":
    try:
      discard initLayout("NCHWN")
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "NCHWN" in err.msg
    expect OpenVinoArgumentError:
      discard initLayout("NC\0HW")

suite "tensor description and element types":
  test "convertElementType: u8 input converted to the model's f32":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorElementType(etU8).convertElementType(etF32)
    var bytes = newSeq[uint8](48)
    for index in 0 ..< 48:
      bytes[index] = uint8(index * 5)
    let input = tensorFrom(etU8, initShape(1, 3, 4, 4), bytes)
    defer: input.close()
    var expected = newSeq[float32](48)
    for index in 0 ..< 48:
      expected[index] = float32(index * 5)
    check core.run(plan, input) == expected

  test "output element type: the f32 result read back as i32":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.output(0).tensorElementType(etI32)
    let source = core.readModel(fixturePath)
    let prepared = source.applyPreprocessing(plan)
    source.close()
    defer: prepared.close()
    let compiled = core.compileModel(prepared, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    var values = ramp(48, -10)
    let input = tensorFrom(etF32, initShape(1, 3, 4, 4), values)
    defer: input.close()
    request.setInputTensor(0, input)
    request.infer()
    let output = request.outputTensor(0)
    defer: output.close()
    check output.elementType == etI32
    var expected = newSeq[int32](48)
    for index in 0 ..< 48:
      expected[index] = int32(max(0'f32, values[index]))
    check output.toSeq(int32) == expected

  test "tensorFrom takes type and shape from a sample, which may be closed":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    block:
      let sample = newTensor(etU8, initShape(1, 3, 4, 4))
      plan.input(0).tensorFrom(sample).convertElementType(etF32)
      sample.close()
    let input = tensorFrom(etU8, initShape(1, 3, 4, 4), newSeq[uint8](48))
    defer: input.close()
    check core.run(plan, input) == newSeq[float32](48)

suite "steps":
  test "convertLayout: an NHWC tensor transposed to the model's NCHW":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NHWC"))
      .convertLayout(initLayout("NCHW")).modelLayout(initLayout("NCHW"))
    var values = newSeq[float32](48)
    for h in 0 ..< 4:
      for w in 0 ..< 4:
        for c in 0 ..< 3:
          values[(h * 4 + w) * 3 + c] = float32(h * 100 + w * 10 + c)
    let input = tensorFrom(etF32, initShape(1, 4, 4, 3), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          check output[nchw(c, h, w)] == float32(h * 100 + w * 10 + c)

  test "mean and scale, scalar and per channel":
    let core = newCore()
    defer: core.close()
    let channelMeans = [float32(1), 2, 3]
    let channelScales = [float32(1), 2, 4]
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NCHW"))
      .mean(0.5).mean(channelMeans).scale(2).scale(channelScales)
    let values = ramp(48, 4)
    let input = tensorFrom(etF32, initShape(1, 3, 4, 4), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          let index = nchw(c, h, w)
          let expected = max(0'f32, ((values[index] - 0.5'f32 -
            channelMeans[c]) / 2'f32) / channelScales[c])
          check abs(output[index] - expected) < 1e-5

  test "reverseChannels swaps the first and last channel":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NCHW")).reverseChannels()
    let values = ramp(48)
    let input = tensorFrom(etF32, initShape(1, 3, 4, 4), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          check output[nchw(c, h, w)] == values[nchw(2 - c, h, w)]

  test "convertColor: BGR NHWC input becomes RGB for the model":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NHWC")).tensorColorFormat(cfBgr)
      .convertColor(cfRgb).modelLayout(initLayout("NCHW"))
    var values = newSeq[float32](48)
    for h in 0 ..< 4:
      for w in 0 ..< 4:
        for c in 0 ..< 3:
          values[(h * 4 + w) * 3 + c] = float32(h * 100 + w * 10 + c)
    let input = tensorFrom(etF32, initShape(1, 4, 4, 3), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          check output[nchw(c, h, w)] == float32(h * 100 + w * 10 + (2 - c))

  test "resize nearest: a 2x2 tensor upsampled to the model's 4x4":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NCHW"))
      .tensorSpatialStaticShape(2, 2).resize(raNearest)
      .modelLayout(initLayout("NCHW"))
    let values = ramp(12, 1)
    let input = tensorFrom(etF32, initShape(1, 3, 2, 2), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          check output[nchw(c, h, w)] ==
            values[nchw(c, h div 2, w div 2, 2, 2)]

  test "resize linear: shape changes and values stay within each channel":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NCHW"))
      .tensorSpatialStaticShape(2, 2).resize(raLinear)
      .modelLayout(initLayout("NCHW"))
    let values = ramp(12, 1)
    let input = tensorFrom(etF32, initShape(1, 3, 2, 2), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      let low = values[nchw(c, 0, 0, 2, 2)]
      let high = values[nchw(c, 1, 1, 2, 2)]
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          let value = output[nchw(c, h, w)]
          check value >= low - 1e-4 and value <= high + 1e-4

  test "crop keeps the requested window of a larger tensor":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    let sample = newTensor(etF32, initShape(1, 3, 6, 6))
    plan.input(0).tensorFrom(sample)
      .crop([int32(0), 0, 1, 1], [int32(1), 3, 5, 5])
    sample.close()
    let values = ramp(108)
    let input = tensorFrom(etF32, initShape(1, 3, 6, 6), values)
    defer: input.close()
    let output = core.run(plan, input)
    for c in 0 ..< 3:
      for h in 0 ..< 4:
        for w in 0 ..< 4:
          check output[nchw(c, h, w)] == values[nchw(c, h + 1, w + 1, 6, 6)]

  test "pad with a constant and with edge values":
    let core = newCore()
    defer: core.close()
    let values = ramp(24, 1)
    let input = tensorFrom(etF32, initShape(1, 3, 2, 4), values)
    defer: input.close()
    for mode in [pmConstant, pmEdge]:
      var plan = initPreprocessPlan()
      let sample = newTensor(etF32, initShape(1, 3, 2, 4))
      plan.input(0).tensorFrom(sample)
        .pad([0, 0, 1, 0], [0, 0, 1, 0], 7, mode)
      sample.close()
      let output = core.run(plan, input)
      for c in 0 ..< 3:
        for w in 0 ..< 4:
          let top = output[nchw(c, 0, w)]
          let bottom = output[nchw(c, 3, w)]
          if mode == pmConstant:
            check top == 7 and bottom == 7
          else:
            check top == values[nchw(c, 0, w, 2, 4)]
            check bottom == values[nchw(c, 1, w, 2, 4)]
          for h in 1 .. 2:
            check output[nchw(c, h, w)] == values[nchw(c, h - 1, w, 2, 4)]

  test "a two-plane NV12 input becomes two model inputs named by sub-name":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorElementType(etU8)
      .tensorColorFormat(cfNv12TwoPlanes, ["y", "uv"])
      .convertElementType(etF32).convertColor(cfBgr)
      .modelLayout(initLayout("NCHW"))
    let source = core.readModel(fixturePath)
    let prepared = source.applyPreprocessing(plan)
    source.close()
    defer: prepared.close()
    check prepared.inputCount == 2
    var names: seq[string] = @[]
    for index in 0 ..< 2:
      let port = prepared.input(index)
      names.add(port.name)
      port.close()
    checkpoint("inputs: " & names.join(", "))
    check names == @["input/y", "input/uv"]

suite "plan semantics":
  test "the source model is modified and shares its graph with the result":
    let core = newCore()
    defer: core.close()
    let source = core.readModel(fixturePath)
    defer: source.close()
    var plan = initPreprocessPlan()
    plan.input("input").tensorElementType(etU8)
    let prepared = source.applyPreprocessing(plan)
    defer: prepared.close()
    for model in [source, prepared]:
      let port = model.input(0)
      check port.elementType == etU8
      port.close()

  test "one plan applies to several models":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorElementType(etU8).convertElementType(etF32)
    for round in 1 .. 2:
      let input = tensorFrom(etU8, initShape(1, 3, 4, 4), newSeq[uint8](48))
      check core.run(plan, input) == newSeq[float32](48)
      input.close()

suite "errors":
  test "a wrong channel count names the input in the message":
    let core = newCore()
    defer: core.close()
    var plan = initPreprocessPlan()
    plan.input(0).tensorLayout(initLayout("NCHW"))
      .mean([float32(1), 2, 3, 4])
    let source = core.readModel(fixturePath)
    defer: source.close()
    try:
      discard source.applyPreprocessing(plan)
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "input[0]" in err.msg

  test "an input that does not exist is located in the message":
    let core = newCore()
    defer: core.close()
    let source = core.readModel(fixturePath)
    defer: source.close()
    var byIndex = initPreprocessPlan()
    byIndex.input(5).tensorElementType(etU8)
    try:
      discard source.applyPreprocessing(byIndex)
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "input[5]" in err.msg
    var byName = initPreprocessPlan()
    byName.input("missing").tensorElementType(etU8)
    try:
      discard source.applyPreprocessing(byName)
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "missing" in err.msg

  test "applying to a closed model raises before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    let source = core.readModel(fixturePath)
    source.close()
    expect OpenVinoArgumentError:
      discard source.applyPreprocessing(initPreprocessPlan())

  test "a closed sample tensor is refused when it is described":
    let sample = newTensor(etF32, initShape(1, 3, 4, 4))
    sample.close()
    var plan = initPreprocessPlan()
    expect OpenVinoArgumentError:
      plan.input(0).tensorFrom(sample)
