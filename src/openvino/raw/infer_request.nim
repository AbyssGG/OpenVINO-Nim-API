# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: inference requests and profiling data.
##
## Source of truth: `ov_infer_request.h` from OpenVINO `2026.4.0`, SHA-256
## `094d1373417110201add3a9474d65017114fee051000a9dd842f50a67553d47c`.
##
## Only the synchronous path is bound. `start_async`, `wait`, `wait_for` and
## `cancel` are optional for `0.1.0` and gated on lifetime and thread tests.
## `ov_infer_request_set_callback` is deliberately absent: a Nim exception must
## never cross a C callback boundary, which needs its own design.

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
