# SPDX-License-Identifier: Apache-2.0

## Inference requests: binding tensors, running inference synchronously or
## asynchronously, collecting completions, and reading profiling.
##
## `infer` blocks. `startAsync` returns at once; `wait` and `waitFor` collect
## the result and are the only places an asynchronous failure is reported.
##
## No Nim code ever runs on an OpenVINO thread. A `CompletionQueue` installs a
## package-internal C callback that only records which request finished; the
## caller's own thread then takes it from the queue with `next`. Users cannot
## register a Nim procedure as a callback. The design and its measured basis
## are in `docs/decisions/0003-async-completion.md`.

import std/[monotimes, options, times]

import errors
import private/conversions
import private/handles
import private/trampoline
import raw/common
import raw/infer_request as rawRequest
import raw/tensor as rawTensor
import tensor

# Only the names a caller needs to use `waitFor` and `next`, not the whole of
# `std/times` and `std/options`, so that `import openvino` stays narrow.
export Duration, initDuration, Option, isSome, isNone, get, tensor

type
  ProfilingStatus* = enum
    ## Whether a node ran, as reported by OpenVINO.
    psNotRun
    psOptimizedOut
    psExecuted

  ProfilingInfo* = object
    ## Timing for one node of an executed model.
    ##
    ## Every field is a Nim-owned copy. The native list is released before this
    ## is returned, so a `ProfilingInfo` outlives the request it came from.
    status*: ProfilingStatus
    realTimeMicroseconds*: int64
    cpuTimeMicroseconds*: int64
    nodeName*: string
    executionType*: string
    nodeType*: string

  InferRequest* = object
    ## One inference request created from a compiled model.
    ##
    ## Owns one `ov_infer_request_t`, held in a shared-memory box whose
    ## address never changes, because OpenVINO keeps a pointer into it once
    ## the request is attached to a `CompletionQueue`. Copying shares the
    ## native object and the closed state.
    ##
    ## Not safe to use from several threads at once. Bind, infer and read from
    ## one thread, or give each thread its own request. One thread may drive
    ## many requests asynchronously.
    handle: Handle[RequestBox]
    inputCount: int
    outputCount: int

  CompletionQueue* = object
    ## Tells the caller's thread which asynchronous requests have finished.
    ##
    ## Attach requests with `attach`, start them, and call `next` to receive
    ## the id of each request as it completes; then call `wait` on that request
    ## to collect its result or its error. Copying shares one queue.
    ##
    ## The queue is shared memory with a fixed capacity. It stays allocated
    ## until it is closed **and** every attached request has been closed, so
    ## either may be closed first.
    handle: Handle[QueueShared]

proc releaseRequest(box: ptr RequestBox) {.nimcall.} =
  ## Release function handed to the handle model. Never raises.
  ##
  ## Order matters and is the same for `close` and for the destructor:
  ## cancel and wait if the request was ever started, so nothing is running;
  ## free the request, after which OpenVINO can no longer call the callback
  ## stored in the box; detach from the queue; and only then free the box.
  ## If the request itself could not be freed, the box is deliberately leaked
  ## rather than freed under a callback that might still fire.
  if box.started:
    try:
      discard ov_infer_request_cancel(box.native)
    except CatchableError:
      discard
    try:
      discard ov_infer_request_wait(box.native)
    except CatchableError:
      discard
  var freed = false
  try:
    ov_infer_request_free(box.native)
    freed = true
  except CatchableError:
    discard
  if not freed:
    return
  box.native = nil
  let queue = box.queue
  if queue != nil:
    acquireQueue(queue)
    removeEntries(queue, box)
    releaseQueue(queue)
    box.queue = nil
    let ring = dropReference(queue)
    if ring != nil:
      deallocShared(ring)
      deallocShared(queue)
  deallocShared(box)

proc wrapInferRequest*(native: ptr ov_infer_request_t;
                       inputCount, outputCount: int): InferRequest =
  ## Takes ownership of `native`.
  ##
  ## Internal to the package. The port counts are captured at creation so that
  ## index checks do not need a call into OpenVINO on every access.
  if native == nil:
    raiseArgumentError("cannot create an infer request from a nil pointer")
  # invariant: `allocShared0` returns zeroed memory of exactly
  # `sizeof(RequestBox)` bytes, which is a valid `RequestBox` with no queue,
  # not started and no callback. The handle releases it with `deallocShared`.
  let box = cast[ptr RequestBox](allocShared0(sizeof(RequestBox)))
  box.native = native
  InferRequest(handle: newHandle(box, releaseRequest, "infer request"),
               inputCount: inputCount, outputCount: outputCount)

proc nativeRequest(request: InferRequest): ptr ov_infer_request_t =
  ## The borrowed native request. Raises `OpenVinoArgumentError` when closed.
  request.handle.native().native

proc close*(request: InferRequest) =
  ## Releases the request. Safe to call more than once.
  ##
  ## Safe on a running request: it is cancelled where the device supports
  ## it, waited for, and then released; any error from that run is discarded.
  request.handle.close()

proc isClosed*(request: InferRequest): bool =
  ## Reports whether the request has been closed. Never raises.
  request.handle.isClosed()

proc inputCount*(request: InferRequest): int =
  ## Returns the number of model inputs this request binds.
  request.inputCount

proc outputCount*(request: InferRequest): int =
  ## Returns the number of model outputs this request produces.
  request.outputCount

proc setInputTensor*(request: InferRequest; index: int; value: Tensor) =
  ## Binds `value` to the input at `index`. Binding does not copy.
  ##
  ## OpenVINO keeps its own reference to the bound tensor, so closing `value`
  ## afterwards, even while an asynchronous run is in flight, does not
  ## invalidate the binding. Memory given to `unsafeTensorFromPointer` is
  ## different: it belongs to the caller and must stay valid until the
  ## inference has been waited for.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or out-of-range index, or if
  ## either object is closed, and `OpenVinoBusyError` while the request runs.
  let raw = checkedIndex(index, request.inputCount, "input")
  checkStatus(ov_infer_request_set_input_tensor_by_index(
                request.nativeRequest(), raw, value.unsafeRawHandle()),
              "set input tensor", "index=" & $index)

proc setInputTensor*(request: InferRequest; name: string; value: Tensor) =
  ## Binds `value` to the port named `name`.
  ##
  ## Raises `OpenVinoError` when no port has that name, and
  ## `OpenVinoArgumentError` if either object is closed.
  checkStatus(ov_infer_request_set_tensor(request.nativeRequest(),
                                          name.cstring,
                                          value.unsafeRawHandle()),
              "set input tensor by name", name)

proc inputTensor*(request: InferRequest; index: int): Tensor =
  ## Returns the tensor currently bound to the input at `index`.
  ##
  ## The returned tensor is a new owner and must be closed. Useful for writing
  ## directly into the buffer OpenVINO already allocated, instead of binding one
  ## of your own.
  ##
  ## Raises `OpenVinoArgumentError` for a bad index or a closed request.
  let raw = checkedIndex(index, request.inputCount, "input")
  var native: ptr ov_tensor_t = nil
  checkStatus(ov_infer_request_get_input_tensor_by_index(
                request.nativeRequest(), raw, addr native),
              "get input tensor", "index=" & $index)
  result = wrapOwnedTensor(native)

proc outputTensor*(request: InferRequest; index: int): Tensor =
  ## Returns the output tensor at `index`.
  ##
  ## The returned tensor is a new owner and must be closed. Its contents are
  ## only meaningful after `infer` has completed.
  ##
  ## Raises `OpenVinoArgumentError` for a bad index or a closed request.
  let raw = checkedIndex(index, request.outputCount, "output")
  var native: ptr ov_tensor_t = nil
  checkStatus(ov_infer_request_get_output_tensor_by_index(
                request.nativeRequest(), raw, addr native),
              "get output tensor", "index=" & $index)
  result = wrapOwnedTensor(native)

proc infer*(request: InferRequest) =
  ## Runs inference synchronously. **Blocks** until the request completes.
  ##
  ## Every input must be bound first, either by `setInputTensor` or by writing
  ## into the tensor `inputTensor` returns.
  ##
  ## Raises `OpenVinoError` when the runtime reports a failure, and
  ## `OpenVinoArgumentError` if the request is closed.
  checkStatus(ov_infer_request_infer(request.nativeRequest()), "run inference")

proc startAsync*(request: InferRequest) =
  ## Starts inference and returns immediately.
  ##
  ## Collect the result with `wait` or `waitFor`, which is also where a
  ## failure of the run is reported. While the request runs, starting it again,
  ## `infer`, and binding or reading its tensors raise `OpenVinoBusyError`.
  ##
  ## Raises `OpenVinoBusyError` when the request is already running, and
  ## `OpenVinoArgumentError` if it is closed.
  let box = request.handle.native()
  checkStatus(ov_infer_request_start_async(box.native),
              "start asynchronous inference")
  box.started = true

proc wait*(request: InferRequest) =
  ## **Blocks** until the request's asynchronous inference has finished.
  ##
  ## Returns at once if the request is idle or was never started. Raises
  ## `OpenVinoCancelledError` if the run was cancelled, which it keeps doing
  ## until the request is started again; raises `OpenVinoError` if the run
  ## failed, and `OpenVinoArgumentError` if the request is closed.
  checkStatus(ov_infer_request_wait(request.nativeRequest()),
              "wait for inference")

proc timeoutMilliseconds(timeout: Duration): int64 =
  ## Converts a non-negative timeout to whole milliseconds, rounding up so
  ## that a positive timeout never becomes a poll.
  if timeout < DurationZero:
    raiseArgumentError("a timeout cannot be negative: " & $timeout)
  if timeout.inSeconds > high(int64) div 1000 - 1:
    raiseArgumentError("timeout " & $timeout &
      " does not fit in a signed 64-bit count of milliseconds")
  result = timeout.inMilliseconds
  if initDuration(milliseconds = result) < timeout:
    inc result

proc waitFor*(request: InferRequest; timeout: Duration): bool =
  ## Waits at most `timeout` for the asynchronous inference to finish.
  ##
  ## Returns `true` when it has finished successfully and `false` when the
  ## timeout expired first, which is not an error. A zero timeout polls.
  ## Returns `true` at once for a request that was never started, matching
  ## `wait`; OpenVINO itself would report a timeout in that case.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or oversized timeout or a
  ## closed request, `OpenVinoCancelledError` if the run was cancelled, and
  ## `OpenVinoError` if it failed.
  let milliseconds = timeoutMilliseconds(timeout)
  let box = request.handle.native()
  if not box.started:
    return true
  let status = ov_infer_request_wait_for(box.native, milliseconds)
  if status == RESULT_NOT_READY:
    return false
  checkStatus(status, "wait for inference", "timeout=" & $timeout)
  result = true

proc cancel*(request: InferRequest) =
  ## Asks OpenVINO to cancel a running inference. Returns immediately.
  ##
  ## Harmless on an idle request. Still call `wait`, which then raises
  ## `OpenVinoCancelledError` if the run was cancelled, or returns normally if
  ## it had already finished.
  ##
  ## Not every plugin can cancel: the Intel NPU plugin in OpenVINO 2026.4
  ## reports `OpenVinoError` here, and the run then continues to completion.
  ## `close` does not depend on cancellation; it always waits.
  ##
  ## Raises `OpenVinoArgumentError` if the request is closed, and
  ## `OpenVinoError` when the device does not support cancellation.
  checkStatus(ov_infer_request_cancel(request.nativeRequest()),
              "cancel inference")

proc toProfilingStatus(raw: ov_status_e): ProfilingStatus =
  ## Converts the nested profiling status enumerator.
  ##
  ## Falls back to `psNotRun` for an unknown value rather than raising: losing
  ## one timing label is not worth discarding an entire profiling result.
  if raw == PROFILING_EXECUTED: psExecuted
  elif raw == PROFILING_OPTIMIZED_OUT: psOptimizedOut
  else: psNotRun

proc profilingInfo*(request: InferRequest): seq[ProfilingInfo] =
  ## Returns per-node timings for the most recent inference.
  ##
  ## Requires profiling to have been enabled when the model was compiled, with
  ## `properties.enableProfiling()`. Without it the runtime reports an error or
  ## an empty list, depending on the device.
  ##
  ## Copies every string, then releases the native list unconditionally,
  ## including when it is empty.
  ##
  ## Raises `OpenVinoError` when the runtime refuses, and
  ## `OpenVinoArgumentError` if the request is closed.
  var list: ov_profiling_info_list_t
  checkStatus(ov_infer_request_get_profiling_info(request.nativeRequest(),
                                                 addr list),
              "get profiling info")
  result = @[]
  try:
    for index in 0 ..< int(list.size):
      let entry = addr list.profiling_infos[index]
      result.add(ProfilingInfo(
        status: toProfilingStatus(entry.status),
        realTimeMicroseconds: entry.real_time,
        cpuTimeMicroseconds: entry.cpu_time,
        nodeName: (if entry.node_name != nil: $entry.node_name else: ""),
        executionType: (if entry.exec_type != nil: $entry.exec_type else: ""),
        nodeType: (if entry.node_type != nil: $entry.node_type else: "")))
  finally:
    # Released on success regardless of size. The prototype released only when
    # size was non-zero, which is not what the contract says.
    ov_profiling_info_list_free(addr list)

proc releaseCompletionQueue(queue: ptr QueueShared) {.nimcall.} =
  ## Release function handed to the handle model. Never raises.
  ##
  ## Marks the queue closed so that later completions are dropped, then gives
  ## up the owner's reference. The memory goes when the last attached request
  ## has also been released.
  acquireQueue(queue)
  queue.closed = true
  releaseQueue(queue)
  let ring = dropReference(queue)
  if ring != nil:
    deallocShared(ring)
    deallocShared(queue)

const maxQueueCapacity = 1 shl 20
  ## Generous upper bound that keeps the ring allocation small and finite.

proc newCompletionQueue*(capacity: int): CompletionQueue =
  ## Creates a queue that can have up to `capacity` requests attached.
  ##
  ## Each attached request has at most one unconsumed completion, so the
  ## queue can never overflow. Close it with `close`.
  ##
  ## Raises `OpenVinoArgumentError` unless `1 <= capacity <= 1048576`.
  if capacity < 1 or capacity > maxQueueCapacity:
    raiseArgumentError("a completion queue capacity must be between 1 and " &
      $maxQueueCapacity & ", not " & $capacity)
  # invariant: both allocations are zeroed shared memory of exactly the size of
  # the type, or of `capacity` pointers. They are released together by
  # `releaseCompletionQueue` or by the last attached request, never earlier.
  let ring = cast[ptr UncheckedArray[ptr RequestBox]](
    allocShared0(capacity * sizeof(pointer)))
  let queue = cast[ptr QueueShared](allocShared0(sizeof(QueueShared)))
  initQueueShared(queue, ring, capacity)
  CompletionQueue(handle: newHandle(queue, releaseCompletionQueue,
                                    "completion queue"))

proc close*(queue: CompletionQueue) =
  ## Closes the queue. Safe to call more than once.
  ##
  ## Attached requests keep working; their completions are no longer
  ## recorded.
  queue.handle.close()

proc isClosed*(queue: CompletionQueue): bool =
  ## Reports whether the queue has been closed. Never raises.
  queue.handle.isClosed()

proc capacity*(queue: CompletionQueue): int =
  ## Returns the maximum number of attached requests.
  ##
  ## Raises `OpenVinoArgumentError` if the queue is closed.
  queue.handle.native().capacity

proc attach*(queue: CompletionQueue; request: InferRequest; id: int) =
  ## Attaches `request`, so that each of its asynchronous runs, including a
  ## cancelled one, makes `next` return `id`. A synchronous `infer` does not.
  ##
  ## A request can be attached to one queue for its whole life; it is
  ## detached when it is closed. Ids are the caller's choice and need not be
  ## unique, though they usually index the caller's own list of requests.
  ##
  ## Raises `OpenVinoBusyError` when the request is running,
  ## `OpenVinoArgumentError` when it is already attached, when the queue is
  ## full, or when either object is closed.
  let shared = queue.handle.native()
  let box = request.handle.native()
  if box.queue != nil:
    raiseArgumentError("this infer request is already attached to a " &
      "completion queue")
  if box.started and
      ov_infer_request_wait_for(box.native, 0) == RESULT_NOT_READY:
    raiseBusyError("attach request to completion queue",
      "the request is running; wait for it before attaching")
  acquireQueue(shared)
  if shared.attached >= shared.capacity:
    let capacity = shared.capacity
    releaseQueue(shared)
    raiseArgumentError("the completion queue is full: its capacity is " &
      $capacity & " requests")
  shared.attached = shared.attached + 1
  addReference(shared)
  releaseQueue(shared)

  box.queue = shared
  box.id = id
  box.callback = ov_callback_t(callback_func: completionTrampoline,
                               args: box)
  let status = ov_infer_request_set_callback(box.native, addr box.callback)
  if status != OK:
    # Capture OpenVINO's detail before anything else, then undo the attach.
    let err = newOpenVinoError("attach request to completion queue", status)
    acquireQueue(shared)
    removeEntries(shared, box)
    releaseQueue(shared)
    box.queue = nil
    discard dropReference(shared)
    raise err

proc pending*(queue: CompletionQueue): int =
  ## Returns how many completions are waiting to be returned by `next`.
  ##
  ## Raises `OpenVinoArgumentError` if the queue is closed.
  let shared = queue.handle.native()
  acquireQueue(shared)
  result = pendingCount(shared)
  releaseQueue(shared)

proc next*(queue: CompletionQueue; timeout: Duration): Option[int] =
  ## **Blocks** until an attached request finishes, and returns its id, or
  ## returns `none` when `timeout` expires first. A zero timeout polls.
  ##
  ## Completions are returned oldest first. The request's result is then
  ## collected with `wait`, which returns at once and raises if the run
  ## failed or was cancelled.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or oversized timeout or a
  ## closed queue.
  let milliseconds = timeoutMilliseconds(timeout)
  let shared = queue.handle.native()
  let deadline = getMonoTime() + initDuration(milliseconds = milliseconds)
  acquireQueue(shared)
  try:
    while pendingCount(shared) == 0:
      let remaining = (deadline - getMonoTime()).inMilliseconds
      if remaining <= 0:
        return none(int)
      # Waits in chunks of at most one hour, which the platform waits accept.
      waitForCompletion(shared, min(remaining, 3_600_000'i64))
    result = some(popCompletion(shared))
  finally:
    releaseQueue(shared)

proc unsafeRawHandle*(request: InferRequest): ptr ov_infer_request_t =
  ## Returns the borrowed native handle for use with `openvino/raw`.
  request.nativeRequest()
