# SPDX-License-Identifier: Apache-2.0

## Layouts and declarative preprocessing.
##
## OpenVINO's pre/post-processing API hands out six kinds of child object, each
## pointing into its parent. Exposing them would mean six more handles that
## must never outlive the object they borrow from. Instead, a caller describes
## the work as a plain value, `PreprocessPlan`, and `applyPreprocessing` turns
## it into a new `Model` in one call that creates, uses and releases every
## child object itself. Nothing borrowed escapes. See
## `docs/decisions/0005-preprocessing-api.md`.
##
## A plan needs no runtime to build or to validate; only `initLayout` and
## `applyPreprocessing` call OpenVINO.

import std/[math, options, strutils]

import errors
import model
import private/conversions
import raw/common
import raw/layout as rawLayout
import raw/model as rawModel
import raw/prepostprocess as rawPreprocess
import shape
import tensor

type
  Layout* = object
    ## A validated layout such as `NCHW`, `NC?` or `[N,C,H,W]`.
    ##
    ## Holds OpenVINO's canonical text, so two spellings of the same layout
    ## compare equal.
    text: string

  ColorFormat* = enum
    ## Color format of an image input, mirroring `ov_color_format_e`.
    cfUndefined
    cfNv12SinglePlane
    cfNv12TwoPlanes
    cfI420SinglePlane
    cfI420ThreePlanes
    cfRgb
    cfBgr
    cfGray
    cfRgbx
    cfBgrx

  ResizeAlgorithm* = enum
    ## Interpolation used by the resize step.
    raLinear
    raCubic
    raNearest

  PaddingMode* = enum
    ## How the pad step fills new elements.
    pmConstant  ## With the given value.
    pmEdge      ## With the nearest edge value.
    pmReflect   ## By reflection, edge not repeated.
    pmSymmetric ## By reflection, edge repeated.

  PreprocessStepKind* = enum
    ## The kind of one preprocessing step.
    pskConvertElementType
    pskConvertColor
    pskConvertLayout
    pskResize
    pskMean
    pskMeanChannels
    pskScale
    pskScaleChannels
    pskCrop
    pskPad
    pskReverseChannels

  PreprocessStep* = object
    ## One step, already validated. Read its kind with `kind` and a readable
    ## form with `$`.
    case stepKind: PreprocessStepKind
    of pskConvertElementType:
      elementType: ElementType
    of pskConvertColor:
      colorFormat: ColorFormat
    of pskConvertLayout:
      layout: Layout
    of pskResize:
      algorithm: ResizeAlgorithm
    of pskMean, pskScale:
      value: float32
    of pskMeanChannels, pskScaleChannels:
      values: seq[float32]
    of pskCrop:
      cropBegin, cropEnd: seq[int32]
    of pskPad:
      padBegin, padEnd: seq[int32]
      padValue: float32
      padMode: PaddingMode
    of pskReverseChannels:
      discard

  InputPreprocess* = object
    ## Everything a plan says about one model input: what the caller's tensor
    ## looks like, the steps to apply in order, and the model's own layout.
    byName: bool
    index: int
    name: string
    elementType: Option[ElementType]
    layout: Option[Layout]
    colorFormat: Option[ColorFormat]
    subNames: seq[string]
    spatial: Option[(int, int)]
    sample: Option[(ElementType, Shape)]
    steps: seq[PreprocessStep]
    modelLayout: Option[Layout]

  OutputPostprocess* = object
    ## What a plan says about one model output. The C API offers only the
    ## element type the caller wants to read.
    byName: bool
    index: int
    name: string
    elementType: Option[ElementType]

  PreprocessPlan* = object
    ## A reusable, runtime-free description of preprocessing for a model.
    inputs: seq[InputPreprocess]
    outputs: seq[OutputPostprocess]

const
  rawColorFormats: array[ColorFormat, ov_color_format_e] = [
    UNDEFINE, NV12_SINGLE_PLANE, NV12_TWO_PLANES, I420_SINGLE_PLANE,
    I420_THREE_PLANES, RGB, BGR, GRAY, RGBX, BGRX]
    ## Managed to raw mapping; the ABI test verifies the raw values.
  rawResizeAlgorithms: array[ResizeAlgorithm,
                             ov_preprocess_resize_algorithm_e] = [
    RESIZE_LINEAR, RESIZE_CUBIC, RESIZE_NEAREST]
  rawPaddingModes: array[PaddingMode, ov_padding_mode_e] = [
    CONSTANT, EDGE, REFLECT, SYMMETRIC]

# Layouts ------------------------------------------------------------------

proc checkText(text, what: string) =
  if '\0' in text:
    raiseArgumentError(what & " " & text.escape & " contains a NUL character")

proc createRawLayout(text: string): ptr ov_layout_t =
  ## Parses `text` into an owned `ov_layout_t`, raising `OpenVinoError` with
  ## OpenVINO's reason when it is not a layout.
  checkText(text, "layout")
  checkStatus(ov_layout_create(text.cstring, addr result), "parse layout",
              text.escape)

proc initLayout*(description: string): Layout =
  ## Parses and validates a layout, for example `"NCHW"`, `"NC?"`, `"...C"`
  ## or `"[N,C,H,W]"`. Needs the OpenVINO runtime.
  ##
  ## Follows OpenVINO's grammar exactly: lower case is accepted and
  ## upper-cased, and the empty string means "any layout", `[...]`.
  ##
  ## Raises `OpenVinoError` for a description OpenVINO rejects, such as one
  ## naming a dimension twice.
  let native = createRawLayout(description)
  try:
    var text = cstring(ov_layout_to_string(native))
    result = Layout(text: takeString(text))
  finally:
    ov_layout_free(native)

proc `$`*(layout: Layout): string =
  ## OpenVINO's canonical form, for example `[N,C,H,W]`.
  layout.text

proc `==`*(a, b: Layout): bool =
  ## Equal when the canonical forms are equal.
  a.text == b.text

# Steps ----------------------------------------------------------------------

proc kind*(step: PreprocessStep): PreprocessStepKind =
  ## The kind of the step.
  step.stepKind

proc formatFloats(values: openArray[float32]): string =
  var parts: seq[string] = @[]
  for value in values:
    parts.add($value)
  "[" & parts.join(", ") & "]"

proc formatInts(values: openArray[int32]): string =
  var parts: seq[string] = @[]
  for value in values:
    parts.add($value)
  "[" & parts.join(", ") & "]"

proc `$`*(step: PreprocessStep): string =
  ## A readable form such as `resize(raNearest)` or `mean([1.0, 2.0, 3.0])`.
  case step.stepKind
  of pskConvertElementType: "convertElementType(" & $step.elementType & ")"
  of pskConvertColor: "convertColor(" & $step.colorFormat & ")"
  of pskConvertLayout: "convertLayout(" & $step.layout & ")"
  of pskResize: "resize(" & $step.algorithm & ")"
  of pskMean: "mean(" & $step.value & ")"
  of pskMeanChannels: "mean(" & formatFloats(step.values) & ")"
  of pskScale: "scale(" & $step.value & ")"
  of pskScaleChannels: "scale(" & formatFloats(step.values) & ")"
  of pskCrop: "crop(" & formatInts(step.cropBegin) & ", " &
      formatInts(step.cropEnd) & ")"
  of pskPad: "pad(" & formatInts(step.padBegin) & ", " &
      formatInts(step.padEnd) & ", " & $step.padValue & ", " &
      $step.padMode & ")"
  of pskReverseChannels: "reverseChannels()"

# Plan construction -------------------------------------------------------------

proc checkTargetName(name, what: string) =
  if name.len == 0:
    raiseArgumentError("an " & what & " name cannot be empty")
  checkText(name, what & " name")

proc initPreprocessPlan*(): PreprocessPlan =
  ## An empty plan. Applying it builds the model unchanged.
  PreprocessPlan()

proc input*(plan: var PreprocessPlan; index: int): var InputPreprocess =
  ## The description of the input at `index`, created on first use. Calling
  ## it again for the same index continues the same description.
  ##
  ## Raises `OpenVinoArgumentError` for a negative index. Whether the index
  ## exists is checked when the plan is applied.
  if index < 0:
    raiseArgumentError("input index is negative: " & $index)
  for position in 0 ..< plan.inputs.len:
    if not plan.inputs[position].byName and
        plan.inputs[position].index == index:
      return plan.inputs[position]
  plan.inputs.add(InputPreprocess(index: index))
  return plan.inputs[^1]

proc input*(plan: var PreprocessPlan; name: string): var InputPreprocess =
  ## The description of the input named `name`, created on first use.
  ##
  ## Raises `OpenVinoArgumentError` for an empty name or one containing NUL.
  checkTargetName(name, "input")
  for position in 0 ..< plan.inputs.len:
    if plan.inputs[position].byName and plan.inputs[position].name == name:
      return plan.inputs[position]
  plan.inputs.add(InputPreprocess(byName: true, name: name))
  return plan.inputs[^1]

proc output*(plan: var PreprocessPlan; index: int): var OutputPostprocess =
  ## The description of the output at `index`, created on first use.
  ##
  ## Raises `OpenVinoArgumentError` for a negative index.
  if index < 0:
    raiseArgumentError("output index is negative: " & $index)
  for position in 0 ..< plan.outputs.len:
    if not plan.outputs[position].byName and
        plan.outputs[position].index == index:
      return plan.outputs[position]
  plan.outputs.add(OutputPostprocess(index: index))
  return plan.outputs[^1]

proc output*(plan: var PreprocessPlan; name: string): var OutputPostprocess =
  ## The description of the output named `name`, created on first use.
  checkTargetName(name, "output")
  for position in 0 ..< plan.outputs.len:
    if plan.outputs[position].byName and plan.outputs[position].name == name:
      return plan.outputs[position]
  plan.outputs.add(OutputPostprocess(byName: true, name: name))
  return plan.outputs[^1]

proc inputs*(plan: PreprocessPlan): seq[InputPreprocess] =
  ## A copy of the input descriptions, in the order they were first used.
  plan.inputs

proc outputs*(plan: PreprocessPlan): seq[OutputPostprocess] =
  ## A copy of the output descriptions.
  plan.outputs

proc steps*(input: InputPreprocess): seq[PreprocessStep] =
  ## A copy of the steps, in the order they will run.
  input.steps

proc target(input: InputPreprocess): string =
  if input.byName: "input[" & input.name.escape & "]"
  else: "input[" & $input.index & "]"

proc target(output: OutputPostprocess): string =
  if output.byName: "output[" & output.name.escape & "]"
  else: "output[" & $output.index & "]"

proc `$`*(input: InputPreprocess): string =
  ## A one-line summary, used in error messages from `applyPreprocessing`.
  var tensorParts: seq[string] = @[]
  if input.sample.isSome:
    tensorParts.add("from " & $input.sample.get[0] & " " &
      $input.sample.get[1])
  if input.elementType.isSome:
    tensorParts.add($input.elementType.get)
  if input.layout.isSome:
    tensorParts.add($input.layout.get)
  if input.colorFormat.isSome:
    tensorParts.add($input.colorFormat.get)
  if input.spatial.isSome:
    tensorParts.add($input.spatial.get[0] & "x" & $input.spatial.get[1])
  var stepParts: seq[string] = @[]
  for step in input.steps:
    stepParts.add($step)
  result = input.target & ": tensor{" & tensorParts.join(", ") &
    "} steps[" & stepParts.join(", ") & "]"
  if input.modelLayout.isSome:
    result.add(" model{" & $input.modelLayout.get & "}")

proc `$`*(output: OutputPostprocess): string =
  ## A one-line summary.
  result = output.target & ": tensor{"
  if output.elementType.isSome:
    result.add($output.elementType.get)
  result.add("}")

proc `$`*(plan: PreprocessPlan): string =
  ## A summary of every input and output description, separated by `; `.
  var parts: seq[string] = @[]
  for input in plan.inputs:
    parts.add($input)
  for output in plan.outputs:
    parts.add($output)
  parts.join("; ")

# Tensor description ----------------------------------------------------------------

proc tensorElementType*(p: var InputPreprocess;
                        elementType: ElementType): var InputPreprocess
    {.discardable.} =
  ## Declares the element type of the tensors the caller will bind.
  p.elementType = some(elementType)
  p

proc tensorLayout*(p: var InputPreprocess; layout: Layout): var InputPreprocess
    {.discardable.} =
  ## Declares the layout of the tensors the caller will bind.
  p.layout = some(layout)
  p

proc tensorColorFormat*(p: var InputPreprocess; format: ColorFormat;
                        subNames: openArray[string] = []): var InputPreprocess
    {.discardable.} =
  ## Declares the color format of the caller's tensors. Multi-plane formats
  ## take one sub-name per plane; each plane then becomes its own model input
  ## named after the original with the sub-name appended.
  ##
  ## Raises `OpenVinoArgumentError` for an empty sub-name or one with NUL.
  for subName in subNames:
    if subName.len == 0:
      raiseArgumentError("a color plane sub-name cannot be empty")
    checkText(subName, "color plane sub-name")
  p.colorFormat = some(format)
  p.subNames = @subNames
  p

proc tensorSpatialStaticShape*(p: var InputPreprocess;
                               height, width: int): var InputPreprocess
    {.discardable.} =
  ## Declares a fixed height and width for the caller's tensors, typically
  ## followed by `resize` to the model's own size.
  ##
  ## Raises `OpenVinoArgumentError` unless both are positive.
  if height <= 0 or width <= 0:
    raiseArgumentError("a spatial shape must be positive, not " & $height &
      "x" & $width)
  p.spatial = some((height, width))
  p

proc tensorFrom*(p: var InputPreprocess; sample: Tensor): var InputPreprocess
    {.discardable.} =
  ## Declares that the caller's tensors look like `sample`: its element type
  ## and its shape. Only those two facts are kept, so the plan stays a plain
  ## value and `sample` may be closed afterwards.
  ##
  ## Raises `OpenVinoArgumentError` if `sample` is closed.
  p.sample = some((sample.elementType, sample.shape))
  p

proc modelLayout*(p: var InputPreprocess; layout: Layout): var InputPreprocess
    {.discardable.} =
  ## Declares the layout the model itself expects for this input, which the
  ## layout conversion and resize steps need to know.
  p.modelLayout = some(layout)
  p

# Steps ---------------------------------------------------------------------------

proc addStep(p: var InputPreprocess; step: PreprocessStep): var InputPreprocess =
  p.steps.add(step)
  p

proc convertElementType*(p: var InputPreprocess;
                         elementType: ElementType): var InputPreprocess
    {.discardable.} =
  ## Adds a step converting elements to `elementType`.
  p.addStep(PreprocessStep(stepKind: pskConvertElementType,
                           elementType: elementType))

proc convertColor*(p: var InputPreprocess;
                   format: ColorFormat): var InputPreprocess {.discardable.} =
  ## Adds a step converting from the declared color format to `format`.
  p.addStep(PreprocessStep(stepKind: pskConvertColor, colorFormat: format))

proc convertLayout*(p: var InputPreprocess;
                    layout: Layout): var InputPreprocess {.discardable.} =
  ## Adds a step transposing from the declared tensor layout to `layout`.
  p.addStep(PreprocessStep(stepKind: pskConvertLayout, layout: layout))

proc resize*(p: var InputPreprocess;
             algorithm: ResizeAlgorithm): var InputPreprocess {.discardable.} =
  ## Adds a step resizing the spatial dimensions to the model's.
  p.addStep(PreprocessStep(stepKind: pskResize, algorithm: algorithm))

proc checkFinite(value: float32; what: string) =
  if value.isNaN or value.classify in {fcInf, fcNegInf}:
    raiseArgumentError(what & " must be finite, not " & $value)

proc checkChannels(values: openArray[float32]; what: string) =
  if values.len == 0:
    raiseArgumentError(what & " needs at least one channel value")
  if values.len > int(high(int32)):
    raiseArgumentError(what & " has more channel values than fit in int32")
  for value in values:
    checkFinite(value, what & " value")

proc mean*(p: var InputPreprocess; value: float32): var InputPreprocess
    {.discardable.} =
  ## Adds a step subtracting `value` from every element.
  ##
  ## Raises `OpenVinoArgumentError` for a value that is not finite.
  checkFinite(value, "mean")
  p.addStep(PreprocessStep(stepKind: pskMean, value: value))

proc mean*(p: var InputPreprocess;
           perChannel: openArray[float32]): var InputPreprocess
    {.discardable.} =
  ## Adds a step subtracting one value per channel. The count must match the
  ## channel dimension, which OpenVINO checks when the plan is applied.
  ##
  ## Raises `OpenVinoArgumentError` for an empty list or a non-finite value.
  checkChannels(perChannel, "mean")
  p.addStep(PreprocessStep(stepKind: pskMeanChannels, values: @perChannel))

proc scale*(p: var InputPreprocess; value: float32): var InputPreprocess
    {.discardable.} =
  ## Adds a step dividing every element by `value`.
  ##
  ## Raises `OpenVinoArgumentError` for zero or a value that is not finite.
  checkFinite(value, "scale")
  if value == 0:
    raiseArgumentError("scale cannot be zero")
  p.addStep(PreprocessStep(stepKind: pskScale, value: value))

proc scale*(p: var InputPreprocess;
            perChannel: openArray[float32]): var InputPreprocess
    {.discardable.} =
  ## Adds a step dividing by one value per channel.
  ##
  ## Raises `OpenVinoArgumentError` for an empty list, a zero or a
  ## non-finite value.
  checkChannels(perChannel, "scale")
  for value in perChannel:
    if value == 0:
      raiseArgumentError("scale values cannot be zero")
  p.addStep(PreprocessStep(stepKind: pskScaleChannels, values: @perChannel))

proc crop*(p: var InputPreprocess;
           begin, `end`: openArray[int32]): var InputPreprocess
    {.discardable.} =
  ## Adds a step keeping `[begin, end)` along every dimension of the tensor
  ## as declared. Negative values count from the end, as in OpenVINO.
  ##
  ## Raises `OpenVinoArgumentError` for empty or unequal lists.
  if begin.len == 0 or begin.len != `end`.len:
    raiseArgumentError("crop needs begin and end lists of the same, " &
      "non-zero length; got " & $begin.len & " and " & $`end`.len)
  p.addStep(PreprocessStep(stepKind: pskCrop, cropBegin: @begin,
                           cropEnd: @`end`))

proc toInt32List(values: openArray[int]; what: string): seq[int32] =
  result = newSeq[int32](values.len)
  for index, value in values:
    if value < int(low(int32)) or value > int(high(int32)):
      raiseArgumentError(what & " value " & $value & " does not fit in int32")
    result[index] = int32(value)

proc pad*(p: var InputPreprocess; padsBegin, padsEnd: openArray[int];
          value = 0'f32; mode = pmConstant): var InputPreprocess
    {.discardable.} =
  ## Adds a step padding every dimension by `padsBegin` before and `padsEnd`
  ## after, filling with `value` or according to `mode`.
  ##
  ## Raises `OpenVinoArgumentError` for empty or unequal lists, a count that
  ## does not fit in int32, or a non-finite value.
  if padsBegin.len == 0 or padsBegin.len != padsEnd.len:
    raiseArgumentError("pad needs begin and end lists of the same, " &
      "non-zero length; got " & $padsBegin.len & " and " & $padsEnd.len)
  checkFinite(value, "pad value")
  p.addStep(PreprocessStep(stepKind: pskPad,
                           padBegin: toInt32List(padsBegin, "pad"),
                           padEnd: toInt32List(padsEnd, "pad"),
                           padValue: value, padMode: mode))

proc reverseChannels*(p: var InputPreprocess): var InputPreprocess
    {.discardable.} =
  ## Adds a step reversing the order of the channel dimension.
  p.addStep(PreprocessStep(stepKind: pskReverseChannels))

proc tensorElementType*(p: var OutputPostprocess;
                        elementType: ElementType): var OutputPostprocess
    {.discardable.} =
  ## Declares the element type the caller wants to read from this output.
  p.elementType = some(elementType)
  p

# Applying a plan -----------------------------------------------------------------

proc applyLayout(text: string; operation, context: string;
                 apply: proc (layout: ptr ov_layout_t): ov_status_e) =
  ## Creates a temporary `ov_layout_t`, hands it to `apply`, and frees it.
  ## OpenVINO copies the layout, so it does not need to live longer.
  let native = createRawLayout(text)
  try:
    checkStatus(apply(native), operation, context)
  finally:
    ov_layout_free(native)

proc applyTensorInfo(info: ptr ov_preprocess_input_info_t;
                     input: InputPreprocess) =
  let where = input.target & ".tensor"
  var tensorInfo: ptr ov_preprocess_input_tensor_info_t = nil
  checkStatus(ov_preprocess_input_info_get_tensor_info(info, addr tensorInfo),
              "apply preprocessing", where)
  try:
    if input.sample.isSome:
      let (elementType, sampleShape) = input.sample.get
      let sample = newTensor(elementType, sampleShape)
      try:
        checkStatus(ov_preprocess_input_tensor_info_set_from(
                      tensorInfo, sample.unsafeRawHandle()),
                    "apply preprocessing", where & ".from")
      finally:
        sample.close()
    if input.elementType.isSome:
      checkStatus(ov_preprocess_input_tensor_info_set_element_type(
                    tensorInfo, input.elementType.get.toRaw),
                  "apply preprocessing", where & ".elementType")
    if input.layout.isSome:
      applyLayout($input.layout.get, "apply preprocessing",
                  where & ".layout") do (layout: ptr ov_layout_t) -> ov_status_e:
        ov_preprocess_input_tensor_info_set_layout(tensorInfo, layout)
    if input.colorFormat.isSome:
      let format = rawColorFormats[input.colorFormat.get]
      if input.subNames.len == 0:
        checkStatus(ov_preprocess_input_tensor_info_set_color_format(
                      tensorInfo, format),
                    "apply preprocessing", where & ".colorFormat")
      else:
        var names = newSeq[cstring](input.subNames.len)
        for index, subName in input.subNames:
          names[index] = subName.cstring
        checkStatus(
          ov_preprocess_input_tensor_info_set_color_format_with_subnames(
            tensorInfo, format, csize_t(names.len), addr names[0]),
          "apply preprocessing", where & ".colorFormat")
    if input.spatial.isSome:
      let (height, width) = input.spatial.get
      checkStatus(ov_preprocess_input_tensor_info_set_spatial_static_shape(
                    tensorInfo, csize_t(height), csize_t(width)),
                  "apply preprocessing", where & ".spatialStaticShape")
  finally:
    ov_preprocess_input_tensor_info_free(tensorInfo)

proc applyStep(steps: ptr ov_preprocess_preprocess_steps_t;
               step: PreprocessStep; where: string) =
  var status = OK
  case step.stepKind
  of pskConvertElementType:
    status = ov_preprocess_preprocess_steps_convert_element_type(
      steps, step.elementType.toRaw)
  of pskConvertColor:
    status = ov_preprocess_preprocess_steps_convert_color(
      steps, rawColorFormats[step.colorFormat])
  of pskConvertLayout:
    applyLayout($step.layout, "apply preprocessing",
                where) do (layout: ptr ov_layout_t) -> ov_status_e:
      ov_preprocess_preprocess_steps_convert_layout(steps, layout)
  of pskResize:
    status = ov_preprocess_preprocess_steps_resize(
      steps, rawResizeAlgorithms[step.algorithm])
  of pskMean:
    status = ov_preprocess_preprocess_steps_mean(steps, cfloat(step.value))
  of pskScale:
    status = ov_preprocess_preprocess_steps_scale(steps, cfloat(step.value))
  of pskMeanChannels, pskScaleChannels:
    var values = newSeq[cfloat](step.values.len)
    for index, value in step.values:
      values[index] = cfloat(value)
    status =
      if step.stepKind == pskMeanChannels:
        ov_preprocess_preprocess_steps_mean_multi_channels(
          steps, addr values[0], int32(values.len))
      else:
        ov_preprocess_preprocess_steps_scale_multi_channels(
          steps, addr values[0], int32(values.len))
  of pskCrop:
    var begin = step.cropBegin
    var finish = step.cropEnd
    status = ov_preprocess_preprocess_steps_crop(
      steps, addr begin[0], int32(begin.len), addr finish[0],
      int32(finish.len))
  of pskPad:
    var padBegin = newSeq[cint](step.padBegin.len)
    var padEnd = newSeq[cint](step.padEnd.len)
    for index in 0 ..< padBegin.len:
      padBegin[index] = cint(step.padBegin[index])
      padEnd[index] = cint(step.padEnd[index])
    status = ov_preprocess_preprocess_steps_pad(
      steps, addr padBegin[0], csize_t(padBegin.len), addr padEnd[0],
      csize_t(padEnd.len), cfloat(step.padValue), rawPaddingModes[step.padMode])
  of pskReverseChannels:
    status = ov_preprocess_preprocess_steps_reverse_channels(steps)
  checkStatus(status, "apply preprocessing", where)

proc applyInput(preprocess: ptr ov_preprocess_prepostprocessor_t;
                input: InputPreprocess) =
  var info: ptr ov_preprocess_input_info_t = nil
  if input.byName:
    checkStatus(ov_preprocess_prepostprocessor_get_input_info_by_name(
                  preprocess, input.name.cstring, addr info),
                "apply preprocessing", input.target)
  else:
    checkStatus(ov_preprocess_prepostprocessor_get_input_info_by_index(
                  preprocess, csize_t(input.index), addr info),
                "apply preprocessing", input.target)
  try:
    applyTensorInfo(info, input)
    if input.steps.len > 0:
      var steps: ptr ov_preprocess_preprocess_steps_t = nil
      checkStatus(ov_preprocess_input_info_get_preprocess_steps(info,
                                                                addr steps),
                  "apply preprocessing", input.target & ".steps")
      try:
        for index, step in input.steps:
          applyStep(steps, step, input.target & ".steps[" & $index & "] (" &
            $step.stepKind & ")")
      finally:
        ov_preprocess_preprocess_steps_free(steps)
    if input.modelLayout.isSome:
      var modelInfo: ptr ov_preprocess_input_model_info_t = nil
      checkStatus(ov_preprocess_input_info_get_model_info(info,
                                                          addr modelInfo),
                  "apply preprocessing", input.target & ".model")
      try:
        applyLayout($input.modelLayout.get, "apply preprocessing",
                    input.target & ".model.layout") do (
                      layout: ptr ov_layout_t) -> ov_status_e:
          ov_preprocess_input_model_info_set_layout(modelInfo, layout)
      finally:
        ov_preprocess_input_model_info_free(modelInfo)
  finally:
    ov_preprocess_input_info_free(info)

proc applyOutput(preprocess: ptr ov_preprocess_prepostprocessor_t;
                 output: OutputPostprocess) =
  if output.elementType.isNone:
    return
  var info: ptr ov_preprocess_output_info_t = nil
  if output.byName:
    checkStatus(ov_preprocess_prepostprocessor_get_output_info_by_name(
                  preprocess, output.name.cstring, addr info),
                "apply preprocessing", output.target)
  else:
    checkStatus(ov_preprocess_prepostprocessor_get_output_info_by_index(
                  preprocess, csize_t(output.index), addr info),
                "apply preprocessing", output.target)
  try:
    var tensorInfo: ptr ov_preprocess_output_tensor_info_t = nil
    checkStatus(ov_preprocess_output_info_get_tensor_info(info,
                                                          addr tensorInfo),
                "apply preprocessing", output.target & ".tensor")
    try:
      checkStatus(ov_preprocess_output_set_element_type(
                    tensorInfo, output.elementType.get.toRaw),
                  "apply preprocessing", output.target & ".elementType")
    finally:
      ov_preprocess_output_tensor_info_free(tensorInfo)
  finally:
    ov_preprocess_output_info_free(info)

proc applyPreprocessing*(model: Model; plan: PreprocessPlan): Model =
  ## Applies `plan` and returns the resulting model, a new owner that must be
  ## closed.
  ##
  ## **The source model is modified.** OpenVINO builds the result from the
  ## same graph, so `model` and the result share it afterwards; the usual
  ## next step is to close `model`. Both remain valid, and closing either
  ## does not affect the other.
  ##
  ## Every OpenVINO object created on the way is released before this
  ## returns, also on failure.
  ##
  ## Raises `OpenVinoArgumentError` if `model` is closed. Raises
  ## `OpenVinoError` when OpenVINO rejects part of the plan: the context
  ## names the input and step, for example `input[0].steps[3] (pskResize)`,
  ## or, for a problem OpenVINO only detects while building, the whole plan.
  var preprocess: ptr ov_preprocess_prepostprocessor_t = nil
  checkStatus(ov_preprocess_prepostprocessor_create(model.unsafeRawHandle(),
                                                    addr preprocess),
              "apply preprocessing", "create")
  try:
    for input in plan.inputs:
      applyInput(preprocess, input)
    for output in plan.outputs:
      applyOutput(preprocess, output)
    var built: ptr ov_model_t = nil
    checkStatus(ov_preprocess_prepostprocessor_build(preprocess, addr built),
                "apply preprocessing", "build " & $plan)
    result = wrapModel(built)
  finally:
    ov_preprocess_prepostprocessor_free(preprocess)
