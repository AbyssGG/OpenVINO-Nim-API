# SPDX-License-Identifier: Apache-2.0

## Preprocessing plans without a runtime: building, chaining, reusing a target
## and every argument check that happens before OpenVINO is involved.
##
## Layouts need the runtime to validate, so no test here uses one; they are
## covered by `tests/integration/tpreprocess.nim`.

import std/[strutils, unittest]

import openvino

suite "building a plan":
  test "chained calls record steps in order":
    var plan = initPreprocessPlan()
    plan.input(0).tensorElementType(etU8).convertElementType(etF32)
      .resize(raNearest).mean([float32(1), 2, 3]).scale(2).reverseChannels()
    check plan.inputs.len == 1
    var kinds: seq[PreprocessStepKind] = @[]
    for step in plan.inputs[0].steps:
      kinds.add(step.kind)
    check kinds == @[pskConvertElementType, pskResize, pskMeanChannels,
                     pskScale, pskReverseChannels]

  test "asking for the same input again continues its description":
    var plan = initPreprocessPlan()
    plan.input(0).mean(1)
    plan.input(0).scale(2)
    plan.input("input").mean(3)
    plan.input("input").scale(4)
    check plan.inputs.len == 2
    check plan.inputs[0].steps.len == 2
    check plan.inputs[1].steps.len == 2

  test "steps and plans format readably for error messages":
    var plan = initPreprocessPlan()
    plan.input(0).tensorElementType(etU8).tensorSpatialStaticShape(480, 640)
      .crop([int32(0), 0], [int32(1), 2]).pad([0, 1], [0, 1], 0.5, pmEdge)
    plan.output("output").tensorElementType(etF32)
    let text = $plan
    checkpoint(text)
    check "input[0]" in text
    check "etU8" in text
    check "480x640" in text
    check "crop([0, 0], [1, 2])" in text
    check "pad([0, 1], [0, 1], 0.5, pmEdge)" in text
    check "output[\"output\"]" in text

  test "a plan is a value: copies are independent":
    var first = initPreprocessPlan()
    first.input(0).mean(1)
    var second = first
    second.input(0).scale(2)
    check first.inputs[0].steps.len == 1
    check second.inputs[0].steps.len == 2

  test "an empty plan has no inputs or outputs":
    let plan = initPreprocessPlan()
    check plan.inputs.len == 0
    check plan.outputs.len == 0
    check $plan == ""

suite "argument checks":
  test "targets must be valid":
    var plan = initPreprocessPlan()
    expect OpenVinoArgumentError:
      discard plan.input(-1)
    expect OpenVinoArgumentError:
      discard plan.input("")
    expect OpenVinoArgumentError:
      discard plan.input("in\0put")
    expect OpenVinoArgumentError:
      discard plan.output(-2)
    expect OpenVinoArgumentError:
      discard plan.output("")

  test "mean and scale reject empty, non-finite and zero values":
    var plan = initPreprocessPlan()
    expect OpenVinoArgumentError:
      plan.input(0).mean(newSeq[float32]())
    expect OpenVinoArgumentError:
      plan.input(0).mean(NaN.float32)
    expect OpenVinoArgumentError:
      plan.input(0).mean([float32(1), Inf.float32])
    expect OpenVinoArgumentError:
      plan.input(0).scale(0)
    expect OpenVinoArgumentError:
      plan.input(0).scale([float32(1), 0])
    expect OpenVinoArgumentError:
      plan.input(0).scale(newSeq[float32]())
    check plan.inputs[0].steps.len == 0

  test "crop and pad need equal, non-empty lists that fit in int32":
    var plan = initPreprocessPlan()
    expect OpenVinoArgumentError:
      plan.input(0).crop(newSeq[int32](), newSeq[int32]())
    expect OpenVinoArgumentError:
      plan.input(0).crop([int32(0)], [int32(1), 2])
    expect OpenVinoArgumentError:
      plan.input(0).pad(newSeq[int](), newSeq[int]())
    expect OpenVinoArgumentError:
      plan.input(0).pad([0, 1], [0])
    expect OpenVinoArgumentError:
      plan.input(0).pad([0, int(high(int32)) + 1], [0, 0])
    expect OpenVinoArgumentError:
      plan.input(0).pad([0, 1], [0, 1], Inf.float32)

  test "spatial shapes and color sub-names are checked":
    var plan = initPreprocessPlan()
    expect OpenVinoArgumentError:
      plan.input(0).tensorSpatialStaticShape(0, 640)
    expect OpenVinoArgumentError:
      plan.input(0).tensorSpatialStaticShape(480, -1)
    expect OpenVinoArgumentError:
      plan.input(0).tensorColorFormat(cfNv12TwoPlanes, ["y", ""])
    expect OpenVinoArgumentError:
      plan.input(0).tensorColorFormat(cfNv12TwoPlanes, ["y", "u\0v"])
    plan.input(0).tensorColorFormat(cfNv12TwoPlanes, ["y", "uv"])
    check "cfNv12TwoPlanes" in $plan
