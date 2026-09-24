# SPDX-License-Identifier: Apache-2.0

## Raw smoke tests against a real OpenVINO runtime.
##
## Unlike `tabi_layout.nim`, which only needs the headers, this file loads the
## installed runtime and calls it. It covers the Phase 2 gate items that cannot
## be checked statically: the library loads, the version can be read, a Core
## can be created and released, the non-variadic properties entry points
## resolve, and `ov_tensor_set_shape` really does take its shape by value.
##
## The by-value regression is the point of the tensor section. A pointer-passing
## declaration, which is what the Resonance prototype had, would read the shape
## struct from the wrong memory. Asserting that the call returns `OK` *and* that
## the resulting shape is the one requested is what distinguishes a correct
## signature from one that merely fails to crash.
##
## Run with `nimble testSmoke`. The test fails rather than skips when the
## runtime is missing, so a broken deployment cannot look like a pass.

import std/unittest

import openvino/raw/common
import openvino/raw/core
import openvino/raw/error
import openvino/raw/loader
import openvino/raw/shape
import openvino/raw/tensor

proc describe(status: ov_status_e; operation: string): string =
  ## Builds a failure message carrying the operation, the numeric status and
  ## OpenVINO's own description of it.
  result = operation & " returned " & $status & " (" &
    $ov_get_error_info(status) & ")"

suite "runtime loading":
  test "the OpenVINO C API library loads":
    # Resolving any symbol triggers the load, so a failure here is reported as
    # OpenVinoLibraryError with the full diagnostic rather than as a crash.
    discard functionSymbol("ov_core_create")
    check isRuntimeLoaded()

  test "every symbol the 0.1.0 surface needs resolves":
    # Required-symbol check. The `_props` entries are the reason this package
    # requires 2026.4, so their absence must be a clear failure here rather
    # than a mysterious one at the first compile call.
    let required = [
      "ov_core_create", "ov_core_free", "ov_core_read_model",
      "ov_core_get_available_devices", "ov_available_devices_free",
      "ov_core_import_model", "ov_core_get_property",
      "ov_core_set_properties", "ov_core_compile_model_props",
      "ov_core_compile_model_from_file_props",
      "ov_compiled_model_set_properties", "ov_compiled_model_get_property",
      "ov_compiled_model_create_infer_request",
      "ov_compiled_model_export_model", "ov_compiled_model_free",
      "ov_compiled_model_inputs_size", "ov_compiled_model_outputs_size",
      "ov_compiled_model_input_by_index", "ov_compiled_model_output_by_index",
      "ov_model_free", "ov_model_inputs_size", "ov_model_outputs_size",
      "ov_model_const_input_by_index", "ov_model_const_output_by_index",
      "ov_model_is_dynamic", "ov_model_get_friendly_name",
      "ov_port_get_any_name", "ov_port_get_element_type",
      "ov_const_port_get_shape", "ov_output_const_port_free",
      "ov_shape_create", "ov_shape_free",
      "ov_tensor_create", "ov_tensor_create_from_host_ptr",
      "ov_tensor_set_shape", "ov_tensor_get_shape",
      "ov_tensor_get_element_type", "ov_tensor_get_size",
      "ov_tensor_get_byte_size", "ov_tensor_data", "ov_tensor_free",
      "ov_infer_request_set_input_tensor_by_index",
      "ov_infer_request_get_output_tensor_by_index",
      "ov_infer_request_get_input_tensor_by_index",
      "ov_infer_request_set_tensor", "ov_infer_request_get_tensor",
      "ov_infer_request_infer", "ov_infer_request_get_profiling_info",
      "ov_profiling_info_list_free", "ov_infer_request_free",
      "ov_get_openvino_version", "ov_version_free",
      "ov_get_error_info", "ov_get_last_err_msg", "ov_free"]
    let missing = missingSymbols(required)
    if missing.len > 0:
      checkpoint("missing: " & $missing)
    check missing.len == 0

  test "the exported enable_profiling property key is a non-empty string":
    # Property keys are exported data symbols, not macros, so this also proves
    # the data-symbol path works. The prototype hand-wrote "PERF_COUNT".
    let key = stringDataSymbol("ov_property_key_enable_profiling")
    checkpoint("ov_property_key_enable_profiling = " & $key)
    check key != nil
    check ($key).len > 0

suite "runtime version":
  test "the runtime reports a build number and a description":
    var version: ov_version_t
    let status = ov_get_openvino_version(addr version)
    if status != OK:
      checkpoint(describe(status, "ov_get_openvino_version"))
    check status == OK
    if status == OK:
      # Copy before releasing: both strings belong to OpenVINO.
      let
        build = $version.buildNumber
        description = $version.description
      ov_version_free(addr version)
      checkpoint("build=" & build & " description=" & description)
      check build.len > 0
      check description.len > 0

suite "core lifetime":
  test "a Core can be created and released":
    var core: ptr ov_core_t = nil
    let status = ov_core_create(addr core)
    if status != OK:
      checkpoint(describe(status, "ov_core_create"))
      checkpoint("native detail: " & $ov_get_last_err_msg())
    check status == OK
    check core != nil
    if core != nil:
      ov_core_free(core)

  test "available devices can be listed and released":
    var core: ptr ov_core_t = nil
    check ov_core_create(addr core) == OK
    check core != nil
    if core != nil:
      var devices: ov_available_devices_t
      let status = ov_core_get_available_devices(core, addr devices)
      if status != OK:
        checkpoint(describe(status, "ov_core_get_available_devices"))
      check status == OK
      if status == OK:
        var names: seq[string] = @[]
        for index in 0 ..< int(devices.size):
          names.add($devices.devices[index])
        # Released unconditionally on success, not only when size is non-zero.
        ov_available_devices_free(addr devices)
        checkpoint("devices: " & $names)
        check names.len > 0
      ov_core_free(core)

suite "ov_tensor_set_shape takes its shape by value":
  test "a tensor can be created from a by-value shape":
    var dims = [int64(1), 3, 8]
    var created: ov_shape_t
    check ov_shape_create(int64(dims.len), addr dims[0], addr created) == OK

    var tensor: ptr ov_tensor_t = nil
    let status = ov_tensor_create(F32, created, addr tensor)
    if status != OK:
      checkpoint(describe(status, "ov_tensor_create"))
    check status == OK
    check tensor != nil
    discard ov_shape_free(addr created)

    if tensor != nil:
      var elements: csize_t = 0
      check ov_tensor_get_size(tensor, addr elements) == OK
      checkpoint("elements=" & $elements)
      check elements == csize_t(24)
      ov_tensor_free(tensor)

  test "setting a larger shape by value is observed by the tensor":
    # The real regression. A pointer-passing declaration would hand OpenVINO
    # the wrong bytes, so requiring the *observed* shape to match what was
    # requested is what makes this test meaningful.
    var initialDims = [int64(1), 2, 2]
    var initial: ov_shape_t
    check ov_shape_create(int64(initialDims.len), addr initialDims[0],
                          addr initial) == OK
    var tensor: ptr ov_tensor_t = nil
    check ov_tensor_create(F32, initial, addr tensor) == OK
    discard ov_shape_free(addr initial)
    check tensor != nil

    if tensor != nil:
      var replacementDims = [int64(2), 3, 4]
      var replacement: ov_shape_t
      check ov_shape_create(int64(replacementDims.len), addr replacementDims[0],
                            addr replacement) == OK
      let status = ov_tensor_set_shape(tensor, replacement)
      if status != OK:
        checkpoint(describe(status, "ov_tensor_set_shape"))
        checkpoint("native detail: " & $ov_get_last_err_msg())
      check status == OK
      discard ov_shape_free(addr replacement)

      var observed: ov_shape_t
      check ov_tensor_get_shape(tensor, addr observed) == OK
      var observedDims: seq[int64] = @[]
      for index in 0 ..< int(observed.rank):
        observedDims.add(cast[ptr UncheckedArray[int64]](observed.dims)[index])
      discard ov_shape_free(addr observed)
      checkpoint("observed shape: " & $observedDims)
      check observedDims == @[int64(2), 3, 4]

      var elements: csize_t = 0
      check ov_tensor_get_size(tensor, addr elements) == OK
      check elements == csize_t(24)

      var byteSize: csize_t = 0
      check ov_tensor_get_byte_size(tensor, addr byteSize) == OK
      checkpoint("byte size=" & $byteSize)
      check byteSize == csize_t(24 * 4)

      var elementType: ov_element_type_e = DYNAMIC
      check ov_tensor_get_element_type(tensor, addr elementType) == OK
      check elementType == F32

      ov_tensor_free(tensor)
