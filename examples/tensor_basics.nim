# SPDX-License-Identifier: Apache-2.0

## Tensors: shapes, element types, and the difference between the safe data
## paths and the unsafe one.
##
## Needs an OpenVINO runtime but no model and no device, because tensors are
## allocated by the runtime rather than by a plugin.
##
## Build and run:
##
## ```shell
## nim c -r --path:src examples/tensor_basics.nim
## ```

import openvino

proc showShapes() =
  echo "Shapes"
  let image = initShape(1, 3, 224, 224)
  echo "  ", image, " rank=", image.rank, " elements=", image.elementCount
  echo "    as f32: ", image.byteSize(etF32), " bytes"
  echo "    as u8 : ", image.byteSize(etU8), " bytes"

  # An empty shape is a scalar and holds one element, matching what OpenVINO
  # reports for a scalar tensor. Written without arguments: `initShape([])`
  # cannot say which overload it means, because an empty array literal has no
  # element type.
  let scalar = initShape()
  echo "  ", scalar, " rank=", scalar.rank, " elements=", scalar.elementCount

  # Shapes are validated when built, so an invalid one cannot be passed around
  # and fail somewhere less obvious.
  try:
    discard initShape(1, -4)
  except OpenVinoArgumentError as err:
    echo "  rejected [1, -4]: ", err.msg

  # Sub-byte types refuse a byte size rather than rounding one. A rounded answer
  # would be used to size a buffer.
  try:
    discard initShape(1, 8).byteSize(etU4)
  except OpenVinoArgumentError as err:
    echo "  rejected byte size of u4: ", err.msg

proc showOwnedTensor() =
  echo ""
  echo "A tensor whose storage OpenVINO owns"
  let value = newTensor(etF32, initShape(2, 3))
  defer: value.close()
  echo "  type=", value.elementType(), " shape=", value.shape(),
    " elements=", value.elementCount, " bytes=", value.byteSize,
    " ownsStorage=", value.ownsStorage()

  # copyFrom requires an exact element count. A shorter source would leave the
  # rest of the tensor holding whatever was there before.
  value.copyFrom([float32(1), 2, 3, 4, 5, 6])
  echo "  after copyFrom: ", value.toSeq(float32)

  try:
    value.copyFrom([float32(1), 2])
  except OpenVinoArgumentError as err:
    echo "  rejected a short copy: ", err.msg

  # The width check stops a caller reading twice as many bytes as the tensor
  # holds.
  try:
    discard value.toSeq(float64)
  except OpenVinoArgumentError as err:
    echo "  rejected float64 access: ", err.msg

proc showReshape() =
  echo ""
  echo "Changing a shape"
  let value = newTensor(etF32, initShape(1, 2))
  defer: value.close()
  echo "  before: ", value.shape(), " elements=", value.elementCount
  value.setShape(initShape(2, 6))
  echo "  after : ", value.shape(), " elements=", value.elementCount
  echo "  note: any pointer from unsafeDataPointer is invalid after this,"
  echo "        because the storage may have moved."

proc showCopyFromNimData() =
  echo ""
  echo "Building a tensor from Nim data, safely"
  let source = @[float32(0.5), 1.5, 2.5, 3.5]
  let value = tensorFrom(etF32, initShape(1, 4), source)
  defer: value.close()
  echo "  source : ", source
  echo "  tensor : ", value.toSeq(float32)
  echo "  the tensor copied the data, so source may now change freely"

proc showUnsafePath() =
  echo ""
  echo "The unsafe path, and why it is named that way"
  # A heap-allocated buffer the example owns for as long as the tensor lives.
  # A `seq` would be wrong here: growing one moves its storage, and the tensor
  # would keep pointing at the old address.
  let elements = 4
  let buffer = cast[ptr UncheckedArray[float32]](
    allocShared0(elements * sizeof(float32)))
  defer: deallocShared(buffer)

  for index in 0 ..< elements:
    buffer[index] = float32(index) * 10.0

  let value = unsafeTensorFromPointer(etF32, initShape(1, 4), buffer)
  defer: value.close()
  echo "  contents    : ", value.toSeq(float32)
  echo "  ownsStorage : ", value.ownsStorage()

  # Writing through the caller's own pointer is visible to the tensor, because
  # there is only one buffer. That is the point of this path, and also its
  # danger.
  buffer[0] = 99.0
  echo "  after writing through the caller's pointer: ", value.toSeq(float32)
  echo "  the caller must keep this buffer alive, unmoved and large enough"
  echo "  for as long as the tensor exists. Prefer tensorFrom unless a"
  echo "  measurement shows the copy matters."

proc main() =
  showShapes()
  showOwnedTensor()
  showReshape()
  showCopyFromNimData()
  showUnsafePath()

when isMainModule:
  try:
    main()
  except OpenVinoLibraryError as err:
    echo "OpenVINO runtime not available."
    echo err.msg
    quit(1)
  except OpenVinoError as err:
    echo "OpenVINO failed during ", err.operation, "."
    echo err.msg
    quit(1)
