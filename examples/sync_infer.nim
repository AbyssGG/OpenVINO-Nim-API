# SPDX-License-Identifier: Apache-2.0

## A complete synchronous inference: read, compile, bind, infer, verify.
##
## Every step is explicit. No device is chosen for you, no cache is enabled and
## nothing is written to disk. Substituting your own model means changing the
## path, the device and the input values.
##
## Build and run against the test fixture, whose output is `max(0, x)`:
##
## ```shell
## nim c -r --path:src examples/sync_infer.nim tests/fixtures/relu_1x4_f32.xml CPU
## ```

import std/[os, strutils]

import openvino

proc describePort(label: string; port: Port) =
  ## Prints one port's metadata. The port is closed by the caller.
  echo "  ", label, ": name=", port.name(), " type=", port.elementType(),
    " shape=", port.shape()

proc main() =
  if paramCount() < 2:
    echo "usage: sync_infer <model.xml> <device>"
    echo "example: sync_infer tests/fixtures/relu_1x4_f32.xml CPU"
    quit(1)

  let
    modelPath = paramStr(1)
    device = paramStr(2)
    inputValues = [float32(-1.5), 2.0, -0.25, 4.0]

  let core = newCore()
  defer: core.close()

  echo "Devices available: ", core.availableDevices().join(", ")
  echo "Compiling ", modelPath, " for ", device

  # Read and compile as separate steps so the model's metadata can be inspected
  # before committing to a device. Closing the model afterwards is safe: the
  # compiled model does not depend on it.
  let model = core.readModel(modelPath)
  echo "Model: ", model.friendlyName()
  echo "  inputs=", model.inputCount, " outputs=", model.outputCount,
    " dynamic=", model.isDynamic()

  let inputPort = model.input(0)
  describePort("input", inputPort)
  let declaredShape = inputPort.shape()
  let declaredType = inputPort.elementType()
  inputPort.close()

  let outputPort = model.output(0)
  describePort("output", outputPort)
  outputPort.close()

  let compiled = core.compileModel(model, device)
  model.close()
  defer: compiled.close()

  let request = compiled.createInferRequest()
  defer: request.close()

  if declaredType != etF32:
    echo "This example only fills an f32 input; the model declares ",
      declaredType, "."
    quit(1)
  if declaredShape.elementCount != inputValues.len:
    echo "The model wants ", declaredShape.elementCount,
      " elements but this example supplies ", inputValues.len, "."
    quit(1)

  # tensorFrom copies into OpenVINO-owned storage, so inputValues is not
  # borrowed once this returns.
  let input = tensorFrom(etF32, declaredShape, inputValues)
  defer: input.close()
  request.setInputTensor(0, input)

  echo ""
  echo "Input : ", @inputValues
  request.infer() # blocks until the inference completes

  let output = request.outputTensor(0)
  defer: output.close()
  let produced = output.toSeq(float32)
  echo "Output: ", produced
  echo "  element type=", output.elementType(), " shape=", output.shape(),
    " bytes=", output.byteSize

  # Verification, not decoration. An example that prints without checking cannot
  # tell a working deployment from a broken one.
  var expected = newSeq[float32](inputValues.len)
  for index, value in inputValues:
    expected[index] = max(float32(0.0), value)
  if produced == expected:
    echo ""
    echo "Verified: output matches max(0, x) for every element."
  else:
    echo ""
    echo "Unexpected output. Wanted ", expected, " for the ReLU fixture."
    echo "If you supplied your own model, this check does not apply to it."
    quit(1)

when isMainModule:
  try:
    main()
  except OpenVinoLibraryError as err:
    echo "OpenVINO runtime not available."
    echo err.msg
    quit(1)
  except OpenVinoArgumentError as err:
    echo "Invalid argument: ", err.msg
    quit(1)
  except OpenVinoError as err:
    echo "OpenVINO failed during ", err.operation, "."
    echo err.msg
    quit(1)
