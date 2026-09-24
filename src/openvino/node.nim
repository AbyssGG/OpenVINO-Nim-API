# SPDX-License-Identifier: Apache-2.0

## Model input and output ports, and the metadata they carry.
##
## Only the read-only port is exposed. The mutable port exists in the C API for
## reshaping, which `0.1.0` does not support, and the two have separate release
## functions: treating them as one type is how a binding gets a mismatched free.

import errors
import private/conversions
import private/handles
import raw/common
import raw/node as rawNode
import raw/shape as rawShape
import shape

type Port* = object
  ## A read-only input or output port of a model or compiled model.
  ##
  ## Owns one `ov_output_const_port_t`. Copying shares the native object and the
  ## closed state.
  handle: Handle[ov_output_const_port_t]

proc releasePort(native: ptr ov_output_const_port_t) {.nimcall.} =
  ## Release function handed to the handle model. Note that this is the const
  ## port's own release function, not `ov_output_port_free`.
  ov_output_const_port_free(native)

proc wrapPort*(native: ptr ov_output_const_port_t): Port =
  ## Takes ownership of `native`.
  ##
  ## Internal to the package: ports are obtained from a model or a compiled
  ## model, never constructed by a caller.
  Port(handle: newHandle(native, releasePort, "port"))

proc close*(port: Port) =
  ## Releases the port. Safe to call more than once.
  port.handle.close()

proc isClosed*(port: Port): bool =
  ## Reports whether the port has been closed. Never raises.
  port.handle.isClosed()

proc name*(port: Port): string =
  ## Returns one of the port's tensor names.
  ##
  ## OpenVINO may associate several names with a port and does not promise which
  ## one this is, which is why it is `name` rather than `names`.
  ##
  ## Copies the string and releases OpenVINO's allocation before returning.
  ##
  ## Raises `OpenVinoArgumentError` if the port is closed, `OpenVinoError` when
  ## the port has no name.
  var native: cstring = nil
  checkStatus(ov_port_get_any_name(port.handle.native(), addr native),
              "get port name")
  result = takeString(native)

proc elementType*(port: Port): ElementType =
  ## Returns the port's element type.
  ##
  ## Raises `OpenVinoArgumentError` if the port is closed or the runtime reports
  ## a type this build does not know.
  var raw: ov_element_type_e = DYNAMIC
  checkStatus(ov_port_get_element_type(port.handle.native(), addr raw),
              "get port element type")
  result = toElementType(raw)

proc shape*(port: Port): Shape =
  ## Returns the port's static shape.
  ##
  ## Copies the dimensions and releases OpenVINO's shape allocation before
  ## returning.
  ##
  ## Raises `OpenVinoError` for a port whose shape is dynamic, because a dynamic
  ## shape has no static form and `0.1.0` does not model one.
  var raw: ov_shape_t
  checkStatus(ov_const_port_get_shape(port.handle.native(), addr raw),
              "get port shape")
  result = initShape(takeShape(raw))

proc unsafeRawHandle*(port: Port): ptr ov_output_const_port_t =
  ## Returns the borrowed native handle for use with `openvino/raw`.
  ##
  ## Borrowed: do not release it, and do not retain it past the port's
  ## lifetime.
  port.handle.native()
