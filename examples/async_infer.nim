# SPDX-License-Identifier: Apache-2.0

## Asynchronous inference: one request with `startAsync` and `waitFor`, then
## four requests pipelined through a `CompletionQueue`.
##
## Uses the ReLU fixture `relu_1x4_f32.xml`, so every output is `max(0, x)`.
##
## Build and run from the repository root:
##
## ```shell
## nim c -r --path:src examples/async_infer.nim
## ```

import openvino

const
  modelPath = "tests/fixtures/relu_1x4_f32.xml"
  requestCount = 4
  batches = 12

proc batchValues(batch: int): array[4, float32] =
  [float32(batch), -float32(batch), 0.5, -0.5]

proc feed(request: InferRequest; values: openArray[float32]) =
  let tensor = tensorFrom(etF32, initShape(1, 4), values)
  defer: tensor.close()
  # OpenVINO keeps its own reference to a bound tensor, so closing ours here
  # is safe even while the request runs.
  request.setInputTensor(0, tensor)

proc firstOutput(request: InferRequest): seq[float32] =
  let tensor = request.outputTensor(0)
  defer: tensor.close()
  tensor.toSeq(float32)

proc showSingleRequest(compiled: CompiledModel) =
  echo "One request"
  let request = compiled.createInferRequest()
  defer: request.close()
  request.feed([float32(-1), 2, -3, 4])
  request.startAsync()
  # The calling thread is free here. waitFor returns false on a timeout, which
  # is not an error; wait or waitFor is where a failed run would raise.
  var polls = 0
  while not request.waitFor(initDuration(milliseconds = 1)):
    inc polls
  echo "  finished after ", polls, " extra polls: ", request.firstOutput

proc showPipeline(compiled: CompiledModel) =
  echo ""
  echo "Four requests through one completion queue"
  let queue = newCompletionQueue(capacity = requestCount)
  defer: queue.close()
  var requests: seq[InferRequest] = @[]
  defer:
    for request in requests:
      request.close()
  var nextBatch = 0
  var batchOf = newSeq[int](requestCount)
  for id in 0 ..< requestCount:
    let request = compiled.createInferRequest()
    requests.add(request)
    # The id comes back from `next` when this request finishes.
    queue.attach(request, id)
    request.feed(batchValues(nextBatch))
    batchOf[id] = nextBatch
    inc nextBatch
    request.startAsync()

  var done = 0
  while done < batches:
    let finished = queue.next(initDuration(seconds = 10))
    if finished.isNone:
      echo "  timed out waiting for a request"
      quit(1)
    let id = finished.get
    let request = requests[id]
    request.wait() # returns at once; raises if this run failed
    echo "  request ", id, " finished batch ", batchOf[id], ": ",
      request.firstOutput
    inc done
    if nextBatch < batches:
      request.feed(batchValues(nextBatch))
      batchOf[id] = nextBatch
      inc nextBatch
      request.startAsync()

proc showCancel(compiled: CompiledModel) =
  echo ""
  echo "Cancelling"
  let request = compiled.createInferRequest()
  defer: request.close()
  request.feed(batchValues(1))
  request.startAsync()
  request.cancel()
  try:
    request.wait()
    echo "  the run finished before the cancellation took effect"
  except OpenVinoCancelledError:
    echo "  the run was cancelled"

proc main() =
  let core = newCore()
  defer: core.close()
  let compiled = core.compileModel(modelPath, "CPU")
  defer: compiled.close()
  showSingleRequest(compiled)
  showPipeline(compiled)
  showCancel(compiled)

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
