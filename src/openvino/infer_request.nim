# SPDX-License-Identifier: Apache-2.0

## Inference requests: binding tensors, running inference, reading profiling.
##
## Only the synchronous path exists. `infer` blocks. There is no asynchronous
## API and no callback API in `0.1.0`: a Nim exception must never cross a C
## callback boundary, and getting that right needs its own design rather than a
## hopeful wrapper.

import errors
import private/conversions
import private/handles
import raw/common
import raw/infer_request as rawRequest
import raw/tensor as rawTensor
import tensor

export tensor

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
    ## Owns one `ov_infer_request_t`. Copying shares the native object and the
    ## closed state.
    ##
    ## Not safe to use from several threads at once. Bind, infer and read from
    ## one thread, or give each thread its own request.
    handle: Handle[ov_infer_request_t]
    inputCount: int
    outputCount: int

proc releaseRequest(native: ptr ov_infer_request_t) {.nimcall.} =
  ## Release function handed to the handle model.
  ov_infer_request_free(native)

proc wrapInferRequest*(native: ptr ov_infer_request_t;
                       inputCount, outputCount: int): InferRequest =
  ## Takes ownership of `native`.
  ##
  ## Internal to the package. The port counts are captured at creation so that
  ## index checks do not need a call into OpenVINO on every access.
  InferRequest(handle: newHandle(native, releaseRequest, "infer request"),
               inputCount: inputCount, outputCount: outputCount)

proc close*(request: InferRequest) =
  ## Releases the request. Safe to call more than once.
  ##
  ## Do not close a request while an inference on it is running.
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
  ## Binds `value` to the input at `index`.
  ##
  ## The request borrows the tensor: it must stay open until the inference
  ## completes. Binding does not copy.
  ##
  ## Raises `OpenVinoArgumentError` for a negative or out-of-range index, or if
  ## either object is closed.
  let raw = checkedIndex(index, request.inputCount, "input")
  checkStatus(ov_infer_request_set_input_tensor_by_index(
                request.handle.native(), raw, value.unsafeRawHandle()),
              "set input tensor", "index=" & $index)

proc setInputTensor*(request: InferRequest; name: string; value: Tensor) =
  ## Binds `value` to the port named `name`.
  ##
  ## Raises `OpenVinoError` when no port has that name, and
  ## `OpenVinoArgumentError` if either object is closed.
  checkStatus(ov_infer_request_set_tensor(request.handle.native(),
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
                request.handle.native(), raw, addr native),
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
                request.handle.native(), raw, addr native),
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
  checkStatus(ov_infer_request_infer(request.handle.native()), "run inference")

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
  checkStatus(ov_infer_request_get_profiling_info(request.handle.native(),
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

proc unsafeRawHandle*(request: InferRequest): ptr ov_infer_request_t =
  ## Returns the borrowed native handle for use with `openvino/raw`.
  request.handle.native()
