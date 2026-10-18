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
##
## The suites marked `0.2.0` pin the upstream behaviour measured in Phase 0 of
## the 0.2 plan (M-01 to M-10) and the quirks the managed layer works around.
## They are regressions in both directions: if OpenVINO fixes a quirk, the test
## fails and the workaround is re-examined rather than silently kept.

import std/[atomics, os, unittest]

import openvino/raw

proc describe(status: ov_status_e; operation: string): string =
  ## Builds a failure message carrying the operation, the numeric status and
  ## OpenVINO's own description of it.
  result = operation & " returned " & $status & " (" &
    $ov_get_error_info(status) & ")"

const fixturePath = currentSourcePath().parentDir.parentDir / "fixtures" /
  "relu_1x4_f32.xml"
  ## The `[1, 4]` f32 ReLU model shared with the integration tests.

const busyLength = 32_000_000'i64
  ## Width the fixture is reshaped to when a test needs a request that stays
  ## busy for a while. Measured at about 40 ms per inference on the Phase 0
  ## host, which is long enough to observe it running.

proc dim(lo, hi: int64): ov_dimension_t = ov_dimension_t(min: lo, max: hi)

proc reshapeInput0(model: ptr ov_model_t; rank: ov_dimension_t;
                   dims: openArray[ov_dimension_t]): ov_status_e =
  ## Reshapes input 0 with a caller-built partial shape, the way the managed
  ## layer does: `dims` points at Nim memory alive for the call, and the
  ## struct is never passed to `ov_partial_shape_free`.
  var storage = @dims
  var shape = ov_partial_shape_t(rank: rank, dims: nil)
  if storage.len > 0:
    shape.dims = addr storage[0]
  result = ov_model_reshape_single_input(model, shape)

proc readDims(shape: ov_partial_shape_t): seq[ov_dimension_t] =
  ## Copies the dimensions of a partial shape OpenVINO filled.
  result = @[]
  if shape.dims != nil:
    let dims = cast[ptr UncheckedArray[ov_dimension_t]](shape.dims)
    for index in 0 ..< int(shape.rank.max):
      result.add(dims[index])

proc inputPartialShape(model: ptr ov_model_t): ov_partial_shape_t =
  ## Reads input 0's partial shape. The caller releases it.
  var port: ptr ov_output_const_port_t = nil
  doAssert ov_model_const_input_by_index(model, 0, addr port) == OK
  doAssert ov_port_get_partial_shape(port, addr result) == OK
  ov_output_const_port_free(port)

proc inputElementType(model: ptr ov_model_t): ov_element_type_e =
  var port: ptr ov_output_const_port_t = nil
  doAssert ov_model_const_input_by_index(model, 0, addr port) == OK
  doAssert ov_port_get_element_type(port, addr result) == OK
  ov_output_const_port_free(port)

proc shapeString(shape: ov_partial_shape_t): string =
  let text = ov_partial_shape_to_string(shape)
  result = $text
  ov_free(text)

proc tensorDims(tensor: ptr ov_tensor_t): seq[int64] =
  var shape: ov_shape_t
  doAssert ov_tensor_get_shape(tensor, addr shape) == OK
  let dims = cast[ptr UncheckedArray[int64]](shape.dims)
  for index in 0 ..< int(shape.rank):
    result.add(dims[index])
  discard ov_shape_free(addr shape)

proc newTensorOf(elementType: ov_element_type_e;
                 dims: openArray[int64]): ptr ov_tensor_t =
  var storage = @dims
  let shape = ov_shape_t(rank: int64(storage.len), dims: addr storage[0])
  doAssert ov_tensor_create(elementType, shape, addr result) == OK

type Fixture = object
  ## A Core with the fixture read into it. Each test releases what it made.
  core: ptr ov_core_t

proc openFixture(): Fixture =
  doAssert ov_core_create(addr result.core) == OK

proc readModel(fixture: Fixture): ptr ov_model_t =
  doAssert ov_core_read_model(fixture.core, fixturePath.cstring, nil,
                              addr result) == OK

proc compileCpu(fixture: Fixture; model: ptr ov_model_t;
                compiled: var ptr ov_compiled_model_t): ov_status_e =
  ov_core_compile_model_props(fixture.core, model, "CPU", 0, nil,
                              addr compiled)

proc requestFor(fixture: Fixture; reshapeTo: openArray[ov_dimension_t]):
    tuple[compiled: ptr ov_compiled_model_t; request: ptr ov_infer_request_t] =
  ## Compiles the fixture, optionally reshaped, and creates one request.
  let model = fixture.readModel()
  if reshapeTo.len > 0:
    doAssert reshapeInput0(model, dim(reshapeTo.len, reshapeTo.len),
                           reshapeTo) == OK
  doAssert fixture.compileCpu(model, result.compiled) == OK
  ov_model_free(model)
  doAssert ov_compiled_model_create_infer_request(result.compiled,
                                                  addr result.request) == OK

proc release(pair: tuple[compiled: ptr ov_compiled_model_t;
                         request: ptr ov_infer_request_t]) =
  ov_infer_request_free(pair.request)
  ov_compiled_model_free(pair.compiled)

var
  callbacksEntered: Atomic[int]
  callbacksFinished: Atomic[int]

proc countCompletion(args: pointer) {.cdecl, gcsafe, raises: [].} =
  ## Test callback: only atomic counters, as required on a foreign thread.
  ## The loop gives a late `wait` a window to overtake an unfinished callback.
  discard callbacksEntered.fetchAdd(1)
  var spin = 0
  for step in 0 ..< 20_000:
    spin += step and 1
  if spin < 0:
    discard callbacksEntered.fetchAdd(1)
  discard callbacksFinished.fetchAdd(1)

var completionSlot = ov_callback_t(callback_func: countCompletion, args: nil)
  ## Global, so its address is stable for as long as any request may use it.

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

  test "every symbol the 0.2.0 raw additions declare resolves":
    let required = [
      "ov_infer_request_start_async", "ov_infer_request_wait",
      "ov_infer_request_wait_for", "ov_infer_request_cancel",
      "ov_infer_request_set_callback", "ov_infer_request_set_input_tensor",
      "ov_infer_request_get_input_tensor",
      "ov_infer_request_set_output_tensor_by_index",
      "ov_infer_request_set_output_tensor",
      "ov_infer_request_get_output_tensor",
      "ov_infer_request_get_tensor_by_const_port",
      "ov_dimension_is_dynamic", "ov_rank_is_dynamic",
      "ov_partial_shape_create", "ov_partial_shape_create_dynamic",
      "ov_partial_shape_create_static", "ov_partial_shape_free",
      "ov_partial_shape_to_shape", "ov_shape_to_partial_shape",
      "ov_partial_shape_is_dynamic", "ov_partial_shape_to_string",
      "ov_port_get_partial_shape",
      "ov_model_reshape", "ov_model_reshape_input_by_name",
      "ov_model_reshape_single_input", "ov_model_reshape_by_port_indexes",
      "ov_layout_create", "ov_layout_free", "ov_layout_to_string",
      "ov_preprocess_prepostprocessor_create",
      "ov_preprocess_prepostprocessor_free",
      "ov_preprocess_prepostprocessor_get_input_info",
      "ov_preprocess_prepostprocessor_get_input_info_by_name",
      "ov_preprocess_prepostprocessor_get_input_info_by_index",
      "ov_preprocess_input_info_free",
      "ov_preprocess_input_info_get_tensor_info",
      "ov_preprocess_input_tensor_info_free",
      "ov_preprocess_input_info_get_preprocess_steps",
      "ov_preprocess_preprocess_steps_free",
      "ov_preprocess_preprocess_steps_resize",
      "ov_preprocess_preprocess_steps_scale",
      "ov_preprocess_preprocess_steps_scale_multi_channels",
      "ov_preprocess_preprocess_steps_mean",
      "ov_preprocess_preprocess_steps_mean_multi_channels",
      "ov_preprocess_preprocess_steps_crop",
      "ov_preprocess_preprocess_steps_convert_layout",
      "ov_preprocess_preprocess_steps_reverse_channels",
      "ov_preprocess_input_tensor_info_set_element_type",
      "ov_preprocess_input_tensor_info_set_color_format",
      "ov_preprocess_input_tensor_info_set_color_format_with_subnames",
      "ov_preprocess_input_tensor_info_set_spatial_static_shape",
      "ov_preprocess_input_tensor_info_set_memory_type",
      "ov_preprocess_preprocess_steps_convert_element_type",
      "ov_preprocess_preprocess_steps_convert_color",
      "ov_preprocess_input_tensor_info_set_from",
      "ov_preprocess_input_tensor_info_set_layout",
      "ov_preprocess_prepostprocessor_get_output_info",
      "ov_preprocess_prepostprocessor_get_output_info_by_index",
      "ov_preprocess_prepostprocessor_get_output_info_by_name",
      "ov_preprocess_output_info_free",
      "ov_preprocess_output_info_get_tensor_info",
      "ov_preprocess_output_tensor_info_free",
      "ov_preprocess_output_set_element_type",
      "ov_preprocess_input_info_get_model_info",
      "ov_preprocess_input_model_info_free",
      "ov_preprocess_input_model_info_set_layout",
      "ov_preprocess_prepostprocessor_build",
      "ov_preprocess_preprocess_steps_pad"]
    let missing = missingSymbols(required)
    if missing.len > 0:
      checkpoint("missing: " & $missing)
    check missing.len == 0

  test "every bound property key resolves to a non-empty string":
    # Property keys are exported data symbols, not macros, so this also proves
    # the data-symbol path works. The prototype hand-wrote "PERF_COUNT".
    let keys = {
      "enable_profiling": ov_property_key_enable_profiling(),
      "available_devices": ov_property_key_available_devices(),
      "device_full_name": ov_property_key_device_full_name(),
      "supported_properties": ov_property_key_supported_properties(),
      "cache_dir": ov_property_key_cache_dir(),
      "num_streams": ov_property_key_num_streams(),
      "inference_num_threads": ov_property_key_inference_num_threads(),
      "hint_performance_mode": ov_property_key_hint_performance_mode(),
      "hint_inference_precision": ov_property_key_hint_inference_precision(),
      "log_level": ov_property_key_log_level()}
    for (label, key) in keys:
      checkpoint(label & " = " & $key)
      check key != nil
      check ($key).len > 0

  test "the profiling status enumerators match the probed header values":
    check PROFILING_NOT_RUN == ov_status_e(0)
    check PROFILING_OPTIMIZED_OUT == ov_status_e(1)
    check PROFILING_EXECUTED == ov_status_e(2)

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

suite "partial shapes and their quirks (0.2.0, M-06, M-07)":
  test "partial shapes are passed by value: to_string sees the dimensions":
    var dims = [dim(1, 8), dim(4, 4)]
    let shape = ov_partial_shape_t(rank: dim(2, 2), dims: addr dims[0])
    check shapeString(shape) == "{1..8,4}"

  test "the create functions reject the {0,-1} form that ports report":
    var shape: ov_partial_shape_t
    var portForm = [dim(0, -1), dim(4, 4)]
    check ov_partial_shape_create_dynamic(dim(2, 2), addr portForm[0],
                                          addr shape) == INVALID_C_PARAM
    var lowerBounded = [dim(2, -1)]
    check ov_partial_shape_create(1, addr lowerBounded[0], addr shape) ==
      INVALID_C_PARAM
    var legacyForm = [dim(-1, -1), dim(4, 4)]
    shape = ov_partial_shape_t()
    check ov_partial_shape_create_dynamic(dim(2, 2), addr legacyForm[0],
                                          addr shape) == OK
    check shapeString(shape) == "{?,4}"
    ov_partial_shape_free(addr shape)

  test "the is_dynamic predicates misreport zero length and rank 0":
    check ov_dimension_is_dynamic(dim(0, 0))
    check not ov_dimension_is_dynamic(dim(4, 4))
    check ov_rank_is_dynamic(dim(0, 0))
    check not ov_rank_is_dynamic(dim(2, 2))

  test "a static shape converts to a partial shape and back to text":
    var dims = [int64(2), 3]
    let shape = ov_shape_t(rank: 2, dims: addr dims[0])
    var partial: ov_partial_shape_t
    check ov_shape_to_partial_shape(shape, addr partial) == OK
    check readDims(partial) == @[dim(2, 2), dim(3, 3)]
    check not ov_partial_shape_is_dynamic(partial)
    ov_partial_shape_free(addr partial)

  test "caller-built reshapes read back in canonical form":
    let fixture = openFixture()
    let cases = [
      (@[dim(-1, -1), dim(4, 4)], @[dim(0, -1), dim(4, 4)], "{?,4}"),
      (@[dim(0, -1), dim(4, 4)], @[dim(0, -1), dim(4, 4)], "{?,4}"),
      (@[dim(2, -1), dim(4, 4)], @[dim(2, -1), dim(4, 4)], "{2..,4}"),
      (@[dim(1, 8), dim(4, 4)], @[dim(1, 8), dim(4, 4)], "{1..8,4}"),
      (@[dim(0, 0), dim(4, 4)], @[dim(0, 0), dim(4, 4)], "{0,4}")]
    for (written, expected, text) in cases:
      let model = fixture.readModel()
      check reshapeInput0(model, dim(2, 2), written) == OK
      var shape = inputPartialShape(model)
      checkpoint("wrote " & $written & " read " & shapeString(shape))
      check shape.rank == dim(2, 2)
      check readDims(shape) == expected
      check shapeString(shape) == text
      ov_partial_shape_free(addr shape)
      ov_model_free(model)
    ov_core_free(fixture.core)

  test "rank 0 and a dynamic rank silently become [?] through C reshape":
    # The reason the managed `reshape` rejects both before calling C. If this
    # starts failing, upstream fixed the conversion and the rejection can be
    # reconsidered.
    let fixture = openFixture()
    for rank in [dim(0, 0), dim(0, -1), dim(-1, -1)]:
      let model = fixture.readModel()
      check reshapeInput0(model, rank, []) == OK
      var shape = inputPartialShape(model)
      checkpoint("rank " & $rank & " read " & shapeString(shape))
      check shape.rank == dim(1, 1)
      check readDims(shape) == @[dim(0, -1)]
      ov_partial_shape_free(addr shape)
      ov_model_free(model)
    ov_core_free(fixture.core)

  test "the batch reshape and the by-index reshape apply atomically":
    let fixture = openFixture()
    let model = fixture.readModel()
    var dims = [dim(3, 3), dim(4, 4)]
    var shapes = [ov_partial_shape_t(rank: dim(2, 2), dims: addr dims[0])]
    var names = [cstring("input")]
    check ov_model_reshape(model, addr names[0], addr shapes[0], 1) == OK
    var shape = inputPartialShape(model)
    check shapeString(shape) == "{3,4}"
    ov_partial_shape_free(addr shape)
    var index = [csize_t(0)]
    dims[0] = dim(5, 5)
    check ov_model_reshape_by_port_indexes(model, addr index[0],
                                           addr shapes[0], 1) == OK
    shape = inputPartialShape(model)
    check shapeString(shape) == "{5,4}"
    ov_partial_shape_free(addr shape)
    dims[0] = dim(6, 6)
    check ov_model_reshape_input_by_name(model, "input", shapes[0]) == OK
    shape = inputPartialShape(model)
    check shapeString(shape) == "{6,4}"
    ov_partial_shape_free(addr shape)
    names[0] = "no-such-input"
    check ov_model_reshape(model, addr names[0], addr shapes[0], 1) != OK
    ov_model_free(model)
    ov_core_free(fixture.core)

suite "dynamic inference (0.2.0, M-08)":
  test "an unbound dynamic input reads as [0, 4] and batches 1, 3, 7 infer":
    let fixture = openFixture()
    let pair = fixture.requestFor([dim(-1, -1), dim(4, 4)])
    var port: ptr ov_output_const_port_t = nil
    check ov_compiled_model_input_by_index(pair.compiled, 0, addr port) == OK
    var compiledShape: ov_partial_shape_t
    check ov_port_get_partial_shape(port, addr compiledShape) == OK
    check shapeString(compiledShape) == "{?,4}"
    ov_partial_shape_free(addr compiledShape)
    ov_output_const_port_free(port)

    var unbound: ptr ov_tensor_t = nil
    check ov_infer_request_get_input_tensor_by_index(pair.request, 0,
                                                     addr unbound) == OK
    check tensorDims(unbound) == @[int64(0), 4]
    ov_tensor_free(unbound)

    for batch in [int64(1), 3, 7]:
      let input = newTensorOf(F32, [batch, 4])
      var data: pointer
      check ov_tensor_data(input, addr data) == OK
      let values = cast[ptr UncheckedArray[float32]](data)
      for index in 0 ..< int(batch * 4):
        values[index] = (if index mod 2 == 0: -float32(index)
          else: float32(index))
      check ov_infer_request_set_input_tensor_by_index(pair.request, 0,
                                                       input) == OK
      check ov_infer_request_infer(pair.request) == OK
      var output: ptr ov_tensor_t = nil
      check ov_infer_request_get_output_tensor_by_index(pair.request, 0,
                                                        addr output) == OK
      check tensorDims(output) == @[batch, 4]
      check ov_tensor_data(output, addr data) == OK
      let results = cast[ptr UncheckedArray[float32]](data)
      for index in 0 ..< int(batch * 4):
        let expected = (if index mod 2 == 0: 0'f32 else: float32(index))
        check results[index] == expected
      ov_tensor_free(output)
      ov_tensor_free(input)
    release(pair)
    ov_core_free(fixture.core)

  test "binding outside a bounded dimension fails with GENERAL_ERROR":
    let fixture = openFixture()
    let pair = fixture.requestFor([dim(1, 8), dim(4, 4)])
    let tooLarge = newTensorOf(F32, [int64(9), 4])
    check ov_infer_request_set_input_tensor_by_index(pair.request, 0,
                                                     tooLarge) ==
      GENERAL_ERROR
    ov_tensor_free(tooLarge)
    release(pair)
    ov_core_free(fixture.core)

suite "asynchronous inference (0.2.0, M-01 to M-05)":
  test "a running request reports REQUEST_BUSY to every call (M-01)":
    let fixture = openFixture()
    let pair = fixture.requestFor([dim(1, 1), dim(busyLength, busyLength)])
    var input: ptr ov_tensor_t = nil
    check ov_infer_request_get_input_tensor_by_index(pair.request, 0,
                                                     addr input) == OK
    var observed = false
    for attempt in 1 .. 5:
      check ov_infer_request_start_async(pair.request) == OK
      if ov_infer_request_wait_for(pair.request, 0) == RESULT_NOT_READY:
        check ov_infer_request_start_async(pair.request) == REQUEST_BUSY
        check ov_infer_request_infer(pair.request) == REQUEST_BUSY
        check ov_infer_request_set_input_tensor_by_index(pair.request, 0,
                                                         input) == REQUEST_BUSY
        var output: ptr ov_tensor_t = nil
        check ov_infer_request_get_output_tensor_by_index(
          pair.request, 0, addr output) == REQUEST_BUSY
        observed = ov_infer_request_wait_for(pair.request, 0) ==
          RESULT_NOT_READY
      check ov_infer_request_wait(pair.request) == OK
      if observed:
        break
    if not observed:
      checkpoint("the request finished before it could be observed running")
    check observed
    ov_tensor_free(input)
    release(pair)
    ov_core_free(fixture.core)

  test "wait after cancel reports INFER_CANCELLED until restarted (M-02)":
    let fixture = openFixture()
    let pair = fixture.requestFor([dim(1, 1), dim(busyLength, busyLength)])
    check ov_infer_request_start_async(pair.request) == OK
    check ov_infer_request_cancel(pair.request) == OK
    check ov_infer_request_wait(pair.request) == INFER_CANCELLED
    check ov_infer_request_wait(pair.request) == INFER_CANCELLED
    check ov_infer_request_infer(pair.request) == OK
    check ov_infer_request_cancel(pair.request) == OK
    check ov_infer_request_wait(pair.request) == OK
    release(pair)
    ov_core_free(fixture.core)

  test "wait and wait_for disagree on a never-started request (M-03)":
    let fixture = openFixture()
    let pair = fixture.requestFor([])
    check ov_infer_request_wait(pair.request) == OK
    check ov_infer_request_wait_for(pair.request, 0) == RESULT_NOT_READY
    check ov_infer_request_wait_for(pair.request, -1) == GENERAL_ERROR
    check ov_infer_request_cancel(pair.request) == OK
    release(pair)
    ov_core_free(fixture.core)

  test "the callback has finished before wait returns (M-05)":
    let fixture = openFixture()
    let pair = fixture.requestFor([])
    check ov_infer_request_set_callback(pair.request,
                                        addr completionSlot) == OK
    callbacksEntered.store(0)
    callbacksFinished.store(0)
    var late = 0
    for round in 1 .. 200:
      check ov_infer_request_start_async(pair.request) == OK
      check ov_infer_request_wait(pair.request) == OK
      if callbacksFinished.load() != round:
        inc late
        while callbacksFinished.load() < round:
          discard
    check late == 0
    check ov_infer_request_infer(pair.request) == OK
    sleep(20)
    check callbacksFinished.load() == 200
    release(pair)
    ov_core_free(fixture.core)

  test "a cancelled run still invokes the callback (M-05)":
    let fixture = openFixture()
    let pair = fixture.requestFor([dim(1, 1), dim(busyLength, busyLength)])
    check ov_infer_request_set_callback(pair.request,
                                        addr completionSlot) == OK
    callbacksFinished.store(0)
    check ov_infer_request_start_async(pair.request) == OK
    check ov_infer_request_cancel(pair.request) == OK
    check ov_infer_request_wait(pair.request) == INFER_CANCELLED
    check callbacksFinished.load() == 1
    release(pair)
    ov_core_free(fixture.core)

suite "layouts (0.2.0)":
  test "layouts parse and format in bracket form":
    for (text, expected) in [("NCHW", "[N,C,H,W]"), ("nchw", "[N,C,H,W]"),
                             ("NC?", "[N,C,?]"), ("...C", "[...,C]"),
                             ("", "[...]")]:
      var layout: ptr ov_layout_t = nil
      check ov_layout_create(text.cstring, addr layout) == OK
      let formatted = ov_layout_to_string(layout)
      checkpoint(text & " -> " & $formatted)
      check $formatted == expected
      ov_free(formatted)
      ov_layout_free(layout)

  test "a repeated dimension name is rejected":
    var layout: ptr ov_layout_t = nil
    check ov_layout_create("NCHWN", addr layout) == GENERAL_ERROR

suite "preprocessing (0.2.0, M-09, M-10)":
  test "build modifies the source model, and the result outlives it (M-09)":
    let fixture = openFixture()
    let source = fixture.readModel()
    var preprocess: ptr ov_preprocess_prepostprocessor_t = nil
    check ov_preprocess_prepostprocessor_create(source, addr preprocess) == OK
    var info: ptr ov_preprocess_input_info_t = nil
    check ov_preprocess_prepostprocessor_get_input_info_by_index(
      preprocess, 0, addr info) == OK
    var tensorInfo: ptr ov_preprocess_input_tensor_info_t = nil
    check ov_preprocess_input_info_get_tensor_info(info, addr tensorInfo) == OK
    check ov_preprocess_input_tensor_info_set_element_type(tensorInfo,
                                                           U8) == OK
    ov_preprocess_input_tensor_info_free(tensorInfo)
    ov_preprocess_input_info_free(info)
    var built: ptr ov_model_t = nil
    check ov_preprocess_prepostprocessor_build(preprocess, addr built) == OK
    ov_preprocess_prepostprocessor_free(preprocess)
    check inputElementType(source) == U8
    check inputElementType(built) == U8
    ov_model_free(source)
    check inputElementType(built) == U8
    ov_model_free(built)
    ov_core_free(fixture.core)

  test "the sample given to set_from may be released before build (M-10)":
    let fixture = openFixture()
    let source = fixture.readModel()
    var preprocess: ptr ov_preprocess_prepostprocessor_t = nil
    check ov_preprocess_prepostprocessor_create(source, addr preprocess) == OK
    ov_model_free(source)
    var info: ptr ov_preprocess_input_info_t = nil
    check ov_preprocess_prepostprocessor_get_input_info_by_name(
      preprocess, "input", addr info) == OK
    var tensorInfo: ptr ov_preprocess_input_tensor_info_t = nil
    check ov_preprocess_input_info_get_tensor_info(info, addr tensorInfo) == OK
    let sample = newTensorOf(U8, [int64(1), 4])
    check ov_preprocess_input_tensor_info_set_from(tensorInfo, sample) == OK
    ov_tensor_free(sample)
    ov_preprocess_input_tensor_info_free(tensorInfo)
    ov_preprocess_input_info_free(info)
    var built: ptr ov_model_t = nil
    check ov_preprocess_prepostprocessor_build(preprocess, addr built) == OK
    ov_preprocess_prepostprocessor_free(preprocess)

    var compiled: ptr ov_compiled_model_t = nil
    check fixture.compileCpu(built, compiled) == OK
    ov_model_free(built)
    var request: ptr ov_infer_request_t = nil
    check ov_compiled_model_create_infer_request(compiled, addr request) == OK
    let input = newTensorOf(U8, [int64(1), 4])
    var data: pointer
    check ov_tensor_data(input, addr data) == OK
    let bytes = cast[ptr UncheckedArray[uint8]](data)
    for index, value in [3'u8, 0, 200, 9]:
      bytes[index] = value
    check ov_infer_request_set_input_tensor(request, input) == OK
    check ov_infer_request_infer(request) == OK
    var output: ptr ov_tensor_t = nil
    check ov_infer_request_get_output_tensor(request, addr output) == OK
    check ov_tensor_data(output, addr data) == OK
    let results = cast[ptr UncheckedArray[float32]](data)
    check [results[0], results[1], results[2], results[3]] ==
      [3'f32, 0, 200, 9]
    ov_tensor_free(output)
    ov_tensor_free(input)
    ov_infer_request_free(request)
    ov_compiled_model_free(compiled)
    ov_core_free(fixture.core)

  test "every child object, step and output setter can be driven":
    # Exercises the remaining declarations with real calls, so a wrong
    # signature fails here rather than in the managed layer. The model
    # becomes u8 NHWC input, f32 NCHW inside, f32 output.
    let fixture = openFixture()
    let source = fixture.readModel()
    check reshapeInput0(source, dim(4, 4),
                        [dim(1, 1), dim(3, 3), dim(4, 4), dim(4, 4)]) == OK
    var preprocess: ptr ov_preprocess_prepostprocessor_t = nil
    check ov_preprocess_prepostprocessor_create(source, addr preprocess) == OK
    var info: ptr ov_preprocess_input_info_t = nil
    check ov_preprocess_prepostprocessor_get_input_info(preprocess,
                                                        addr info) == OK
    var tensorInfo: ptr ov_preprocess_input_tensor_info_t = nil
    check ov_preprocess_input_info_get_tensor_info(info, addr tensorInfo) == OK
    var nhwc, nchw: ptr ov_layout_t = nil
    check ov_layout_create("NHWC", addr nhwc) == OK
    check ov_layout_create("NCHW", addr nchw) == OK
    check ov_preprocess_input_tensor_info_set_element_type(tensorInfo,
                                                           U8) == OK
    check ov_preprocess_input_tensor_info_set_layout(tensorInfo, nhwc) == OK
    check ov_preprocess_input_tensor_info_set_spatial_static_shape(
      tensorInfo, 6, 6) == OK
    check ov_preprocess_input_tensor_info_set_color_format(tensorInfo,
                                                           RGB) == OK
    var noNames: ptr cstring = nil
    check ov_preprocess_input_tensor_info_set_color_format_with_subnames(
      tensorInfo, RGB, 0, noNames) == OK
    var steps: ptr ov_preprocess_preprocess_steps_t = nil
    check ov_preprocess_input_info_get_preprocess_steps(info,
                                                        addr steps) == OK
    check ov_preprocess_preprocess_steps_convert_element_type(steps,
                                                              F32) == OK
    check ov_preprocess_preprocess_steps_convert_color(steps, BGR) == OK
    check ov_preprocess_preprocess_steps_reverse_channels(steps) == OK
    var begin = [int32(0), 1, 1, 0]
    var finish = [int32(1), 5, 5, 3]
    check ov_preprocess_preprocess_steps_crop(steps, addr begin[0], 4,
                                              addr finish[0], 4) == OK
    var padBegin = [cint(0), 0, 0, 0]
    var padEnd = [cint(0), 0, 0, 0]
    check ov_preprocess_preprocess_steps_pad(steps, addr padBegin[0], 4,
                                             addr padEnd[0], 4, 0,
                                             CONSTANT) == OK
    check ov_preprocess_preprocess_steps_resize(steps, RESIZE_NEAREST) == OK
    var means = [cfloat(1), 2, 3]
    check ov_preprocess_preprocess_steps_mean_multi_channels(
      steps, addr means[0], 3) == OK
    check ov_preprocess_preprocess_steps_mean(steps, 0.5) == OK
    var scales = [cfloat(2), 2, 2]
    check ov_preprocess_preprocess_steps_scale_multi_channels(
      steps, addr scales[0], 3) == OK
    check ov_preprocess_preprocess_steps_scale(steps, 1) == OK
    check ov_preprocess_preprocess_steps_convert_layout(steps, nchw) == OK
    var modelInfo: ptr ov_preprocess_input_model_info_t = nil
    check ov_preprocess_input_info_get_model_info(info, addr modelInfo) == OK
    check ov_preprocess_input_model_info_set_layout(modelInfo, nchw) == OK
    ov_layout_free(nhwc)
    ov_layout_free(nchw)

    var outputInfo: ptr ov_preprocess_output_info_t = nil
    check ov_preprocess_prepostprocessor_get_output_info_by_index(
      preprocess, 0, addr outputInfo) == OK
    ov_preprocess_output_info_free(outputInfo)
    check ov_preprocess_prepostprocessor_get_output_info_by_name(
      preprocess, "output", addr outputInfo) == OK
    ov_preprocess_output_info_free(outputInfo)
    check ov_preprocess_prepostprocessor_get_output_info(preprocess,
                                                         addr outputInfo) == OK
    var outputTensorInfo: ptr ov_preprocess_output_tensor_info_t = nil
    check ov_preprocess_output_info_get_tensor_info(
      outputInfo, addr outputTensorInfo) == OK
    check ov_preprocess_output_set_element_type(outputTensorInfo, F32) == OK

    ov_preprocess_output_tensor_info_free(outputTensorInfo)
    ov_preprocess_output_info_free(outputInfo)
    ov_preprocess_input_model_info_free(modelInfo)
    ov_preprocess_preprocess_steps_free(steps)
    ov_preprocess_input_tensor_info_free(tensorInfo)
    ov_preprocess_input_info_free(info)
    var built: ptr ov_model_t = nil
    let status = ov_preprocess_prepostprocessor_build(preprocess, addr built)
    if status != OK:
      let detail = ov_get_last_err_msg()
      checkpoint(describe(status, "build") & ": " & $detail)
      ov_free(detail)
    check status == OK
    ov_preprocess_prepostprocessor_free(preprocess)
    if status == OK:
      var shape = inputPartialShape(built)
      checkpoint("built input " & shapeString(shape))
      check shapeString(shape) == "{1,6,6,3}"
      ov_partial_shape_free(addr shape)
      check inputElementType(built) == U8
      ov_model_free(built)
    ov_model_free(source)
    ov_core_free(fixture.core)
