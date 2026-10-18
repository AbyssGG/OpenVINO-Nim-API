# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: inference requests and profiling data.
##
## Source of truth: `ov_infer_request.h` from OpenVINO `2026.4.0`, SHA-256
## `094d1373417110201add3a9474d65017114fee051000a9dd842f50a67553d47c`.
##
## The asynchronous entry points are bound since `0.2.0`. Their measured
## behaviour (Phase 0 of the 0.2 plan, `docs/decisions/0003-async-completion.md`)
## is summarised on each declaration. `ov_infer_request_set_callback` stores
## the **pointer** it is given and invokes it on an OpenVINO worker thread, so
## an `ov_callback_t` must outlive the request and its function must not
## allocate, raise or touch Nim-managed memory.

import common
import loader
import node
import tensor

{.push styleChecks: off.}

type
  ov_infer_request_t* = object
    ## Opaque inference request handle. Released with
    ## `ov_infer_request_free`.
    ##
    ## Declared incomplete on purpose: the layout is private to OpenVINO.

  ov_profiling_info_t* = object
    ## Timing for one executed node.
    ##
    ## `status` is an anonymous nested `enum Status` in the header. Its width
    ## is whatever the C compiler gives an enum, which the ABI test verifies
    ## rather than assumes; the prototype declared it as `int32` without
    ## checking. The three strings belong to OpenVINO and must be copied
    ## before the list is released.
    status*: ov_status_e
    real_time*: int64
    cpu_time*: int64
    node_name*: cstring
    exec_type*: cstring
    node_type*: cstring

  ov_profiling_info_list_t* = object
    ## A profiling result set.
    ##
    ## Release a successful result with `ov_profiling_info_list_free`
    ## unconditionally, including when `size` is zero. The prototype released
    ## it only when `size` was non-zero, which is not what the contract says.
    profiling_infos*: ptr UncheckedArray[ov_profiling_info_t]
    size*: csize_t

  ov_callback_func* = proc (args: pointer) {.cdecl, gcsafe, raises: [].}
    ## Completion function type. `OPENVINO_C_API_CALLBACK` is `__cdecl` on
    ## Windows and empty elsewhere, which `cdecl` matches on both.
    ##
    ## Declared `gcsafe` and `raises: []` because OpenVINO calls it on a
    ## thread Nim did not create: it must not raise, allocate from the Nim
    ## heap or touch a `ref`, `string` or `seq`.

  ov_callback_t* = object
    ## A completion function and its argument.
    ##
    ## OpenVINO keeps a pointer to this struct, not a copy, so it must live at
    ## a stable address for as long as the request can complete. Layout is
    ## verified by the ABI test.
    callback_func*: ov_callback_func
    args*: pointer

const
  PROFILING_NOT_RUN* = ov_status_e(0)
    ## The node was not executed. Value verified by the ABI test.

  PROFILING_OPTIMIZED_OUT* = ov_status_e(1)
    ## The node was optimised away.

  PROFILING_EXECUTED* = ov_status_e(2)
    ## The node was executed.

proc ov_infer_request_set_input_tensor_by_index*(
    infer_request: ptr ov_infer_request_t; idx: csize_t;
    tensor: ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Binds `tensor` to the input at `idx`.
  ##
  ## The request borrows the tensor: it must outlive the inference.

proc ov_infer_request_get_input_tensor_by_index*(
    infer_request: ptr ov_infer_request_t; idx: csize_t;
    tensor: ptr ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Returns the tensor currently bound to the input at `idx`.
  ##
  ## The returned handle is owned by the caller and released with
  ## `ov_tensor_free`.

proc ov_infer_request_get_output_tensor_by_index*(
    infer_request: ptr ov_infer_request_t; idx: csize_t;
    tensor: ptr ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Returns the output tensor at `idx`, owned by the caller.

proc ov_infer_request_set_tensor*(infer_request: ptr ov_infer_request_t;
                                  tensor_name: cstring;
                                  tensor: ptr ov_tensor_t): ov_status_e
  {.openvinoImport.}
  ## Binds `tensor` to the port named `tensor_name`.

proc ov_infer_request_get_tensor*(infer_request: ptr ov_infer_request_t;
                                  tensor_name: cstring;
                                  tensor: ptr ptr ov_tensor_t): ov_status_e
  {.openvinoImport.}
  ## Returns the tensor at the port named `tensor_name`, owned by the caller.

proc ov_infer_request_set_tensor_by_const_port*(
    infer_request: ptr ov_infer_request_t;
    port: ptr ov_output_const_port_t;
    tensor: ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Binds `tensor` to `port`.

proc ov_infer_request_infer*(infer_request: ptr ov_infer_request_t): ov_status_e
  {.openvinoImport.}
  ## Runs inference synchronously. **Blocks** until the request completes.
  ##
  ## Does not invoke a callback installed with `ov_infer_request_set_callback`.

proc ov_infer_request_start_async*(infer_request: ptr ov_infer_request_t):
    ov_status_e {.openvinoImport.}
  ## Starts inference and returns immediately.
  ##
  ## Returns `REQUEST_BUSY` when the request is already running. While it
  ## runs, `infer` and tensor getters and setters also return `REQUEST_BUSY`.
  ## Failures of the run itself are reported by `wait` or `wait_for`.

proc ov_infer_request_wait*(infer_request: ptr ov_infer_request_t):
    ov_status_e {.openvinoImport.}
  ## Blocks until the request completes and returns the run's status.
  ##
  ## Returns `INFER_CANCELLED` after a cancelled run, repeatedly, until the
  ## request is started again. Returns `OK` at once on a request that was
  ## never started.

proc ov_infer_request_wait_for*(infer_request: ptr ov_infer_request_t;
                                timeout: int64): ov_status_e {.openvinoImport.}
  ## Waits at most `timeout` milliseconds.
  ##
  ## Returns `RESULT_NOT_READY` on timeout, which is not a failure. Unlike
  ## `ov_infer_request_wait`, it also returns `RESULT_NOT_READY` on a request
  ## that was never started. A negative timeout returns `GENERAL_ERROR`.

proc ov_infer_request_cancel*(infer_request: ptr ov_infer_request_t):
    ov_status_e {.openvinoImport.}
  ## Requests cancellation of a running inference.
  ##
  ## Returns `OK`, including on an idle or never-started request. A following
  ## `wait` reports `INFER_CANCELLED` if the run was actually cancelled.

proc ov_infer_request_set_callback*(infer_request: ptr ov_infer_request_t;
                                    callback: ptr ov_callback_t): ov_status_e
  {.openvinoImport.}
  ## Installs `callback` to be invoked when an asynchronous run completes,
  ## including a cancelled one.
  ##
  ## OpenVINO stores the **pointer**. The struct must outlive the request.
  ## Measured: the callback has finished before `wait` returns; a running
  ## request being freed does not invoke it.

proc ov_infer_request_set_input_tensor*(infer_request: ptr ov_infer_request_t;
                                        tensor: ptr ov_tensor_t): ov_status_e
  {.openvinoImport.}
  ## Binds `tensor` to the only input. Fails on a model with several inputs.

proc ov_infer_request_get_input_tensor*(infer_request: ptr ov_infer_request_t;
                                        tensor: ptr ptr ov_tensor_t):
    ov_status_e {.openvinoImport.}
  ## Returns the only input tensor, owned by the caller.

proc ov_infer_request_set_output_tensor_by_index*(
    infer_request: ptr ov_infer_request_t; idx: csize_t;
    tensor: ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Binds a caller-provided tensor as the output at `idx`.

proc ov_infer_request_set_output_tensor*(infer_request: ptr ov_infer_request_t;
                                         tensor: ptr ov_tensor_t): ov_status_e
  {.openvinoImport.}
  ## Binds a caller-provided tensor as the only output.

proc ov_infer_request_get_output_tensor*(infer_request: ptr ov_infer_request_t;
                                         tensor: ptr ptr ov_tensor_t):
    ov_status_e {.openvinoImport.}
  ## Returns the only output tensor, owned by the caller.

proc ov_infer_request_get_tensor_by_const_port*(
    infer_request: ptr ov_infer_request_t;
    port: ptr ov_output_const_port_t;
    tensor: ptr ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Returns the tensor at `port`, owned by the caller.

proc ov_infer_request_get_profiling_info*(
    infer_request: ptr ov_infer_request_t;
    profiling_infos: ptr ov_profiling_info_list_t): ov_status_e
  {.openvinoImport.}
  ## Fills `profiling_infos` with per-node timings.
  ##
  ## Requires profiling to have been enabled through the
  ## `ov_property_key_enable_profiling` property. Release a successful result
  ## with `ov_profiling_info_list_free`.

proc ov_profiling_info_list_free*(
    profiling_infos: ptr ov_profiling_info_list_t) {.openvinoImport.}
  ## Releases a profiling result set.

proc ov_infer_request_free*(infer_request: ptr ov_infer_request_t)
  {.openvinoImport.}
  ## Releases an inference request.

{.pop.}
