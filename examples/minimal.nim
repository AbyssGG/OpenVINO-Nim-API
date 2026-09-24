# SPDX-License-Identifier: Apache-2.0

## The smallest complete program: compile a model for CPU, run it once, print
## the result.
##
## This is the same code the README shows. `tools/mdcheck.nim` compares the two,
## so the README cannot describe an API that does not exist any more: a README
## example that no longer compiles is worse than none, because it is what a
## reader tries first.
##
## Build and run:
##
## ```shell
## nim c -r --path:src examples/minimal.nim
## ```

import openvino

const modelPath = "tests/fixtures/relu_1x4_f32.xml"

proc main() =
  let core = newCore()
  defer: core.close()

  let compiled = core.compileModel(modelPath, "CPU")
  defer: compiled.close()

  let request = compiled.createInferRequest()
  defer: request.close()

  let input = tensorFrom(etF32, initShape(1, 4),
                         [float32(-1.5), 2.0, -0.25, 4.0])
  defer: input.close()

  request.setInputTensor(0, input)
  request.infer()

  let output = request.outputTensor(0)
  defer: output.close()
  echo output.toSeq(float32)

main()
