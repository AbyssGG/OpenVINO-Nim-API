# SPDX-License-Identifier: Apache-2.0

## Preprocessing: describe how your tensors differ from what the model wants,
## and let OpenVINO add the conversion to the model itself.
##
## The caller has 8-bit BGR images, height 2 and width 2, interleaved (NHWC).
## The model, `relu_1x3x4x4_f32.xml`, wants f32 RGB in NCHW at 4x4. One plan
## covers element type, color order, layout, size and normalisation.
##
## Build and run from the repository root:
##
## ```shell
## nim c -r --path:src examples/preprocess.nim
## ```

import openvino

const modelPath = "tests/fixtures/relu_1x3x4x4_f32.xml"

proc main() =
  let core = newCore()
  defer: core.close()

  # A plan is a plain value: it can be built, printed and reused without
  # touching OpenVINO. Only initLayout needs the runtime, to validate.
  var plan = initPreprocessPlan()
  plan.input(0)
    .tensorElementType(etU8)
    .tensorLayout(initLayout("NHWC"))
    .tensorColorFormat(cfBgr)
    .tensorSpatialStaticShape(2, 2)
    .convertElementType(etF32)
    .convertColor(cfRgb)
    .resize(raNearest)
    .mean([float32(10), 20, 30])
    .scale(2)
    .modelLayout(initLayout("NCHW"))
  echo "Plan: ", plan

  let source = core.readModel(modelPath)
  # applyPreprocessing modifies `source` as well, so close it straight away.
  let prepared = source.applyPreprocessing(plan)
  source.close()
  defer: prepared.close()
  let input = prepared.input(0)
  echo "Prepared model input: ", input.elementType, " ", input.shape
  input.close()

  let compiled = core.compileModel(prepared, "CPU")
  defer: compiled.close()
  let request = compiled.createInferRequest()
  defer: request.close()

  # One 2x2 BGR image: every pixel is (B, G, R) = (100, 150, 200).
  var pixels: seq[uint8] = @[]
  for pixel in 0 ..< 4:
    pixels.add([uint8(100), 150, 200])
  let image = tensorFrom(etU8, initShape(1, 2, 2, 3), pixels)
  defer: image.close()
  request.setInputTensor(0, image)
  request.infer()

  let output = request.outputTensor(0)
  defer: output.close()
  let values = output.toSeq(float32)
  # Channel 0 is now R: (200 - 10) / 2 = 95. G: (150 - 20) / 2 = 65.
  # B: (100 - 30) / 2 = 35. Nearest resize copies each pixel to a 2x2 block.
  echo "Output ", output.shape, ": R=", values[0], " G=", values[16],
    " B=", values[32]

when isMainModule:
  try:
    main()
  except OpenVinoLibraryError as err:
    echo "OpenVINO runtime not available."
    echo err.msg
    quit(1)
  except OpenVinoError as err:
    echo "OpenVINO failed during ", err.operation, "."
    echo err.msg
    quit(1)
