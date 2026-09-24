# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: compiled models.
##
## Source of truth: `ov_compiled_model.h` from OpenVINO `2026.4.0`, SHA-256
## `f49bbf08a264d06d834b3c2bd43bff826d255766e90e64092d27037bac07e218`.
##
## Only the non-variadic `ov_compiled_model_set_properties` is bound. The
## variadic `ov_compiled_model_set_property` is deliberately absent: replacing
## it is why the prototype's `perf_count_wrapper.c` existed and why that file
## is deleted rather than ported.

import common
import infer_request
import loader
import node
import property

{.push styleChecks: off.}

type ov_compiled_model_t* = object
  ## Opaque compiled model handle. Released with `ov_compiled_model_free`.
  ##
  ## Declared incomplete on purpose: the layout is private to OpenVINO.

proc ov_compiled_model_create_infer_request*(
    compiled_model: ptr ov_compiled_model_t;
    infer_request: ptr ptr ov_infer_request_t): ov_status_e {.openvinoImport.}
  ## Creates an inference request, owned by the caller.

proc ov_compiled_model_inputs_size*(compiled_model: ptr ov_compiled_model_t;
                                    size: ptr csize_t): ov_status_e
  {.openvinoImport.}
  ## Reads the number of inputs.

proc ov_compiled_model_outputs_size*(compiled_model: ptr ov_compiled_model_t;
                                     size: ptr csize_t): ov_status_e
  {.openvinoImport.}
  ## Reads the number of outputs.

proc ov_compiled_model_input_by_index*(
    compiled_model: ptr ov_compiled_model_t; index: csize_t;
    input_port: ptr ptr ov_output_const_port_t): ov_status_e
  {.openvinoImport.}
  ## Returns the input port at `index`, owned by the caller.
  ##
  ## A compiled model yields const ports only, which is what the metadata
  ## getters in `openvino/raw/node` require.

proc ov_compiled_model_output_by_index*(
    compiled_model: ptr ov_compiled_model_t; index: csize_t;
    output_port: ptr ptr ov_output_const_port_t): ov_status_e
  {.openvinoImport.}
  ## Returns the output port at `index`, owned by the caller.

proc ov_compiled_model_set_properties*(
    compiled_model: ptr ov_compiled_model_t; num_properties: csize_t;
    properties: ptr ov_property_t): ov_status_e {.openvinoImport.}
  ## Applies `num_properties` properties. Non-variadic form.
  ##
  ## Every key and value pointer must stay alive until the call returns.

proc ov_compiled_model_get_property*(
    compiled_model: ptr ov_compiled_model_t; property_key: cstring;
    property_value: ptr cstring): ov_status_e {.openvinoImport.}
  ## Reads one property as a string.
  ##
  ## Allocates the value, so the caller must copy it and release the original
  ## with `ov_free`.

proc ov_compiled_model_export_model*(
    compiled_model: ptr ov_compiled_model_t;
    export_model_path: cstring): ov_status_e {.openvinoImport.}
  ## Writes the compiled model to `export_model_path`.
  ##
  ## An explicit operation only. This package never creates a directory, picks
  ## a cache filename or exports on its own initiative.

proc ov_compiled_model_free*(compiled_model: ptr ov_compiled_model_t)
  {.openvinoImport.}
  ## Releases a compiled model.

{.pop.}
