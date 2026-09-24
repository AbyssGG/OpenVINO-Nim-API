# SPDX-License-Identifier: Apache-2.0

## Copying data out of OpenVINO-owned memory, then releasing it.
##
## Every function here follows the same shape: copy into Nim-managed memory
## first, release the native container in a `finally`, and return the copy. The
## `finally` matters because a failure part-way through the copy must still
## release, which is the bug the Resonance prototype had in its error path.
##
## Nothing here is exported from `import openvino`. These are internal helpers,
## and they are kept separate from the managed types so that the
## copy-then-release rule lives in one readable place instead of being restated
## at every call site.

import ../errors
import ../raw/core
import ../raw/error
import ../raw/shape

proc takeString*(native: var cstring): string =
  ## Copies an OpenVINO-allocated string and releases the original.
  ##
  ## For `char**` out-parameters such as the one `ov_core_get_property` fills.
  ## Sets `native` to `nil` so that a second call cannot release it twice.
  ##
  ## Never apply this to the result of `ov_get_error_info`, which is a static
  ## pointer that must not be released.
  if native == nil:
    return ""
  try:
    result = $native
  finally:
    ov_free(native)
    native = nil

proc takeDeviceNames*(devices: var ov_available_devices_t): seq[string] =
  ## Copies every device name, then releases the list.
  ##
  ## Released unconditionally on a successful query, including when `size` is
  ## zero. The prototype released only when `size` was non-zero, which is not
  ## what the contract says.
  result = @[]
  try:
    for index in 0 ..< int(devices.size):
      if devices.devices[index] != nil:
        result.add($devices.devices[index])
      else:
        result.add("")
  finally:
    ov_available_devices_free(addr devices)

proc takeVersion*(version: var ov_version_t): tuple[build,
    description: string] =
  ## Copies the runtime version strings, then releases them.
  result = ("", "")
  try:
    if version.buildNumber != nil:
      result.build = $version.buildNumber
    if version.description != nil:
      result.description = $version.description
  finally:
    ov_version_free(addr version)

proc takeShape*(shape: var ov_shape_t): seq[int64] =
  ## Copies an OpenVINO-allocated shape, then releases its dimension storage.
  ##
  ## Rejects a negative rank rather than trusting it, because the rank is used
  ## as a loop bound and a negative value read from foreign memory would be a
  ## far worse failure than an exception.
  if shape.rank < 0:
    # Release before reporting, so a malformed shape does not also leak.
    discard ov_shape_free(addr shape)
    raiseArgumentError("OpenVINO reported a negative shape rank: " &
      $shape.rank)
  result = newSeq[int64](int(shape.rank))
  try:
    if shape.dims != nil:
      let dims = cast[ptr UncheckedArray[int64]](shape.dims)
      for index in 0 ..< int(shape.rank):
        result[index] = dims[index]
  finally:
    # `ov_shape_free` returns a status. Ignoring it here is deliberate: there
    # is no recovery from a failed release, and this helper is called on
    # cleanup paths where raising would mask the original failure.
    discard ov_shape_free(addr shape)

proc checkedElementCount*(dimensions: openArray[int64]): int64 =
  ## Multiplies `dimensions` into an element count, rejecting negatives and
  ## overflow.
  ##
  ## An empty shape denotes a scalar and yields 1, matching
  ## `ov_tensor_get_size`.
  ##
  ## Raises `OpenVinoArgumentError` on a negative dimension or on overflow.
  ## Overflow is checked before it happens rather than detected afterwards,
  ## because a wrapped count would be used to size a buffer.
  result = 1
  for index, dimension in dimensions:
    if dimension < 0:
      raiseArgumentError("dimension " & $index & " is negative: " &
        $dimension)
    if dimension == 0:
      return 0
    if result > high(int64) div dimension:
      raiseArgumentError("shape " & $(@dimensions) &
        " overflows a signed 64-bit element count")
    result = result * dimension

proc checkedByteSize*(elementCount, bytesPerElement: int64): int64 =
  ## Multiplies an element count by an element size, rejecting overflow.
  ##
  ## Raises `OpenVinoArgumentError` on a negative input or on overflow.
  if elementCount < 0:
    raiseArgumentError("element count is negative: " & $elementCount)
  if bytesPerElement < 0:
    raiseArgumentError("element size is negative: " & $bytesPerElement)
  if elementCount == 0 or bytesPerElement == 0:
    return 0
  if elementCount > high(int64) div bytesPerElement:
    raiseArgumentError("byte size of " & $elementCount & " elements of " &
      $bytesPerElement & " bytes overflows a signed 64-bit integer")
  result = elementCount * bytesPerElement

proc checkedIndex*(index: int; count: int; what: string): csize_t =
  ## Converts `index` to `csize_t` after checking it against `count`.
  ##
  ## Raises `OpenVinoArgumentError` when the index is negative or not below
  ## `count`. Checking before the conversion is the point: a negative `int`
  ## converted to `csize_t` becomes an enormous positive value, and OpenVINO
  ## would then index far outside its own arrays.
  if index < 0:
    raiseArgumentError(what & " index is negative: " & $index)
  if index >= count:
    raiseArgumentError(what & " index " & $index &
      " is out of range; there are " & $count)
  result = csize_t(index)
