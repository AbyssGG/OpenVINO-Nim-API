# SPDX-License-Identifier: Apache-2.0

## Tensors: OpenVINO-owned storage, safe copies in and out, and one clearly
## named unsafe escape hatch.
##
## The default is always the safe one. `newTensor` asks OpenVINO to allocate,
## and `tensorFrom` copies caller data into OpenVINO-owned storage. Neither can
## leave a tensor pointing at memory that Nim might move or free.
##
## Borrowing caller memory is possible, through `unsafeTensorFromPointer`. The
## name says what it is, and the doc comment lists what the caller must
## guarantee. There is no unnamed middle ground, because a borrowing entry point
## that looked safe would be the most dangerous thing in this package.

import errors
import private/conversions
import private/handles
import raw/common
import raw/shape as rawShape
import raw/tensor as rawTensor
import shape

export shape

type Tensor* = object
  ## A tensor and its storage.
  ##
  ## Owns one `ov_tensor_t`. Copying a `Tensor` shares the same native object
  ## and the same closed state, so closing through one copy closes all of them;
  ## see `docs/decisions/0002-handle-model.md`.
  handle: Handle[ov_tensor_t]
  ownsStorage: bool

proc releaseTensor(native: ptr ov_tensor_t) {.nimcall.} =
  ## Release function handed to the handle model.
  ov_tensor_free(native)

proc wrap(native: ptr ov_tensor_t; ownsStorage: bool): Tensor =
  ## Takes ownership of `native`. Only called after a successful create.
  Tensor(handle: newHandle(native, releaseTensor, "tensor"),
         ownsStorage: ownsStorage)

template withRawShape(shapeValue: Shape; rawName: untyped; body: untyped) =
  ## Builds an `ov_shape_t` for `shapeValue`, runs `body`, then releases it.
  ##
  ## The shape is created through `ov_shape_create` so that OpenVINO owns the
  ## dimension storage and the by-value struct the tensor functions take is
  ## exactly the one OpenVINO built. Released in a `finally` so a failure in
  ## `body` still releases.
  var dimensions = shapeValue.dims()
  var rawName: ov_shape_t
  let rank = int64(dimensions.len)
  let dimensionPointer =
    if dimensions.len == 0: nil else: addr dimensions[0]
  if rank == 0:
    raiseArgumentError("OpenVINO cannot build a shape of rank 0; a scalar " &
      "tensor is expressed as a shape of [1]")
  checkStatus(ov_shape_create(rank, dimensionPointer, addr rawName),
              "create shape", $shapeValue)
  try:
    body
  finally:
    discard ov_shape_free(addr rawName)

proc close*(tensor: Tensor) =
  ## Releases the tensor. Safe to call more than once.
  ##
  ## Preferred over waiting for the destructor, because it makes the release
  ## point visible. Any pointer previously obtained from `unsafeDataPointer` is
  ## invalid afterwards.
  tensor.handle.close()

proc isClosed*(tensor: Tensor): bool =
  ## Reports whether the tensor has been closed. Never raises.
  tensor.handle.isClosed()

proc newTensor*(elementType: ElementType; tensorShape: Shape): Tensor =
  ## Creates a tensor whose storage OpenVINO allocates and owns.
  ##
  ## The safe default. The contents are not initialised by this call.
  ##
  ## Raises `OpenVinoArgumentError` for a shape OpenVINO cannot express,
  ## `OpenVinoError` when the runtime refuses, and `OpenVinoLibraryError` when
  ## the runtime is missing. Performs no file I/O and does not block.
  var native: ptr ov_tensor_t = nil
  withRawShape(tensorShape, raw):
    checkStatus(ov_tensor_create(elementType.toRaw(), raw, addr native),
                "create tensor", $elementType & " " & $tensorShape)
  result = wrap(native, ownsStorage = true)

proc elementType*(tensor: Tensor): ElementType =
  ## Returns the tensor's element type.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed.
  var raw: ov_element_type_e = DYNAMIC
  checkStatus(ov_tensor_get_element_type(tensor.handle.native(), addr raw),
              "get tensor element type")
  result = toElementType(raw)

proc shape*(tensor: Tensor): Shape =
  ## Returns the tensor's current shape.
  ##
  ## Copies the dimensions and releases OpenVINO's shape allocation before
  ## returning, so the result has no tie to native memory.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed.
  var raw: ov_shape_t
  checkStatus(ov_tensor_get_shape(tensor.handle.native(), addr raw),
              "get tensor shape")
  result = initShape(takeShape(raw))

proc elementCount*(tensor: Tensor): int =
  ## Returns the number of elements, as reported by OpenVINO rather than
  ## recomputed from the shape.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed.
  var count: csize_t = 0
  checkStatus(ov_tensor_get_size(tensor.handle.native(), addr count),
              "get tensor element count")
  result = int(count)

proc byteSize*(tensor: Tensor): int =
  ## Returns the storage size in bytes, as reported by OpenVINO.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed.
  var size: csize_t = 0
  checkStatus(ov_tensor_get_byte_size(tensor.handle.native(), addr size),
              "get tensor byte size")
  result = int(size)

proc setShape*(tensor: Tensor; newShape: Shape) =
  ## Replaces the tensor's shape, reallocating when the new size is larger.
  ##
  ## Any pointer previously obtained from `unsafeDataPointer` is invalid
  ## afterwards, because the storage may have moved.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed, and `OpenVinoError`
  ## when the runtime refuses the shape. Does not apply to a tensor built over
  ## borrowed memory whose capacity is fixed; OpenVINO reports that itself.
  withRawShape(newShape, raw):
    checkStatus(ov_tensor_set_shape(tensor.handle.native(), raw),
                "set tensor shape", $newShape)

proc unsafeDataPointer*(tensor: Tensor): pointer =
  ## Returns a borrowed pointer to the tensor's storage.
  ##
  ## Unsafe, and named so. The pointer belongs to the tensor: it must not be
  ## released, and it becomes invalid as soon as the tensor is closed or its
  ## shape changes. Prefer `copyFrom` and `copyTo`, which have no such window.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed.
  var data: pointer = nil
  checkStatus(ov_tensor_data(tensor.handle.native(), addr data),
              "get tensor data pointer")
  result = data

proc requireTypedAccess(tensor: Tensor; elementSize: int;
                        typeName: string): int =
  ## Validates that typed access of `elementSize` bytes matches the tensor, and
  ## returns the element count.
  ##
  ## Checks the element type's width against the Nim type's width, and the total
  ## byte size against the product. Both are checked because either alone can be
  ## satisfied by a coincidence.
  let
    tensorType = tensor.elementType()
    count = tensor.elementCount()
    bytes = tensor.byteSize()
  if not hasFixedWidth(tensorType):
    raiseArgumentError("cannot access a " & $tensorType &
      " tensor as " & typeName & ": the element type has no fixed width")
  if isSubByte(tensorType):
    raiseArgumentError("cannot access a " & $tensorType &
      " tensor as " & typeName & ": elements are packed several per byte")
  let expectedElementSize = bitsPerElement(tensorType) div 8
  if expectedElementSize != elementSize:
    raiseArgumentError("cannot access a " & $tensorType & " tensor of " &
      $expectedElementSize & "-byte elements as " & typeName & " of " &
      $elementSize & " bytes")
  if bytes != count * elementSize:
    raiseArgumentError("tensor reports " & $bytes & " bytes for " & $count &
      " elements of " & $elementSize & " bytes; refusing typed access")
  result = count

proc copyFrom*[T](tensor: Tensor; source: openArray[T]) =
  ## Copies `source` into the tensor's storage.
  ##
  ## The safe way to set input data: the tensor keeps owning its storage, and
  ## nothing of the caller's is borrowed afterwards.
  ##
  ## Raises `OpenVinoArgumentError` when the tensor is closed, when `T` does not
  ## match the element type's width, or when the lengths differ. Requiring an
  ## exact length rather than accepting a shorter one is deliberate: a partial
  ## fill would leave the rest holding whatever was there before.
  let count = requireTypedAccess(tensor, sizeof(T), $T)
  if source.len != count:
    raiseArgumentError("tensor holds " & $count & " elements but " &
      $source.len & " were supplied; copyFrom requires an exact match")
  if count == 0:
    return
  let destination = tensor.unsafeDataPointer()
  copyMem(destination, unsafeAddr source[0], count * sizeof(T))

proc copyTo*[T](tensor: Tensor; destination: var openArray[T]) =
  ## Copies the tensor's contents into `destination`.
  ##
  ## Raises `OpenVinoArgumentError` when the tensor is closed, when `T` does not
  ## match the element type's width, or when the lengths differ.
  let count = requireTypedAccess(tensor, sizeof(T), $T)
  if destination.len != count:
    raiseArgumentError("tensor holds " & $count & " elements but " &
      $destination.len & " were supplied; copyTo requires an exact match")
  if count == 0:
    return
  copyMem(addr destination[0], tensor.unsafeDataPointer(), count * sizeof(T))

proc toSeq*[T](tensor: Tensor; _: typedesc[T]): seq[T] =
  ## Returns the tensor's contents as a freshly allocated `seq`.
  ##
  ## The safe way to read output data. Allocates and copies; for a large tensor
  ## on a hot path, `unsafeDataPointer` avoids the copy at the cost of a
  ## lifetime obligation.
  ##
  ## Raises `OpenVinoArgumentError` when the tensor is closed or `T` does not
  ## match the element type.
  let count = requireTypedAccess(tensor, sizeof(T), $T)
  result = newSeq[T](count)
  if count > 0:
    copyMem(addr result[0], tensor.unsafeDataPointer(), count * sizeof(T))

proc tensorFrom*[T](elementType: ElementType; tensorShape: Shape;
                    source: openArray[T]): Tensor =
  ## Creates an OpenVINO-owned tensor holding a copy of `source`.
  ##
  ## The safe way to build an input tensor from Nim data. Nothing of the
  ## caller's is borrowed once this returns, so `source` may be modified or
  ## collected freely.
  ##
  ## Raises `OpenVinoArgumentError` when `T` does not match `elementType`, or
  ## when `source.len` does not equal the shape's element count.
  result = newTensor(elementType, tensorShape)
  try:
    result.copyFrom(source)
  except CatchableError:
    # The tensor was created but never handed to the caller, so it would
    # otherwise be released only by the collector. Releasing here keeps a
    # failed construction from holding native memory.
    result.close()
    raise

proc unsafeTensorFromPointer*(elementType: ElementType; tensorShape: Shape;
                              data: pointer): Tensor =
  ## Creates a tensor over memory the caller owns. **Unsafe.**
  ##
  ## The tensor borrows `data` and never owns it. The caller must guarantee, for
  ## the entire lifetime of the tensor:
  ##
  ## - `data` stays allocated and is not moved. A Nim `seq` or `string` fails
  ##   this as soon as it grows, and a stack buffer fails it on return.
  ## - it is large enough for `tensorShape` at `elementType`.
  ## - it is suitably aligned for the element type.
  ## - nothing else writes to it while an inference reads from it.
  ##
  ## Violating any of these is undefined behaviour, not an exception. Use
  ## `tensorFrom` unless a measurement shows the copy matters.
  ##
  ## Raises `OpenVinoArgumentError` for a nil pointer or an unusable shape.
  if data == nil:
    raiseArgumentError("unsafeTensorFromPointer requires a non-nil pointer")
  var native: ptr ov_tensor_t = nil
  withRawShape(tensorShape, raw):
    checkStatus(ov_tensor_create_from_host_ptr(elementType.toRaw(), raw, data,
                                              addr native),
                "create tensor over borrowed memory",
                $elementType & " " & $tensorShape)
  result = wrap(native, ownsStorage = false)

proc ownsStorage*(tensor: Tensor): bool =
  ## Reports whether OpenVINO allocated this tensor's storage.
  ##
  ## False only for a tensor made by `unsafeTensorFromPointer`, whose storage
  ## belongs to the caller. Useful in assertions and diagnostics.
  tensor.ownsStorage

proc wrapOwnedTensor*(native: ptr ov_tensor_t): Tensor =
  ## Takes ownership of a tensor handle that OpenVINO returned.
  ##
  ## Internal to the package. Used for the handles that
  ## `ov_infer_request_get_*_tensor_by_index` produces, which the caller owns
  ## and must release even though the storage behind them belongs to the
  ## request.
  wrap(native, ownsStorage = true)

proc unsafeRawHandle*(tensor: Tensor): ptr ov_tensor_t =
  ## Returns the borrowed native handle, for interoperating with code that uses
  ## `openvino/raw` directly.
  ##
  ## Borrowed: the caller must not release it and must not retain it past the
  ## tensor's lifetime.
  ##
  ## Raises `OpenVinoArgumentError` if the tensor is closed.
  tensor.handle.native()
