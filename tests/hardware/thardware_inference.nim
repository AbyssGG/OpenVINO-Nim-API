# SPDX-License-Identifier: Apache-2.0

## Hardware compatibility suite for GPU and NPU inference through the public
## managed API.
##
## Responsible for verifying that real GPU and NPU plugins on a hardware host
## can compile models, run synchronous inference, bind positional/named/in-place
## and external-buffer tensors, handle non-ASCII model paths, report profiling
## timings, round-trip compiled blobs, and survive repeated handle creation and
## release. Since 0.2.0 it also covers dynamic and bounded batches (recording
## plan item M-11 as `M-11` output lines), asynchronous inference through a
## `CompletionQueue`, and a preprocessing plan.
##
## Not responsible for CPU-only CI gating, which lives in
## `tests/integration/tcpu_inference.nim` so hosted runners without accelerator
## hardware remain deterministic.
##
## Run with `nimble testHardware`. By default both a GPU device and `NPU` must
## be present in `availableDevices()`; set `OPENVINO_TEST_DEVICES` to a
## comma-separated list (for example `GPU.0,NPU`) to target an explicit subset.

import std/[os, strutils, unittest]

import openvino

const
  fixtureDirectory = currentSourcePath().parentDir.parentDir / "fixtures"
  modelPath = fixtureDirectory / "relu_1x4_f32.xml"
  dynamicModelPath = fixtureDirectory / "relu_dyn_x4_f32.xml"
  boundedModelPath = fixtureDirectory / "relu_bounded_f32.xml"
  inputValues = [float32(-1.5), 2.0, -0.25, 4.0]
  expectedOutput = [float32(0.0), 2.0, 0.0, 4.0]

proc targetHardwareDevices(discovered: seq[string]): seq[string] =
  ## Resolves the hardware device list to exercise.
  ##
  ## Honours `OPENVINO_TEST_DEVICES` when set; otherwise selects the generic
  ## `GPU` alias, every numbered `GPU.*` target reported by the runtime, and
  ## `NPU`.
  let configured = getEnv("OPENVINO_TEST_DEVICES").strip()
  if configured.len > 0:
    result = @[]
    for item in configured.split(','):
      let name = item.strip()
      if name.len > 0:
        result.add(name)
    return

  result = @[]
  var sawGpu = false
  for candidate in discovered:
    if candidate == "GPU" or candidate.startsWith("GPU."):
      if not sawGpu:
        result.add("GPU")
        sawGpu = true
      if candidate != "GPU":
        result.add(candidate)
  if "NPU" in discovered:
    result.add("NPU")

proc sanitizeDeviceTag(device: string): string =
  ## Converts a device identifier such as `GPU.0` into a file-system-safe tag.
  result = newStringOfCap(device.len)
  for character in device:
    if character in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '-', '_'}:
      result.add(character)
    else:
      result.add('_')

suite "hardware device discovery":
  test "GPU and NPU plugins are discovered by the runtime":
    let core = newCore()
    defer: core.close()
    let discovered = core.availableDevices()
    checkpoint("discovered devices: " & discovered.join(", "))
    let configured = getEnv("OPENVINO_TEST_DEVICES").strip()
    if configured.len == 0:
      var hasGpu = false
      for candidate in discovered:
        if candidate == "GPU" or candidate.startsWith("GPU."):
          hasGpu = true
          break
      check hasGpu
      check "NPU" in discovered
    let targets = targetHardwareDevices(discovered)
    checkpoint("target hardware devices: " & targets.join(", "))
    check targets.len > 0

proc runDeviceSuite(targetDevice: string) =
  ## Runs the full synchronous inference contract on `targetDevice`.
  suite "hardware compatibility (" & targetDevice & ")":
    test "reports a non-empty full device name":
      let core = newCore()
      defer: core.close()
      let fullName = core.getProperty(targetDevice, "FULL_DEVICE_NAME")
      checkpoint(targetDevice & " FULL_DEVICE_NAME=" & fullName)
      check fullName.len > 0

    test "compiles from a Model and from a file path":
      let core = newCore()
      defer: core.close()
      let model = core.readModel(modelPath)
      let fromModel = core.compileModel(model, targetDevice)
      model.close()
      defer: fromModel.close()
      check fromModel.inputCount == 1
      check fromModel.outputCount == 1

      let fromPath = core.compileModel(modelPath, targetDevice)
      defer: fromPath.close()
      let port = fromPath.input(0)
      defer: port.close()
      check port.elementType() == etF32
      check port.shape() == initShape(1, 4)

    test "runs synchronous ReLU inference with positional input":
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      let request = compiled.createInferRequest()
      defer: request.close()
      let input = tensorFrom(etF32, initShape(1, 4), inputValues)
      defer: input.close()
      request.setInputTensor(0, input)
      request.infer()
      let output = request.outputTensor(0)
      defer: output.close()
      check output.elementType() == etF32
      check output.shape() == initShape(1, 4)
      check output.toSeq(float32) == @expectedOutput

    test "runs synchronous ReLU inference with named input":
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      let request = compiled.createInferRequest()
      defer: request.close()
      let input = tensorFrom(etF32, initShape(1, 4), inputValues)
      defer: input.close()
      request.setInputTensor("input", input)
      request.infer()
      let output = request.outputTensor(0)
      defer: output.close()
      check output.toSeq(float32) == @expectedOutput

    test "runs synchronous ReLU inference through the request input tensor":
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      let request = compiled.createInferRequest()
      defer: request.close()
      let input = request.inputTensor(0)
      defer: input.close()
      input.copyFrom(inputValues)
      request.infer()
      let output = request.outputTensor(0)
      defer: output.close()
      check output.toSeq(float32) == @expectedOutput

    test "infers from a caller-owned buffer without freeing it on close":
      let elements = 4
      let buffer = cast[ptr UncheckedArray[float32]](
        allocShared0(elements * sizeof(float32)))
      defer: deallocShared(buffer)
      for index in 0 ..< elements:
        buffer[index] = inputValues[index]

      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      let request = compiled.createInferRequest()
      let input = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
      request.setInputTensor(0, input)
      request.infer()
      let output = request.outputTensor(0)
      check output.toSeq(float32) == @expectedOutput
      output.close()
      input.close()
      request.close()
      buffer[1] = 2.0
      check buffer[1] == 2.0

    test "a hundred inferences on one request produce identical outputs":
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      let request = compiled.createInferRequest()
      defer: request.close()
      let input = tensorFrom(etF32, initShape(1, 4), inputValues)
      defer: input.close()
      request.setInputTensor(0, input)
      var mismatches = 0
      for iteration in 1 .. 100:
        request.infer()
        let output = request.outputTensor(0)
        if output.toSeq(float32) != @expectedOutput:
          inc mismatches
        output.close()
      check mismatches == 0

    test "two hundred requests can be created, inferred and released":
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      var mismatches = 0
      for iteration in 1 .. 200:
        let request = compiled.createInferRequest()
        let input = tensorFrom(etF32, initShape(1, 4), inputValues)
        request.setInputTensor(0, input)
        request.infer()
        let output = request.outputTensor(0)
        if output.toSeq(float32) != @expectedOutput:
          inc mismatches
        output.close()
        input.close()
        request.close()
      check mismatches == 0

    test "compiles and infers from a non-ASCII model path":
      let directory = getTempDir() /
        ("openvino-nim-模型-тест-" & sanitizeDeviceTag(targetDevice))
      removeDir(directory)
      createDir(directory)
      let nonAsciiPath = directory / "релу_模型.xml"
      copyFile(modelPath, nonAsciiPath)
      try:
        let core = newCore()
        defer: core.close()
        let compiled = core.compileModel(nonAsciiPath, targetDevice)
        defer: compiled.close()
        let request = compiled.createInferRequest()
        defer: request.close()
        let input = tensorFrom(etF32, initShape(1, 4), inputValues)
        defer: input.close()
        request.setInputTensor(0, input)
        request.infer()
        let output = request.outputTensor(0)
        defer: output.close()
        check output.toSeq(float32) == @expectedOutput
      finally:
        removeDir(directory)

    test "records unprofiled behaviour and yields timed nodes when enabled":
      let core = newCore()
      defer: core.close()
      let input = tensorFrom(etF32, initShape(1, 4), inputValues)
      defer: input.close()

      # Without `enableProfiling()`, plugins legitimately differ: the Intel GPU
      # plugin raises `OpenVinoError`, the NPU plugin returns an empty list, and
      # the CPU plugin returns untimed entries. Either outcome is valid under
      # `infer_request.profilingInfo`'s contract.
      let unprofiled = core.compileModel(modelPath, targetDevice)
      defer: unprofiled.close()
      let unprofiledReq = unprofiled.createInferRequest()
      defer: unprofiledReq.close()
      unprofiledReq.setInputTensor(0, input)
      unprofiledReq.infer()
      try:
        let entriesOff = unprofiledReq.profilingInfo()
        checkpoint(targetDevice & " profiling off entries=" & $entriesOff.len)
        check entriesOff.len >= 0
      except OpenVinoError as err:
        checkpoint(targetDevice & " profiling off raised OpenVinoError: " &
          err.statusInfo)
        check err.statusInfo.len > 0

      let profiled = core.compileModel(modelPath, targetDevice,
                                       [enableProfiling()])
      defer: profiled.close()
      let profiledReq = profiled.createInferRequest()
      defer: profiledReq.close()
      profiledReq.setInputTensor(0, input)
      profiledReq.infer()
      let entriesOn = profiledReq.profilingInfo()
      checkpoint(targetDevice & " profiling on entries=" & $entriesOn.len)
      check entriesOn.len > 0
      var executed = 0
      for entry in entriesOn:
        if entry.status == psExecuted:
          inc executed
        check entry.nodeName.len > 0
      checkpoint(targetDevice & " executed nodes=" & $executed)
      check executed > 0

    test "round-trips a compiled model through an explicit blob":
      let blobPath = getTempDir() /
        ("openvino-nim-relu-" & sanitizeDeviceTag(targetDevice) & ".blob")
      removeFile(blobPath)
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      compiled.exportTo(blobPath)
      compiled.close()
      check fileExists(blobPath)

      let blob = readFile(blobPath)
      checkpoint(targetDevice & " exported blob bytes=" & $blob.len)
      check blob.len > 0
      let imported = core.importModel(blob, targetDevice)
      defer:
        imported.close()
        removeFile(blobPath)

      let request = imported.createInferRequest()
      defer: request.close()
      let input = tensorFrom(etF32, initShape(1, 4), inputValues)
      defer: input.close()
      request.setInputTensor(0, input)
      request.infer()
      let output = request.outputTensor(0)
      defer: output.close()
      check output.toSeq(float32) == @expectedOutput

    # 0.2.0: dynamic shapes, asynchronous inference and preprocessing. Whether
    # a plugin compiles an unbounded or bounded dynamic model is a property of
    # the plugin, not of this package (plan item M-11), so the outcome is
    # printed as a `M-11` line for docs/compatibility.md, and a plugin that
    # refuses must still accept the same model reshaped to a static shape.
    for (label, path) in [("unbounded [?, 4]", dynamicModelPath),
                          ("bounded [1..8, 4]", boundedModelPath)]:
      test "dynamic batch " & label & ", or its static reshape":
        let core = newCore()
        defer: core.close()
        var compiled: CompiledModel
        var dynamicWorks = true
        try:
          compiled = core.compileModel(path, targetDevice)
        except OpenVinoError as err:
          dynamicWorks = false
          echo "M-11 ", targetDevice, " ", label, ": compile refused (",
            err.statusInfo, ")"
          let model = core.readModel(path)
          model.reshape(initPartialShape(initShape(3, 4)))
          compiled = core.compileModel(model, targetDevice)
          model.close()
        defer: compiled.close()
        let request = compiled.createInferRequest()
        defer: request.close()
        let batches = (if dynamicWorks: @[1, 3, 7] else: @[3])
        var correct = true
        for batch in batches:
          var values = newSeq[float32](batch * 4)
          for index in 0 ..< values.len:
            values[index] = inputValues[index mod 4]
          let input = tensorFrom(etF32, initShape(batch, 4), values)
          request.setInputTensor(0, input)
          request.infer()
          let output = request.outputTensor(0)
          if output.shape != initShape(batch, 4):
            correct = false
          let produced = output.toSeq(float32)
          for index in 0 ..< produced.len:
            if produced[index] != expectedOutput[index mod 4]:
              correct = false
          output.close()
          input.close()
        if dynamicWorks:
          echo "M-11 ", targetDevice, " ", label,
            ": compiled and inferred batches ", batches, ", correct=", correct
        else:
          echo "M-11 ", targetDevice, " ", label,
            ": static reshape [3, 4] inferred, correct=", correct
        check correct

    test "asynchronous inference through a completion queue":
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(modelPath, targetDevice)
      defer: compiled.close()
      let queue = newCompletionQueue(capacity = 2)
      defer: queue.close()
      var requests: seq[InferRequest] = @[]
      defer:
        for request in requests:
          request.close()
      let input = tensorFrom(etF32, initShape(1, 4), inputValues)
      defer: input.close()
      for id in 0 ..< 2:
        let request = compiled.createInferRequest()
        requests.add(request)
        queue.attach(request, id)
        request.setInputTensor(0, input)
        request.startAsync()
      var completed = 0
      var mismatches = 0
      while completed < 100:
        let finished = queue.next(initDuration(seconds = 30))
        check finished.isSome
        if finished.isNone:
          break
        let request = requests[finished.get]
        request.wait()
        let output = request.outputTensor(0)
        if output.toSeq(float32) != @expectedOutput:
          inc mismatches
        output.close()
        inc completed
        if completed + 2 <= 100:
          request.startAsync()
      check completed == 100
      check mismatches == 0
      # Cancelling may or may not catch such a short run, and some plugins
      # (the Intel NPU plugin in 2026.4) do not support cancellation at all and
      # report it as an OpenVinoError. Either way the request must remain
      # usable once waited for.
      requests[0].startAsync()
      var cancelSupported = true
      try:
        requests[0].cancel()
      except OpenVinoError as err:
        cancelSupported = false
        echo "CANCEL ", targetDevice, ": not supported (", err.statusInfo, ")"
      try:
        requests[0].wait()
      except OpenVinoCancelledError:
        discard
      check requests[0].waitFor(initDuration(seconds = 30))
      # Closing a running request must be safe even where cancellation is not
      # supported: the release path waits instead.
      requests[1].startAsync()
      requests[1].close()
      check requests[1].isClosed
      echo "ASYNC ", targetDevice, ": 100 completions through a queue, ",
        "mismatches=", mismatches, ", cancel supported=", cancelSupported

    test "a preprocessing plan converts u8 input on the device":
      let core = newCore()
      defer: core.close()
      var plan = initPreprocessPlan()
      plan.input(0).tensorElementType(etU8).convertElementType(etF32)
      let source = core.readModel(modelPath)
      let prepared = source.applyPreprocessing(plan)
      source.close()
      defer: prepared.close()
      let compiled = core.compileModel(prepared, targetDevice)
      defer: compiled.close()
      let request = compiled.createInferRequest()
      defer: request.close()
      let input = tensorFrom(etU8, initShape(1, 4), [uint8(0), 7, 128, 255])
      defer: input.close()
      request.setInputTensor(0, input)
      request.infer()
      let output = request.outputTensor(0)
      defer: output.close()
      check output.toSeq(float32) == @[float32(0), 7, 128, 255]

proc main() =
  let core = newCore()
  let discovered = core.availableDevices()
  core.close()
  for targetDevice in targetHardwareDevices(discovered):
    runDeviceSuite(targetDevice)

main()
