# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: models.
##
## Source of truth: `ov_model.h` from OpenVINO `2026.4.0`, SHA-256
## `c30d0f655c3065197fbec3a7575a65214bb75b8b51984351ff54ac0f74232ae6`.
##
## The const-port accessors and the name- and index-based reshape functions
## are bound. `ov_model_reshape_by_ports` and the mutable-port accessors are
## not, because they need `ov_output_port_t`.
##
## The reshape functions take a `const ov_model_t*` but **modify the model in
## place**. They convert the partial shape without validating it, and when its
## rank is dynamic, or is 0, they reshape to a rank-1 `[?]` instead (measured
## in Phase 0 of the 0.2 plan; see
## `docs/decisions/0004-partial-shape-representation.md`).

import common
import loader
import node
import partial_shape

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

proc ov_model_reshape*(model: ptr ov_model_t; tensor_names: ptr cstring;
                       partial_shapes: ptr ov_partial_shape_t;
                       size: csize_t): ov_status_e {.openvinoImport.}
  ## Reshapes `size` inputs, named by `tensor_names`, in one call.
  ##
  ## Both arrays are read during the call only. Modifies `model` in place.

proc ov_model_reshape_input_by_name*(model: ptr ov_model_t;
                                     tensor_name: cstring;
                                     partial_shape: ov_partial_shape_t):
    ov_status_e {.openvinoImport.}
  ## Reshapes the input named `tensor_name`. Takes the shape **by value**.

proc ov_model_reshape_single_input*(model: ptr ov_model_t;
                                    partial_shape: ov_partial_shape_t):
    ov_status_e {.openvinoImport.}
  ## Reshapes input 0. Takes the shape **by value**.

proc ov_model_reshape_by_port_indexes*(model: ptr ov_model_t;
                                       port_indexes: ptr csize_t;
                                       partial_shape: ptr ov_partial_shape_t;
                                       size: csize_t): ov_status_e
  {.openvinoImport.}
  ## Reshapes `size` inputs selected by index, in one call.

{.pop.}
