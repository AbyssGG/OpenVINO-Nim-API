# SPDX-License-Identifier: Apache-2.0

## Dynamic shapes: reading a partial shape, reshaping a model, and running one
## compiled model with several batch sizes.
##
## Uses the fixtures `relu_dyn_x4_f32.xml` (input `[?, 4]`) and
## `relu_1x4_f32.xml` (input `[1, 4]`), both computing `max(0, x)`.
##
## Build and run from the repository root:
##
## ```shell
## nim c -r --path:src examples/dynamic_shape.nim
## ```

import openvino

const
  dynamicPath = "tests/fixtures/relu_dyn_x4_f32.xml"
  staticPath = "tests/fixtures/relu_1x4_f32.xml"

proc inputFor(batch: int): seq[float32] =
  result = newSeq[float32](batch * 4)
  for index in 0 ..< result.len:
    result[index] = (if index mod 2 == 0: -1'f32 else: float32(index))

proc showPartialShapes(core: Core) =
  echo "Reading partial shapes"
  let model = core.readModel(dynamicPath)
  defer: model.close()
  let input = model.input(0)
  defer: input.close()
  let declared = input.partialShape
  echo "  input ", input.name, ": ", declared, " dynamic=", input.isDynamic
  # A dynamic port has no static Shape; partialShape is the way to read it.
  for dimension in declared.dims:
    echo "    ", dimension, " min=", dimension.minLength,
      " max=", dimension.maxLength
  echo "  accepts [3, 4]: ", declared.accepts(initShape(3, 4))
  echo "  accepts [3, 5]: ", declared.accepts(initShape(3, 5))

proc showDynamicInference(core: Core) =
  echo ""
  echo "One compiled model, several batch sizes"
  let compiled = core.compileModel(dynamicPath, "CPU")
  defer: compiled.close()
  let request = compiled.createInferRequest()
  defer: request.close()
  for batch in [1, 3, 7]:
    let tensor = tensorFrom(etF32, initShape(batch, 4), inputFor(batch))
    defer: tensor.close()
    request.setInputTensor(0, tensor)
    request.infer()
    # Fetch the output again after every inference: its shape follows the
    # input, so a tensor taken before this run may describe the old shape.
    let output = request.outputTensor(0)
    defer: output.close()
    echo "  batch ", batch, " -> output ", output.shape,
      " first row ", output.toSeq(float32)[0 ..< 4]

proc showReshape(core: Core) =
  echo ""
  echo "Reshaping a static model"
  let model = core.readModel(staticPath)
  defer: model.close()
  echo "  before: ", model.isDynamic
  # reshape modifies this Model in place. A CompiledModel built earlier keeps
  # the shape it was compiled with.
  model.reshape(initPartialShape([boundedDim(1, 8), staticDim(4)]))
  let input = model.input(0)
  defer: input.close()
  echo "  after : ", input.partialShape, " dynamic=", model.isDynamic

  # A scalar or a dynamic rank cannot be expressed through the OpenVINO 2026.4
  # C API, so the request is refused before it reaches OpenVINO.
  try:
    model.reshape(dynamicRankShape())
  except OpenVinoArgumentError as err:
    echo "  refused [...]: ", err.msg

proc main() =
  let core = newCore()
  defer: core.close()
  showPartialShapes(core)
  showDynamicInference(core)
  showReshape(core)

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
