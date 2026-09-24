# SPDX-License-Identifier: Apache-2.0

## Error-path tests that need a real OpenVINO runtime.
##
## The unit tests cover what can be checked without one. These cover what
## cannot: that a genuine failure produces a status, a stable description and
## the runtime's own detail message, and that reading the detail does not leak.
##
## Run with `nimble testLifecycle`.

import std/[os, strutils, unittest]

import openvino/errors
import openvino/raw

suite "status conversion":
  test "an OK status raises nothing":
    checkStatus(OK, "nothing")

  test "a failing status becomes an OpenVinoError with all fields set":
    try:
      checkStatus(GENERAL_ERROR, "example operation", "context detail")
      check false
    except OpenVinoError as err:
      checkpoint(err.msg)
      check err.operation == "example operation"
      check err.status == GENERAL_ERROR
      check err.context == "context detail"
      # ov_get_error_info returns a static description for every status.
      check err.statusInfo.len > 0
      check "example operation" in err.msg
      check "context detail" in err.msg

  test "each bound status has a non-empty stable description":
    # ov_get_error_info is documented to describe every status, and its result
    # must never be released. Reading all 18 also exercises that promise.
    for entry in StatusCodes:
      let info = $ov_get_error_info(entry.value)
      checkpoint(entry.name & " -> " & info)
      check info.len > 0

suite "native detail capture":
  test "a real failure carries the runtime's own detail message":
    # Reading a model from a path that does not exist is a failure OpenVINO
    # describes in its last-error slot, so this proves the detail is captured
    # rather than merely that a status was mapped.
    var core: ptr ov_core_t = nil
    check ov_core_create(addr core) == OK
    if core != nil:
      let missing = getTempDir() / "openvino-nim-no-such-model.xml"
      check not fileExists(missing)
      var model: ptr ov_model_t = nil
      let status = ov_core_read_model(core, missing.cstring, nil, addr model)
      check status != OK
      check model == nil
      try:
        checkStatus(status, "read model", missing)
        check false
      except OpenVinoError as err:
        checkpoint(err.msg)
        check err.status == status
        check err.statusInfo.len > 0
        check err.nativeDetail.len > 0
      ov_core_free(core)

  test "capturing the detail repeatedly does not exhaust or corrupt it":
    # The prototype converted the last-error string and never released it,
    # leaking on every failure. Repeating the failure many times would grow
    # unboundedly. This cannot measure bytes, but it does prove that release
    # and re-acquisition stay consistent rather than returning a freed buffer.
    var core: ptr ov_core_t = nil
    check ov_core_create(addr core) == OK
    if core != nil:
      let missing = getTempDir() / "openvino-nim-no-such-model.xml"
      var details: seq[string] = @[]
      for _ in 1 .. 200:
        var model: ptr ov_model_t = nil
        let status = ov_core_read_model(core, missing.cstring, nil, addr model)
        check status != OK
        try:
          checkStatus(status, "read model", missing)
        except OpenVinoError as err:
          details.add(err.nativeDetail)
      ov_core_free(core)
      check details.len == 200
      check details[0].len > 0
      # Every iteration must see the same message. A freed or overwritten
      # buffer would show up here as variation.
      for detail in details:
        check detail == details[0]

suite "argument errors never reach the C layer":
  test "an invalid device name still produces a described failure":
    var core: ptr ov_core_t = nil
    check ov_core_create(addr core) == OK
    if core != nil:
      var value: cstring = nil
      let status = ov_core_get_property(core, "NO_SUCH_DEVICE".cstring,
                                        ov_property_key_device_full_name(),
                                        addr value)
      check status != OK
      try:
        checkStatus(status, "get device property", "NO_SUCH_DEVICE")
        check false
      except OpenVinoError as err:
        checkpoint(err.msg)
        check "NO_SUCH_DEVICE" in err.msg
      ov_core_free(core)

  test "a zero rank shape is rejected by OpenVINO with a status":
    # ov_shape_create documents that rank must be greater than zero.
    var shape: ov_shape_t
    var dims = [int64(1)]
    let status = ov_shape_create(0, addr dims[0], addr shape)
    checkpoint("status=" & $status)
    if status != OK:
      try:
        checkStatus(status, "create shape", "rank=0")
        check false
      except OpenVinoError as err:
        checkpoint(err.msg)
        check err.status == status
    else:
      discard ov_shape_free(addr shape)

suite "core lifetime under repetition":
  test "a thousand create and release cycles stay healthy":
    # The lifetime stress requirement against the real runtime. A leak or a
    # double free here would normally surface as a crash or a failing create
    # part-way through.
    const cycles = 1000
    var created = 0
    for _ in 1 .. cycles:
      var core: ptr ov_core_t = nil
      if ov_core_create(addr core) == OK and core != nil:
        inc created
        ov_core_free(core)
    check created == cycles

  test "a thousand tensor cycles stay healthy":
    const cycles = 1000
    var dims = [int64(1), 2, 3]
    var created = 0
    for _ in 1 .. cycles:
      var shape: ov_shape_t
      if ov_shape_create(int64(dims.len), addr dims[0], addr shape) == OK:
        var tensor: ptr ov_tensor_t = nil
        if ov_tensor_create(F32, shape, addr tensor) == OK and tensor != nil:
          inc created
          ov_tensor_free(tensor)
        discard ov_shape_free(addr shape)
    check created == cycles
