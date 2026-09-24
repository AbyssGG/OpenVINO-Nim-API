# SPDX-License-Identifier: Apache-2.0

## A consumer of the *installed* package, compiled from outside the checkout.
##
## This file is deliberately not part of the test suite that runs against
## `--path:src`. It is compiled against an installed package with no access to
## the repository's `src`, which is what makes it able to catch a manifest that
## installs the wrong files, or a module that only resolves inside a checkout.
##
## `nimble packagingCheck` installs the package into a throwaway directory,
## copies this file somewhere else entirely, and compiles it there.
##
## Takes the model path as its only argument, because a consumer has no reason
## to know where this repository keeps its fixtures.

import std/os

import openvino

proc main() =
  if paramCount() < 1:
    echo "usage: consumer <model.xml>"
    quit(1)
  let modelPath = paramStr(1)

  echo "package : ", PackageName, " ", PackageVersion
  echo "targets : OpenVINO ", TargetOpenVinoVersion

  let version = runtimeVersion()
  echo "runtime : ", version.build
  echo "matches : ", version.isSupported()

  let core = newCore()
  defer: core.close()

  let devices = core.availableDevices()
  echo "devices : ", devices.len
  if "CPU" notin devices:
    echo "CPU plugin missing; the installed package loaded but no plugin did"
    quit(1)

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
  let produced = output.toSeq(float32)
  echo "output  : ", produced

  # The same hand-computed value the integration suite uses. A consumer that
  # compiles but infers wrongly is not a working package.
  if produced != @[float32(0.0), 2.0, 0.0, 4.0]:
    echo "WRONG OUTPUT: expected @[0.0, 2.0, 0.0, 4.0]"
    quit(1)
  echo "consumer OK"

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
