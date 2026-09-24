# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: models.
##
## Source of truth: `ov_model.h` from OpenVINO `2026.4.0`, SHA-256
## `c30d0f655c3065197fbec3a7575a65214bb75b8b51984351ff54ac0f74232ae6`.
##
## Only the const-port accessors are bound. The mutable-port and reshape
## entry points belong to dynamic shapes, which are out of scope for `0.1.0`.
## Note that `ov_model_reshape_input_by_name` and `ov_model_reshape_single_input`
## take `ov_partial_shape_t` by value, a fact recorded in
## `docs/c-api-coverage.md` so that it is not rediscovered the hard way later.

import common
import loader
import node

{.push styleChecks: off.}

type ov_model_t* = object
  ## Opaque model handle. Released with `ov_model_free`.
  ##
  ## Declared incomplete on purpose: the layout is private to OpenVINO.

proc ov_model_free*(model: ptr ov_model_t) {.openvinoImport.}
  ## Releases a model.

proc ov_model_inputs_size*(model: ptr ov_model_t;
                           input_size: ptr csize_t): ov_status_e
  {.openvinoImport.}
  ## Reads the number of inputs.

proc ov_model_outputs_size*(model: ptr ov_model_t;
                            output_size: ptr csize_t): ov_status_e
  {.openvinoImport.}
  ## Reads the number of outputs.

proc ov_model_const_input_by_index*(model: ptr ov_model_t; index: csize_t;
                                    input_port:
                                      ptr ptr ov_output_const_port_t):
    ov_status_e {.openvinoImport.}
  ## Returns the input port at `index`, owned by the caller.
  ##
  ## Release it with `ov_output_const_port_free`.

proc ov_model_const_output_by_index*(model: ptr ov_model_t; index: csize_t;
                                     output_port:
                                       ptr ptr ov_output_const_port_t):
    ov_status_e {.openvinoImport.}
  ## Returns the output port at `index`, owned by the caller.

proc ov_model_const_input_by_name*(model: ptr ov_model_t;
                                   tensor_name: cstring;
                                   input_port:
                                     ptr ptr ov_output_const_port_t):
    ov_status_e {.openvinoImport.}
  ## Returns the input port named `tensor_name`, owned by the caller.

proc ov_model_const_output_by_name*(model: ptr ov_model_t;
                                    tensor_name: cstring;
                                    output_port:
                                      ptr ptr ov_output_const_port_t):
    ov_status_e {.openvinoImport.}
  ## Returns the output port named `tensor_name`, owned by the caller.

proc ov_model_is_dynamic*(model: ptr ov_model_t): bool {.openvinoImport.}
  ## Reports whether the model has any dynamic dimension.
  ##
  ## Returns C99 `bool`, not a status. The ABI test verifies that Nim's `bool`
  ## has the same width.

proc ov_model_get_friendly_name*(model: ptr ov_model_t;
                                 friendly_name: ptr cstring): ov_status_e
  {.openvinoImport.}
  ## Reads the model's friendly name.
  ##
  ## Allocates the string, so the caller must copy it and release the original
  ## with `ov_free`.

{.pop.}
