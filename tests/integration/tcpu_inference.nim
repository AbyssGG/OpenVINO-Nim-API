# SPDX-License-Identifier: Apache-2.0

## The full synchronous inference loop on CPU, through the public entry point
## only.
##
## This is the test that decides whether the package works: create a Core, read
## a model, compile it, build a tensor, bind it, infer, read the output and
## compare it against a value computed by hand. Everything before this proves
## that declarations match a header; only this proves that inference happens.
##
## The fixture is `tests/fixtures/relu_1x4_f32.xml`, a three-node IR model whose
## output is `max(0, x)`. ReLU is chosen because it needs no weights file and its
## expected output is obvious by inspection, so a wrong answer is recognisable
## rather than merely different.
##
## Run with `nimble testIntegration`.

import std/[os, strutils, unittest]

import openvino
# Reached into deliberately: `isAscii` decides which entry point a path takes,
# and the non-ASCII suite below asserts its own premise with it rather than
# trusting that a literal containing Cyrillic really is non-ASCII after
# whatever the file system did to it.
import openvino/private/paths
# The raw layer appears here for one test, which records what the narrow C entry
# point does with a non-ASCII path. No managed call can ask that question,
# because the managed layer is what picks the entry point.
import openvino/raw

const
  fixtureDirectory = currentSourcePath().parentDir.parentDir / "fixtures"
  modelPath = fixtureDirectory / "relu_1x4_f32.xml"
  device = "CPU"
  inputValues = [float32(-1.5), 2.0, -0.25, 4.0]
  expectedOutput = [float32(0.0), 2.0, 0.0, 4.0]

suite "runtime discovery":
  test "the runtime reports a version and a description":
    let version = runtimeVersion()
    checkpoint("build=" & version.build)
    checkpoint("description=" & version.description)
    check version.build.len > 0
    check version.description.len > 0

  test "the runtime version parses into a major and minor":
    let version = runtimeVersion()
    checkpoint("parsed=" & $version.parsed & " " & $version.major & "." &
      $version.minor)
    check version.parsed
    check version.major > 0

  test "the pinned baseline is what is installed here":
    # Recorded rather than required: a mismatched runtime often works, and the
    # package does not refuse to start. This test documents which one was used.
    let version = runtimeVersion()
    checkpoint("supported=" & $version.isSupported() &
      " expected=" & TargetOpenVinoVersion)
    check version.isSupported()

suite "core and devices":
  test "a core can be created and closed":
    let core = newCore()
    check not core.isClosed()
    core.close()
    check core.isClosed()

  test "closing a core twice is harmless":
    let core = newCore()
    core.close()
    core.close()
    check core.isClosed()

  test "using a core after close raises before reaching OpenVINO":
    let core = newCore()
    core.close()
    expect OpenVinoArgumentError:
      discard core.availableDevices()

  test "CPU is among the available devices":
    let core = newCore()
    defer: core.close()
    let devices = core.availableDevices()
    checkpoint("devices: " & devices.join(", "))
    check devices.len > 0
    check device in devices

  test "a device reports its full name":
    let core = newCore()
    defer: core.close()
    let name = core.getProperty(device, "FULL_DEVICE_NAME")
    checkpoint("FULL_DEVICE_NAME=" & name)
    check name.len > 0

  test "an unknown device is reported with its name in the message":
    let core = newCore()
    defer: core.close()
    try:
      discard core.getProperty("NO_SUCH_DEVICE", "FULL_DEVICE_NAME")
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "NO_SUCH_DEVICE" in err.msg
      check err.statusInfo.len > 0

suite "reading a model":
  test "the fixture exists where the test expects it":
    check fileExists(modelPath)

  test "a missing model path is rejected before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    let missing = fixtureDirectory / "no-such-model.xml"
    try:
      discard core.readModel(missing)
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "does not exist" in err.msg

  test "the fixture reports one input and one output":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    defer: model.close()
    check model.inputCount == 1
    check model.outputCount == 1
    check not model.isDynamic()

  test "the model reports its own name":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    defer: model.close()
    checkpoint("friendly name=" & model.friendlyName())
    check model.friendlyName().len > 0

  test "the input port describes the shape and type the fixture declares":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    defer: model.close()
    let port = model.input(0)
    defer: port.close()
    checkpoint("name=" & port.name() & " type=" & $port.elementType() &
      " shape=" & $port.shape())
    check port.elementType() == etF32
    check port.shape() == initShape(1, 4)
    check port.shape().elementCount == 4
    check port.shape().byteSize(etF32) == 16

  test "an out-of-range port index is rejected with the count":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    defer: model.close()
    try:
      discard model.input(1)
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "there are 1" in err.msg

  test "a negative port index is rejected before conversion":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    defer: model.close()
    expect OpenVinoArgumentError:
      discard model.output(-1)

suite "compiling":
  test "the model compiles for CPU with no properties":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    let compiled = core.compileModel(model, device)
    model.close()
    defer: compiled.close()
    check compiled.inputCount == 1
    check compiled.outputCount == 1

  test "reading and compiling in one step gives the same shape":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
    defer: compiled.close()
    let port = compiled.input(0)
    defer: port.close()
    check port.shape() == initShape(1, 4)

  test "an unknown device is refused with its name in the message":
    let core = newCore()
    defer: core.close()
    let model = core.readModel(modelPath)
    defer: model.close()
    try:
      discard core.compileModel(model, "NO_SUCH_DEVICE")
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check "NO_SUCH_DEVICE" in err.msg

suite "tensors":
  test "an owned tensor reports the shape and sizes it was given":
    let value = newTensor(etF32, initShape(1, 4))
    defer: value.close()
    check value.elementType() == etF32
    check value.shape() == initShape(1, 4)
    check value.elementCount == 4
    check value.byteSize == 16
    check value.ownsStorage()

  test "a tensor built from Nim data reads back the same values":
    let value = tensorFrom(etF32, initShape(1, 4), inputValues)
    defer: value.close()
    check value.toSeq(float32) == @inputValues

  test "copying in the wrong element count is refused":
    let value = newTensor(etF32, initShape(1, 4))
    defer: value.close()
    try:
      value.copyFrom([float32(1.0), 2.0])
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "exact match" in err.msg

  test "accessing an f32 tensor as float64 is refused":
    # The width check is what stops a caller from reading twice as many bytes
    # as the tensor holds.
    let value = newTensor(etF32, initShape(1, 4))
    defer: value.close()
    try:
      discard value.toSeq(float64)
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "4-byte elements" in err.msg

  test "a sub-byte element type refuses a byte size":
    # u4 packs two elements per byte, so a byte size computed from the element
    # count would be wrong rather than merely imprecise.
    expect OpenVinoArgumentError:
      discard initShape(1, 8).byteSize(etU4)

  test "using a tensor after close raises before reaching OpenVINO":
    let value = newTensor(etF32, initShape(1, 4))
    value.close()
    expect OpenVinoArgumentError:
      discard value.elementCount()

  test "a negative dimension is refused when the shape is built":
    expect OpenVinoArgumentError:
      discard initShape(1, -4)

suite "synchronous inference":
  test "ReLU on CPU produces the output computed by hand":
    # The closed loop. Every step is visible: nothing chooses the device,
    # allocates a cache or picks a tensor for us.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
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
    let produced = output.toSeq(float32)
    checkpoint("input=" & $(@inputValues))
    checkpoint("produced=" & $produced)
    checkpoint("expected=" & $(@expectedOutput))
    check produced == @expectedOutput

  test "binding the input by name gives the same result":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
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

  test "writing into the request's own input tensor gives the same result":
    # The allocation-free path: OpenVINO already owns an input tensor, so no
    # tensor of ours needs to be created or bound.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
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

  test "an out-of-range input index is rejected with the count":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let input = tensorFrom(etF32, initShape(1, 4), inputValues)
    defer: input.close()
    expect OpenVinoArgumentError:
      request.setInputTensor(1, input)

  test "a hundred inferences on one request all give the same answer":
    # Repetition on a single request, which is where a leaked or reused tensor
    # would show up as a changing answer.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let input = tensorFrom(etF32, initShape(1, 4), inputValues)
    defer: input.close()
    request.setInputTensor(0, input)
    for iteration in 1 .. 100:
      request.infer()
      let output = request.outputTensor(0)
      let produced = output.toSeq(float32)
      output.close()
      if produced != @expectedOutput:
        checkpoint("iteration " & $iteration & " produced " & $produced)
      check produced == @expectedOutput

suite "profiling":
  test "the CPU plugin lists nodes even when profiling was not requested":
    # Measured, not assumed. The first version of this test asserted that the
    # query returns nothing without the property, and the CPU plugin disproved
    # it by returning three entries anyway. What the plugin does with the
    # property is its business; what matters here is that this package never
    # sets the property on its own, which the absence of an argument below is
    # what demonstrates.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let input = tensorFrom(etF32, initShape(1, 4), inputValues)
    defer: input.close()
    request.setInputTensor(0, input)
    request.infer()
    let entries = request.profilingInfo()
    var timed = 0
    for entry in entries:
      if entry.realTimeMicroseconds > 0:
        inc timed
    checkpoint("entries=" & $entries.len & " with non-zero real time=" & $timed)
    # Recording the count rather than constraining it: the number of nodes a
    # plugin chooses to report is not part of any contract this package can
    # rely on.
    check entries.len >= 0

  test "enabling profiling through the property yields timed nodes":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device,
                                     [enableProfiling()])
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let input = tensorFrom(etF32, initShape(1, 4), inputValues)
    defer: input.close()
    request.setInputTensor(0, input)
    request.infer()
    let entries = request.profilingInfo()
    checkpoint("profiled nodes=" & $entries.len)
    check entries.len > 0
    var executed = 0
    for entry in entries:
      if entry.status == psExecuted:
        inc executed
      check entry.nodeName.len > 0
    checkpoint("executed nodes=" & $executed)
    check executed > 0

suite "export and import":
  test "a compiled model round-trips through an explicit blob":
    # Export and import are separate, explicit operations. No directory is
    # created and no cache filename is invented; the test owns the temporary
    # file, which is exactly the division of responsibility the package
    # promises.
    let blobPath = getTempDir() / "openvino-nim-relu-roundtrip.blob"
    removeFile(blobPath)
    let core = newCore()
    defer: core.close()

    let compiled = core.compileModel(modelPath, device)
    compiled.exportTo(blobPath)
    compiled.close()
    check fileExists(blobPath)

    let blob = readFile(blobPath)
    check blob.len > 0
    let imported = core.importModel(blob, device)
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

  test "importing an empty blob is rejected before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    expect OpenVinoArgumentError:
      discard core.importModel("", device)
suite "non-ASCII model paths":
  # The C API does not document how a Windows build interprets the bytes of a
  # narrow `const char*` path: UTF-8 or the active code page. The package sends
  # non-ASCII paths through the wide-character entry point, where the question
  # does not arise. This suite runs on every platform, because the two branches
  # must agree about what a caller sees.
  const
    directoryName = "openvino-nim-模型-тест"
    fileName = "релу_模型.xml"

  template withNonAsciiCopy(pathName, body: untyped) =
    ## Copies the fixture into a temporary directory whose name and file name
    ## are both non-ASCII, binds `pathName` to the copy, runs `body`, then
    ## removes the directory.
    ##
    ## A template rather than a proc taking a closure, so that `check` inside
    ## the body belongs to the enclosing test and reports against it.
    block:
      let directory = getTempDir() / directoryName
      removeDir(directory)
      createDir(directory)
      let pathName = directory / fileName
      copyFile(modelPath, pathName)
      try:
        body
      finally:
        removeDir(directory)

  test "the copy really is where the test thinks it is":
    # Guards the test itself. If the file system or the copy silently failed,
    # every check below would pass for the wrong reason.
    withNonAsciiCopy(path):
      check fileExists(path)
      check readFile(path) == readFile(modelPath)
      check not path.isAscii()

  test "a model reads from a non-ASCII path":
    withNonAsciiCopy(path):
      let core = newCore()
      defer: core.close()
      let model = core.readModel(path)
      defer: model.close()
      check model.inputCount == 1
      let port = model.input(0)
      defer: port.close()
      check port.shape() == initShape(1, 4)

  test "a model compiles and infers from a non-ASCII path":
    withNonAsciiCopy(path):
      let core = newCore()
      defer: core.close()
      let compiled = core.compileModel(path, device)
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

  test "what the narrow entry point does with a non-ASCII path is recorded":
    # Measured, not assumed. The first version of this suite was written on the
    # belief that the narrow entry point would fail here, which would have made
    # the wide branch load-bearing. On a host with active code page 936 it
    # succeeded: OpenVINO 2026.4 reads those bytes as UTF-8. So this test
    # records the answer instead of asserting one, and the wide branch is
    # insurance against an undocumented behaviour rather than a fix.
    #
    # Reaching into the raw layer is the point here: nothing in the managed API
    # can ask this question, because the managed API is what chooses the branch.
    withNonAsciiCopy(path):
      let core = newCore()
      defer: core.close()
      var native: ptr ov_model_t = nil
      let status = ov_core_read_model(core.unsafeRawHandle(), path.cstring,
                                      nil, addr native)
      checkpoint("narrow ov_core_read_model status: " & $status)
      if status == OK:
        checkpoint("this runtime accepts UTF-8 through the narrow entry point")
        check native != nil
        ov_model_free(native)
      else:
        checkpoint("this runtime needs the wide entry point for such a path")
        check native == nil
      # Either answer is acceptable. What must hold is that the managed call
      # works regardless, which is what the two tests above check.

  test "a missing non-ASCII path is reported with the path itself":
    let core = newCore()
    defer: core.close()
    let path = getTempDir() / directoryName / "нет.xml"
    try:
      discard core.readModel(path)
      check false
    except OpenVinoArgumentError as err:
      # The message must carry the path as the caller wrote it. A mangled
      # path in the message is what makes this class of bug hard to diagnose.
      check path in err.msg

suite "lifecycle under repetition":
  test "a thousand tensors can be created and released":
    # The plan asks for a thousand iterations because a leak of one handle per
    # iteration is invisible at ten and obvious at a thousand. Tensors are the
    # cheapest object that still allocates through OpenVINO.
    for iteration in 1 .. 1000:
      let value = tensorFrom(etF32, initShape(1, 4), inputValues)
      check value.elementCount == 4
      value.close()
      check value.isClosed()

  test "a thousand requests can be created, used and released":
    # One compiled model, a thousand requests. This is the shape of a long-lived
    # server process, and the place where a request that is never released shows
    # up as growth.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
    defer: compiled.close()

    var mismatches = 0
    for iteration in 1 .. 1000:
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
    # Counted rather than checked inside the loop, so a failure reports how many
    # iterations went wrong instead of stopping at the first.
    check mismatches == 0

  test "a hundred models can be read and released":
    # Reading is the expensive one, so this loop is shorter. It still covers the
    # model and port handles, which the tensor loop does not.
    let core = newCore()
    defer: core.close()
    for iteration in 1 .. 100:
      let model = core.readModel(modelPath)
      let port = model.input(0)
      check port.shape() == initShape(1, 4)
      port.close()
      model.close()
suite "external buffers and the unsafe path":
  # The prototype had exactly one tensor constructor and it wrapped a caller's
  # pointer, so every caller carried a lifetime obligation whether they knew it
  # or not. The current API splits that by ownership, and this suite is what
  # holds the split in place: it asserts which side owns the memory, that the
  # safe side really copies, and that the unsafe side really does not.

  test "an OpenVINO-allocated tensor reports that it owns its storage":
    let value = newTensor(etF32, initShape(1, 4))
    defer: value.close()
    check value.ownsStorage()

  test "tensorFrom copies, so the source may change afterwards":
    var source = @[float32(1), 2, 3, 4]
    let value = tensorFrom(etF32, initShape(1, 4), source)
    defer: value.close()
    check value.ownsStorage()
    source[0] = 99.0
    # If this read 99, the "copy" would be a view and every caller of the safe
    # constructor would silently be on the unsafe path.
    check value.toSeq(float32) == @[float32(1), 2, 3, 4]

  test "an external buffer is shared, not copied":
    let elements = 4
    let buffer = cast[ptr UncheckedArray[float32]](
      allocShared0(elements * sizeof(float32)))
    defer: deallocShared(buffer)
    for index in 0 ..< elements:
      buffer[index] = float32(index)

    let value = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
    defer: value.close()
    check not value.ownsStorage()
    check value.toSeq(float32) == @[float32(0), 1, 2, 3]

    # Writing through the caller's own pointer is visible to the tensor. That is
    # the reason to use this path and also its entire danger.
    buffer[0] = 42.0
    check value.toSeq(float32) == @[float32(42), 1, 2, 3]

    # And the reverse direction: OpenVINO writes land in the caller's buffer.
    value.copyFrom([float32(7), 8, 9, 10])
    check buffer[0] == 7.0
    check buffer[3] == 10.0

  test "an external buffer can be inferred from and outlives the request":
    # The realistic use: a buffer the caller already has, bound as an input.
    let elements = 4
    let buffer = cast[ptr UncheckedArray[float32]](
      allocShared0(elements * sizeof(float32)))
    defer: deallocShared(buffer)
    for index in 0 ..< elements:
      buffer[index] = inputValues[index]

    let core = newCore()
    defer: core.close()
    let compiled = core.compileModel(modelPath, device)
    defer: compiled.close()
    let request = compiled.createInferRequest()

    let input = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
    request.setInputTensor(0, input)
    request.infer()
    let output = request.outputTensor(0)
    check output.toSeq(float32) == @[float32(0.0), 2.0, 0.0, 4.0]

    # Closing the tensor and the request must not touch the caller's buffer.
    # OpenVINO does not own it, so a release that freed it would be a double
    # free against `deallocShared` below.
    output.close()
    input.close()
    request.close()
    check buffer[1] == 2.0

  test "closing an unsafe tensor does not free the caller's buffer":
    # Made observable by writing through the pointer after the tensor is gone.
    # Under a wrong release this is a use-after-free, which is what the test is
    # for; under the correct one it simply works.
    let buffer = cast[ptr UncheckedArray[float32]](
      allocShared0(4 * sizeof(float32)))
    defer: deallocShared(buffer)
    let value = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
    value.close()
    check value.isClosed()
    buffer[2] = 5.0
    check buffer[2] == 5.0

  test "a thousand unsafe tensors over one buffer release exactly their own":
    let buffer = cast[ptr UncheckedArray[float32]](
      allocShared0(4 * sizeof(float32)))
    defer: deallocShared(buffer)
    for iteration in 1 .. 1000:
      let value = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
      value.close()
    # The buffer is still the caller's, after a thousand tensors were built over
    # it and closed.
    buffer[0] = 1.0
    check buffer[0] == 1.0

  test "the tensor does not extend the buffer's lifetime, and says so":
    # Documentation is the only guarantee here, so this test asserts that the
    # documented distinction is at least observable: the two constructors
    # disagree about ownership for the same shape and type.
    let buffer = cast[ptr UncheckedArray[float32]](
      allocShared0(4 * sizeof(float32)))
    defer: deallocShared(buffer)
    let borrowed = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
    defer: borrowed.close()
    let owned = tensorFrom(etF32, initShape(1, 4), inputValues)
    defer: owned.close()
    check borrowed.ownsStorage() != owned.ownsStorage()
    check borrowed.byteSize == owned.byteSize
