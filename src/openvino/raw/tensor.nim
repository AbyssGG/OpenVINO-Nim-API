# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: tensors.
##
## Source of truth: `ov_tensor.h` from OpenVINO `2026.4.0`, SHA-256
## `01c3e0de53079e6c099a078b1ca166eaf10b7fdf604124666a04e7657e6a7240`.
##
## Every shape parameter here is `ov_shape_t` **by value**. The Resonance
## prototype declared `ov_tensor_set_shape` as taking a pointer, which is the
## third confirmed ABI defect from the audit and is covered by a dedicated
## regression test rather than by inspection.

import common
import loader
import shape

{.push styleChecks: off.}

type ov_tensor_t* = object
  ## Opaque tensor handle. Released with `ov_tensor_free`.
  ##
  ## Declared incomplete on purpose: the layout is private to OpenVINO.

proc ov_tensor_create*(`type`: ov_element_type_e; shape: ov_shape_t;
                       tensor: ptr ptr ov_tensor_t): ov_status_e
  {.openvinoImport.}
  ## Creates a tensor whose storage OpenVINO allocates and owns.
  ##
  ## Takes `shape` **by value**. This is the safe default for the managed
  ## layer, and the prototype never bound it at all.

proc ov_tensor_create_from_host_ptr*(`type`: ov_element_type_e;
                                     shape: ov_shape_t; host_ptr: pointer;
                                     tensor: ptr ptr ov_tensor_t): ov_status_e
  {.openvinoImport.}
  ## Creates a tensor over memory the caller owns.
  ##
  ## Takes `shape` **by value**. The tensor borrows `host_ptr` without owning
  ## it: the caller must keep that memory alive, at a stable address and with
  ## sufficient capacity, for as long as the tensor exists. The managed layer
  ## exposes this only under a name containing `unsafe`.

proc ov_tensor_set_shape*(tensor: ptr ov_tensor_t;
                          shape: ov_shape_t): ov_status_e {.openvinoImport.}
  ## Replaces the tensor's shape, reallocating when the new size is larger.
  ##
  ## Takes `shape` **by value**, not by pointer. Any view previously obtained
  ## from `ov_tensor_data` is invalid afterwards.

proc ov_tensor_get_shape*(tensor: ptr ov_tensor_t;
                          shape: ptr ov_shape_t): ov_status_e {.openvinoImport.}
  ## Fills `shape` with the tensor's shape.
  ##
  ## OpenVINO allocates the dimension storage, so a successful call must be
  ## paired with `ov_shape_free`.

proc ov_tensor_get_element_type*(tensor: ptr ov_tensor_t;
                                 `type`: ptr ov_element_type_e): ov_status_e
  {.openvinoImport.}
  ## Reads the tensor's element type.

proc ov_tensor_get_size*(tensor: ptr ov_tensor_t;
                         elements_size: ptr csize_t): ov_status_e
  {.openvinoImport.}
  ## Reads the number of elements, which is one for a scalar.

proc ov_tensor_get_byte_size*(tensor: ptr ov_tensor_t;
                              byte_size: ptr csize_t): ov_status_e
  {.openvinoImport.}
  ## Reads the size of the tensor's storage in bytes.

proc ov_tensor_data*(tensor: ptr ov_tensor_t;
                     data: ptr pointer): ov_status_e {.openvinoImport.}
  ## Returns a borrowed pointer to the tensor's storage.
  ##
  ## The pointer belongs to the tensor and must not be released. It becomes
  ## invalid when the tensor is freed or its shape changes.

proc ov_tensor_free*(tensor: ptr ov_tensor_t) {.openvinoImport.}
  ## Releases a tensor.

{.pop.}
