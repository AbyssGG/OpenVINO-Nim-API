# SPDX-License-Identifier: Apache-2.0

## Per-node timings, and what they do and do not tell you.
##
## Profiling is a property, not a mode: `enableProfiling()` is passed to
## `compileModel` like any other property. There is deliberately no
## `compileModelWithProfiling`, because that would suggest profiling changes the
## kind of thing a compiled model is.
##
## Two things this example makes visible, both measured rather than assumed:
##
## 1. The CPU plugin returns a node list even when profiling was never
##    requested. An earlier version of the integration test asserted the
##    opposite and the plugin disproved it. So the presence of entries does not
##    prove that profiling is on; timings above zero do.
## 2. The node names are the plugin's, after its own graph transformations. They
##    are not the names in the IR file, and a fused node may account for several
##    of them. Matching these against the model's own node names is a mistake
##    this output is meant to prevent.
##
## Build and run:
##
## ```shell
## nim c -r --path:src examples/profiling.nim
## ```

import std/[algorithm, strutils]

import openvino

const
  modelPath = "tests/fixtures/relu_1x4_f32.xml"
  device = "CPU"
  inputValues = [float32(-1.5), 2.0, -0.25, 4.0]

proc runOnce(core: Core; profiled: bool): seq[ProfilingInfo] =
  ## Compiles, infers once and returns whatever timings the plugin reports.
  let properties =
    if profiled: @[enableProfiling()]
    else: newSeq[Property]()
  let compiled = core.compileModel(modelPath, device, properties)
  defer: compiled.close()

  let request = compiled.createInferRequest()
  defer: request.close()

  let input = tensorFrom(etF32, initShape(1, 4), inputValues)
  defer: input.close()
  request.setInputTensor(0, input)
  request.infer()

  # Read the output too, so that this is a complete inference rather than a
  # compile followed by a timing query.
  let output = request.outputTensor(0)
  defer: output.close()
  doAssert output.toSeq(float32) == @[float32(0.0), 2.0, 0.0, 4.0]

  result = request.profilingInfo()

proc report(title: string; entries: seq[ProfilingInfo]) =
  echo ""
  echo title
  echo "  entries: ", entries.len
  if entries.len == 0:
    echo "  the plugin reported nothing for this run"
    return

  var executed = 0
  var totalReal = 0'i64
  for entry in entries:
    if entry.status == psExecuted:
      inc executed
    totalReal += entry.realTimeMicroseconds
  echo "  executed nodes: ", executed, " of ", entries.len
  echo "  total real time: ", totalReal, " us"

  # Sorted by cost, because the only reason to read this list is to find what is
  # expensive. Insertion order is the plugin's, and means nothing to a caller.
  var ranked = entries
  ranked.sort(proc (a, b: ProfilingInfo): int =
    cmp(b.realTimeMicroseconds, a.realTimeMicroseconds))

  echo "  slowest nodes:"
  for index in 0 ..< min(5, ranked.len):
    let entry = ranked[index]
    echo "    ", align($entry.realTimeMicroseconds, 6), " us  ",
      alignLeft($entry.status, 10), " ", entry.nodeType, "  ", entry.nodeName
    if entry.executionType.len > 0:
      echo "            implementation: ", entry.executionType

proc main() =
  let core = newCore()
  defer: core.close()

  let devices = core.availableDevices()
  if device notin devices:
    echo "This example needs the ", device, " plugin. Devices found: ",
      devices.join(", ")
    quit(1)

  let without = runOnce(core, profiled = false)
  report("Without the profiling property", without)

  let with = runOnce(core, profiled = true)
  report("With enableProfiling()", with)

  echo ""
  echo "What the two runs show on this machine:"
  echo "  entries without the property: ", without.len
  echo "  entries with the property   : ", with.len
  echo "  A plugin is free to report nodes either way. Compare the times, not"
  echo "  the presence of the list."
  echo ""
  echo "The node names above are the plugin's own, after fusion and other"
  echo "graph transformations. Do not expect them to match the names in the IR:"
  echo "  IR nodes: input, relu, output"

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
