# SPDX-License-Identifier: Apache-2.0

## Asynchronous inference through the public API: `startAsync`, `wait`,
## `waitFor`, `cancel`, the two new error subtypes, and `CompletionQueue`.
##
## Timing-sensitive checks use the ReLU fixture reshaped to `[1, 32000000]`,
## whose inference takes tens of milliseconds, and only assert "busy" after
## `waitFor` with a zero timeout has confirmed the run is still in flight, so
## a fast machine cannot make them flaky.
##
## Run with `nimble testIntegration`.

import std/[os, sequtils, unittest]

import openvino

const
  fixtureDirectory = currentSourcePath().parentDir.parentDir / "fixtures"
  staticPath = fixtureDirectory / "relu_1x4_f32.xml"
  device = "CPU"
  busyLength = 32_000_000
  noWait = initDuration(milliseconds = 0)
  patience = initDuration(seconds = 30)

proc relu(values: openArray[float32]): seq[float32] =
  values.mapIt(max(0'f32, it))

proc compileSmall(core: Core): CompiledModel =
  core.compileModel(staticPath, device)

proc compileBusy(core: Core): CompiledModel =
  ## A model whose inference lasts long enough to be observed running.
  let model = core.readModel(staticPath)
  defer: model.close()
  model.reshape(initPartialShape(initShape(1, busyLength)))
  core.compileModel(model, device)

proc feed(request: InferRequest; values: openArray[float32]) =
  let tensor = tensorFrom(etF32, initShape(1, 4), values)
  defer: tensor.close()
  request.setInputTensor(0, tensor)

proc output(request: InferRequest): seq[float32] =
  let tensor = request.outputTensor(0)
  defer: tensor.close()
  tensor.toSeq(float32)

template whileRunning(request: InferRequest; body: untyped) =
  ## Starts `request` and runs `body` only if the run is observed in flight,
  ## retrying a few times. Fails the test if it never is.
  var observed = false
  for attempt in 1 .. 5:
    request.startAsync()
    if not request.waitFor(noWait):
      body
      observed = true
    request.wait()
    if observed:
      break
  if not observed:
    checkpoint("the request finished before it could be observed running")
  check observed

suite "start, wait and waitFor":
  test "startAsync then wait produces the synchronous result":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let values = [float32(-1.5), 2.0, -0.25, 4.0]
    request.feed(values)
    request.startAsync()
    request.wait()
    check request.output == relu(values)

  test "waitFor reports a timeout as false and completion as true":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    var sawTimeout = false
    for attempt in 1 .. 5:
      request.startAsync()
      if not request.waitFor(noWait):
        sawTimeout = true
      check request.waitFor(patience)
      if sawTimeout:
        break
    check sawTimeout
    # Once finished, polling reports completion again without raising.
    check request.waitFor(noWait)

  test "waitFor and wait on a never-started request return at once":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    check request.waitFor(noWait)
    check request.waitFor(initDuration(milliseconds = 10))
    request.wait()

  test "a negative timeout is refused before reaching OpenVINO":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    expect OpenVinoArgumentError:
      discard request.waitFor(initDuration(milliseconds = -1))

  test "a bound tensor may be closed before the run; OpenVINO keeps it":
    # The evidence behind ADR 0003's decision not to keep bound tensors alive
    # on the Nim side: the request holds its own reference to the tensor.
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let values = [float32(3), -3, 5, -5]
    block:
      let tensor = tensorFrom(etF32, initShape(1, 4), values)
      request.setInputTensor(0, tensor)
      tensor.close()
    request.startAsync()
    request.wait()
    check request.output == relu(values)

suite "busy and cancelled":
  test "calls on a running request raise OpenVinoBusyError":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let spare = newTensor(etF32, initShape(1, busyLength))
    defer: spare.close()
    request.whileRunning:
      expect OpenVinoBusyError:
        request.startAsync()
      expect OpenVinoBusyError:
        request.infer()
      expect OpenVinoBusyError:
        request.setInputTensor(0, spare)
      expect OpenVinoBusyError:
        discard request.outputTensor(0)

  test "OpenVinoBusyError is an OpenVinoError carrying REQUEST_BUSY":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    request.whileRunning:
      try:
        request.startAsync()
        check false
      except OpenVinoError as err:
        check err of OpenVinoBusyError
        check err.statusInfo.len > 0

  test "wait after cancel raises OpenVinoCancelledError until restarted":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    request.startAsync()
    request.cancel()
    expect OpenVinoCancelledError:
      request.wait()
    expect OpenVinoCancelledError:
      discard request.waitFor(noWait)
    # The request is usable again afterwards, synchronously and not.
    request.infer()
    request.startAsync()
    request.wait()

  test "cancel on an idle request is harmless":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    request.cancel()
    request.wait()
    request.startAsync()
    request.wait()
    request.cancel()
    request.wait()

suite "completion queue":
  test "next returns the id of the request that finished":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let queue = newCompletionQueue(capacity = 1)
    defer: queue.close()
    queue.attach(request, 42)
    check queue.next(noWait).isNone
    request.feed([float32(1), -1, 1, -1])
    request.startAsync()
    let finished = queue.next(patience)
    check finished.isSome
    check finished.get == 42
    request.wait()
    check request.output == @[float32(1), 0, 1, 0]
    check queue.pending == 0

  test "a cancelled run is reported, a synchronous infer is not":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let queue = newCompletionQueue(capacity = 1)
    defer: queue.close()
    queue.attach(request, 7)
    request.startAsync()
    request.cancel()
    check queue.next(patience).get == 7
    expect OpenVinoCancelledError:
      request.wait()
    request.infer()
    check queue.next(initDuration(milliseconds = 50)).isNone

  test "a request finishing twice before next is reported once":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let queue = newCompletionQueue(capacity = 1)
    defer: queue.close()
    queue.attach(request, 1)
    for round in 1 .. 2:
      request.startAsync()
      request.wait()
    check queue.pending == 1
    check queue.next(noWait).get == 1
    check queue.pending == 0

  test "attach refuses a full queue, a second queue and a closed queue":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    let first = compiled.createInferRequest()
    defer: first.close()
    let second = compiled.createInferRequest()
    defer: second.close()
    let queue = newCompletionQueue(capacity = 1)
    defer: queue.close()
    check queue.capacity == 1
    queue.attach(first, 0)
    expect OpenVinoArgumentError:
      queue.attach(second, 1)
    expect OpenVinoArgumentError:
      queue.attach(first, 0)
    let other = newCompletionQueue(capacity = 2)
    expect OpenVinoArgumentError:
      other.attach(first, 0)
    other.close()
    expect OpenVinoArgumentError:
      other.attach(second, 0)
    expect OpenVinoArgumentError:
      discard newCompletionQueue(capacity = 0)

  test "attach refuses a running request":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileBusy()
    defer: compiled.close()
    let request = compiled.createInferRequest()
    defer: request.close()
    let queue = newCompletionQueue(capacity = 1)
    defer: queue.close()
    request.whileRunning:
      expect OpenVinoBusyError:
        queue.attach(request, 0)
    queue.attach(request, 0)

  test "next and pending on a closed queue raise; negative timeouts too":
    let queue = newCompletionQueue(capacity = 1)
    expect OpenVinoArgumentError:
      discard queue.next(initDuration(milliseconds = -5))
    queue.close()
    check queue.isClosed
    expect OpenVinoArgumentError:
      discard queue.next(noWait)
    expect OpenVinoArgumentError:
      discard queue.pending

  test "four requests pipelined through one queue for 1000 rounds":
    let core = newCore()
    defer: core.close()
    let compiled = core.compileSmall()
    defer: compiled.close()
    const requestCount = 4
    const rounds = 1000
    var requests: seq[InferRequest] = @[]
    let queue = newCompletionQueue(capacity = requestCount)
    defer: queue.close()
    var issued = newSeq[int](requestCount)
    proc valuesFor(round: int): array[4, float32] =
      [float32(round), -float32(round), float32(round) + 0.5, -1]
    for id in 0 ..< requestCount:
      let request = compiled.createInferRequest()
      requests.add(request)
      queue.attach(request, id)
    defer:
      for request in requests:
        request.close()
    var nextRound = 0
    for id in 0 ..< requestCount:
      requests[id].feed(valuesFor(nextRound))
      issued[id] = nextRound
      inc nextRound
      requests[id].startAsync()
    var completed = 0
    var wrong = 0
    while completed < rounds:
      let finished = queue.next(patience)
      check finished.isSome
      if finished.isNone:
        break
      let id = finished.get
      requests[id].wait()
      if requests[id].output != relu(valuesFor(issued[id])):
        inc wrong
      inc completed
      if nextRound < rounds:
        requests[id].feed(valuesFor(nextRound))
        issued[id] = nextRound
        inc nextRound
        requests[id].startAsync()
    check completed == rounds
    check wrong == 0
    check queue.pending == 0
