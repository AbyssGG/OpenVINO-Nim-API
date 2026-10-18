# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: pre- and post-processing.
##
## Source of truth: `ov_prepostprocess.h` from OpenVINO `2026.4.0`, SHA-256
## `7643323d197dd17068f01f75669d299297fc3d82891b35532ebea17fa3f518cb`.
##
## The header declares 40 functions. All 39 non-variadic ones are bound. The
## variadic `ov_preprocess_input_tensor_info_set_color_format_with_subname` is
## deliberately absent, because this package never guesses a platform varargs
## ABI; `ov_preprocess_input_tensor_info_set_color_format_with_subnames` takes
## the same information as an array.
##
## Ownership, verified against the upstream C binding in Phase 0: the
## preprocessor holds a shared reference to the model, and every child object
## (input info, input tensor info, steps, input model info, output info, output
## tensor info) stores a raw pointer **into its parent**. A child must be
## released before its parent; releasing a child frees only its wrapper.
## `ov_preprocess_prepostprocessor_build` returns a new `ov_model_t` that
## shares, and has modified, the source model's graph. See
## `docs/decisions/0005-preprocessing-api.md`.
##
## The three enumerations are bound as `cint` aliases with constants, for the
## reason given in `raw/common`. An out-of-range resize algorithm or padding
## mode makes OpenVINO report `UNKNOW_EXCEPTION`; an out-of-range color format
## is silently treated as `UNDEFINE`.

import common
import layout
import loader
import model
import tensor

{.push styleChecks: off.}

type
  ov_preprocess_prepostprocessor_t* = object
    ## Opaque preprocessor. Released with
    ## `ov_preprocess_prepostprocessor_free`.

  ov_preprocess_input_info_t* = object
    ## Opaque input description, borrowed from its preprocessor. Released with
    ## `ov_preprocess_input_info_free`.

  ov_preprocess_input_tensor_info_t* = object
    ## Opaque input tensor description, borrowed from its input info. Released
    ## with `ov_preprocess_input_tensor_info_free`.

  ov_preprocess_output_info_t* = object
    ## Opaque output description, borrowed from its preprocessor. Released with
    ## `ov_preprocess_output_info_free`.

  ov_preprocess_output_tensor_info_t* = object
    ## Opaque output tensor description, borrowed from its output info.
    ## Released with `ov_preprocess_output_tensor_info_free`.

  ov_preprocess_input_model_info_t* = object
    ## Opaque model-side input description, borrowed from its input info.
    ## Released with `ov_preprocess_input_model_info_free`.

  ov_preprocess_preprocess_steps_t* = object
    ## Opaque list of preprocessing steps, borrowed from its input info.
    ## Released with `ov_preprocess_preprocess_steps_free`.

  ov_color_format_e* = cint
    ## Color format of an input image. Width verified by the ABI test.

  ov_preprocess_resize_algorithm_e* = cint
    ## Resize algorithm. Width verified by the ABI test.

  ov_padding_mode_e* = cint
    ## Padding mode. Width verified by the ABI test.

const
  UNDEFINE* = ov_color_format_e(0)
    ## Undefined color format. Upstream spelling.
  NV12_SINGLE_PLANE* = ov_color_format_e(1)
    ## NV12 as a single tensor.
  NV12_TWO_PLANES* = ov_color_format_e(2)
    ## NV12 as separate Y and UV tensors.
  I420_SINGLE_PLANE* = ov_color_format_e(3)
    ## I420 as a single tensor.
  I420_THREE_PLANES* = ov_color_format_e(4)
    ## I420 as separate Y, U and V tensors.
  RGB* = ov_color_format_e(5)
    ## Interleaved RGB.
  BGR* = ov_color_format_e(6)
    ## Interleaved BGR.
  GRAY* = ov_color_format_e(7)
    ## Single-channel gray.
  RGBX* = ov_color_format_e(8)
    ## Interleaved RGBX.
  BGRX* = ov_color_format_e(9)
    ## Interleaved BGRX.

  RESIZE_LINEAR* = ov_preprocess_resize_algorithm_e(0)
    ## Linear interpolation.
  RESIZE_CUBIC* = ov_preprocess_resize_algorithm_e(1)
    ## Cubic interpolation.
  RESIZE_NEAREST* = ov_preprocess_resize_algorithm_e(2)
    ## Nearest neighbour.

  CONSTANT* = ov_padding_mode_e(0)
    ## Pad with a constant value.
  EDGE* = ov_padding_mode_e(1)
    ## Pad with edge values.
  REFLECT* = ov_padding_mode_e(2)
    ## Pad by reflection, edges not duplicated.
  SYMMETRIC* = ov_padding_mode_e(3)
    ## Pad by reflection, edges duplicated.

proc ov_preprocess_prepostprocessor_create*(
    model: ptr ov_model_t;
    preprocess: ptr ptr ov_preprocess_prepostprocessor_t): ov_status_e
  {.openvinoImport.}
  ## Creates a preprocessor for `model`. Holds a shared reference to the
  ## model, so releasing `model` afterwards is safe.

proc ov_preprocess_prepostprocessor_free*(
    preprocess: ptr ov_preprocess_prepostprocessor_t) {.openvinoImport.}
  ## Releases a preprocessor. Release every child object first.

proc ov_preprocess_prepostprocessor_get_input_info*(
    preprocess: ptr ov_preprocess_prepostprocessor_t;
    preprocess_input_info: ptr ptr ov_preprocess_input_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the only input's info. Fails on a model with several inputs.

proc ov_preprocess_prepostprocessor_get_input_info_by_name*(
    preprocess: ptr ov_preprocess_prepostprocessor_t; tensor_name: cstring;
    preprocess_input_info: ptr ptr ov_preprocess_input_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the info of the input named `tensor_name`.

proc ov_preprocess_prepostprocessor_get_input_info_by_index*(
    preprocess: ptr ov_preprocess_prepostprocessor_t; tensor_index: csize_t;
    preprocess_input_info: ptr ptr ov_preprocess_input_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the info of the input at `tensor_index`.

proc ov_preprocess_input_info_free*(
    preprocess_input_info: ptr ov_preprocess_input_info_t) {.openvinoImport.}
  ## Releases an input info wrapper.

proc ov_preprocess_input_info_get_tensor_info*(
    preprocess_input_info: ptr ov_preprocess_input_info_t;
    preprocess_input_tensor_info: ptr ptr ov_preprocess_input_tensor_info_t):
    ov_status_e {.openvinoImport.}
  ## Returns the input tensor description.

proc ov_preprocess_input_tensor_info_free*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t)
  {.openvinoImport.}
  ## Releases an input tensor info wrapper.

proc ov_preprocess_input_info_get_preprocess_steps*(
    preprocess_input_info: ptr ov_preprocess_input_info_t;
    preprocess_input_steps: ptr ptr ov_preprocess_preprocess_steps_t):
    ov_status_e {.openvinoImport.}
  ## Returns the step list of an input.

proc ov_preprocess_preprocess_steps_free*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t)
  {.openvinoImport.}
  ## Releases a step list wrapper.

proc ov_preprocess_preprocess_steps_resize*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    resize_algorithm: ov_preprocess_resize_algorithm_e): ov_status_e
  {.openvinoImport.}
  ## Adds a resize step.

proc ov_preprocess_preprocess_steps_scale*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    value: cfloat): ov_status_e {.openvinoImport.}
  ## Adds a step dividing every element by `value`.

proc ov_preprocess_preprocess_steps_scale_multi_channels*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    values: ptr cfloat; value_size: int32): ov_status_e {.openvinoImport.}
  ## Adds a per-channel scale step. `value_size` must be positive.

proc ov_preprocess_preprocess_steps_mean*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    value: cfloat): ov_status_e {.openvinoImport.}
  ## Adds a step subtracting `value` from every element.

proc ov_preprocess_preprocess_steps_mean_multi_channels*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    values: ptr cfloat; value_size: int32): ov_status_e {.openvinoImport.}
  ## Adds a per-channel mean step. `value_size` must be positive.

proc ov_preprocess_preprocess_steps_crop*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    begin: ptr int32; begin_size: int32; `end`: ptr int32;
    end_size: int32): ov_status_e {.openvinoImport.}
  ## Adds a crop step. The arrays are read, not retained; upstream does not
  ## check them for `nil`.

proc ov_preprocess_preprocess_steps_convert_layout*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    layout: ptr ov_layout_t): ov_status_e {.openvinoImport.}
  ## Adds a layout conversion step. The layout is copied.

proc ov_preprocess_preprocess_steps_reverse_channels*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t):
    ov_status_e {.openvinoImport.}
  ## Adds a step reversing the channel order.

proc ov_preprocess_input_tensor_info_set_element_type*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    element_type: ov_element_type_e): ov_status_e {.openvinoImport.}
  ## Declares the element type of the user's input tensor.

proc ov_preprocess_input_tensor_info_set_color_format*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    colorFormat: ov_color_format_e): ov_status_e {.openvinoImport.}
  ## Declares the color format with no plane sub-names.
  ##
  ## Not variadic itself; upstream forwards to the variadic function with
  ## zero names inside the library.

proc ov_preprocess_input_tensor_info_set_color_format_with_subnames*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    colorFormat: ov_color_format_e; sub_names_size: csize_t;
    sub_names: ptr cstring): ov_status_e {.openvinoImport.}
  ## Declares the color format and the names of its planes.
  ##
  ## The array form of the variadic `_with_subname`, which is not bound.

proc ov_preprocess_input_tensor_info_set_spatial_static_shape*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    input_height: csize_t; input_width: csize_t): ov_status_e
  {.openvinoImport.}
  ## Declares the static height and width of the user's input tensor.

proc ov_preprocess_input_tensor_info_set_memory_type*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    mem_type: cstring): ov_status_e {.openvinoImport.}
  ## Declares a device memory type. Remote memory is not part of the managed
  ## API.

proc ov_preprocess_preprocess_steps_convert_element_type*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    element_type: ov_element_type_e): ov_status_e {.openvinoImport.}
  ## Adds an element type conversion step.

proc ov_preprocess_preprocess_steps_convert_color*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    colorFormat: ov_color_format_e): ov_status_e {.openvinoImport.}
  ## Adds a color conversion step.

proc ov_preprocess_input_tensor_info_set_from*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    tensor: ptr ov_tensor_t): ov_status_e {.openvinoImport.}
  ## Takes element type and shape from `tensor`. The tensor is only read and
  ## may be released right after the call.

proc ov_preprocess_input_tensor_info_set_layout*(
    preprocess_input_tensor_info: ptr ov_preprocess_input_tensor_info_t;
    layout: ptr ov_layout_t): ov_status_e {.openvinoImport.}
  ## Declares the layout of the user's input tensor. The layout is copied.

proc ov_preprocess_prepostprocessor_get_output_info*(
    preprocess: ptr ov_preprocess_prepostprocessor_t;
    preprocess_output_info: ptr ptr ov_preprocess_output_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the only output's info. Fails on a model with several outputs.

proc ov_preprocess_prepostprocessor_get_output_info_by_index*(
    preprocess: ptr ov_preprocess_prepostprocessor_t; tensor_index: csize_t;
    preprocess_output_info: ptr ptr ov_preprocess_output_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the info of the output at `tensor_index`.

proc ov_preprocess_prepostprocessor_get_output_info_by_name*(
    preprocess: ptr ov_preprocess_prepostprocessor_t; tensor_name: cstring;
    preprocess_output_info: ptr ptr ov_preprocess_output_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the info of the output named `tensor_name`.

proc ov_preprocess_output_info_free*(
    preprocess_output_info: ptr ov_preprocess_output_info_t)
  {.openvinoImport.}
  ## Releases an output info wrapper.

proc ov_preprocess_output_info_get_tensor_info*(
    preprocess_output_info: ptr ov_preprocess_output_info_t;
    preprocess_output_tensor_info:
      ptr ptr ov_preprocess_output_tensor_info_t): ov_status_e
  {.openvinoImport.}
  ## Returns the output tensor description.

proc ov_preprocess_output_tensor_info_free*(
    preprocess_output_tensor_info: ptr ov_preprocess_output_tensor_info_t)
  {.openvinoImport.}
  ## Releases an output tensor info wrapper.

proc ov_preprocess_output_set_element_type*(
    preprocess_output_tensor_info: ptr ov_preprocess_output_tensor_info_t;
    element_type: ov_element_type_e): ov_status_e {.openvinoImport.}
  ## Declares the element type the user wants for the output.

proc ov_preprocess_input_info_get_model_info*(
    preprocess_input_info: ptr ov_preprocess_input_info_t;
    preprocess_input_model_info: ptr ptr ov_preprocess_input_model_info_t):
    ov_status_e {.openvinoImport.}
  ## Returns the model-side description of an input.

proc ov_preprocess_input_model_info_free*(
    preprocess_input_model_info: ptr ov_preprocess_input_model_info_t)
  {.openvinoImport.}
  ## Releases a model info wrapper.

proc ov_preprocess_input_model_info_set_layout*(
    preprocess_input_model_info: ptr ov_preprocess_input_model_info_t;
    layout: ptr ov_layout_t): ov_status_e {.openvinoImport.}
  ## Declares the model's own input layout. The layout is copied.

proc ov_preprocess_prepostprocessor_build*(
    preprocess: ptr ov_preprocess_prepostprocessor_t;
    model: ptr ptr ov_model_t): ov_status_e {.openvinoImport.}
  ## Applies every recorded step and returns the resulting model, owned by
  ## the caller.
  ##
  ## The result shares the source model's graph, which has been modified in
  ## place (measured in Phase 0, M-09).

proc ov_preprocess_preprocess_steps_pad*(
    preprocess_input_process_steps: ptr ov_preprocess_preprocess_steps_t;
    pads_begin: ptr cint; pads_begin_size: csize_t; pads_end: ptr cint;
    pads_end_size: csize_t; value: cfloat; mode: ov_padding_mode_e):
    ov_status_e {.openvinoImport.}
  ## Adds a padding step. Note the `int` arrays with `size_t` lengths, unlike
  ## `crop`; the steps pointer is `const` in the header.

{.pop.}

# Not part of the C ABI: name tables that let the ABI test walk every bound
# enumerator and compare it with the header, as `raw/common` does.

type ResizeAlgorithmValue = ov_preprocess_resize_algorithm_e
  ## Local shorthand that keeps the table declaration below on two lines.

const ColorFormats*: array[10, tuple[name: string;
                                     value: ov_color_format_e]] = [
  ("UNDEFINE", UNDEFINE),
  ("NV12_SINGLE_PLANE", NV12_SINGLE_PLANE),
  ("NV12_TWO_PLANES", NV12_TWO_PLANES),
  ("I420_SINGLE_PLANE", I420_SINGLE_PLANE),
  ("I420_THREE_PLANES", I420_THREE_PLANES),
  ("RGB", RGB),
  ("BGR", BGR),
  ("GRAY", GRAY),
  ("RGBX", RGBX),
  ("BGRX", BGRX)]
  ## Every bound `ov_color_format_e` constant with its upstream spelling.

const ResizeAlgorithms*: array[3, tuple[name: string;
                                        value: ResizeAlgorithmValue]] = [
  ("RESIZE_LINEAR", RESIZE_LINEAR),
  ("RESIZE_CUBIC", RESIZE_CUBIC),
  ("RESIZE_NEAREST", RESIZE_NEAREST)]
  ## Every bound `ov_preprocess_resize_algorithm_e` constant.

const PaddingModes*: array[4, tuple[name: string;
                                    value: ov_padding_mode_e]] = [
  ("CONSTANT", CONSTANT),
  ("EDGE", EDGE),
  ("REFLECT", REFLECT),
  ("SYMMETRIC", SYMMETRIC)]
  ## Every bound `ov_padding_mode_e` constant.
