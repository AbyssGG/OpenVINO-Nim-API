# SPDX-License-Identifier: Apache-2.0

## Dimensions and partial shapes, without a runtime.
##
## Every rule that decides what is static, what is valid and what fits is
## implemented in Nim rather than delegated to OpenVINO's own predicates, which
## misclassify zero-length dimensions and scalars. These tests are where those
## rules are pinned.

import std/[strutils, unittest]

import openvino

suite "dimensions":
  test "a static dimension has one length, including zero":
    check staticDim(4).isStatic
    check staticDim(4).minLength == 4
    check staticDim(4).maxLength == 4
    check staticDim(0).isStatic
    check not staticDim(0).isDynamic

  test "a dynamic dimension is [0, unbounded]":
    let any = dynamicDim()
    check any.isDynamic
    check any.minLength == 0
    check any.maxLength == -1
    check not any.hasUpperBound
    check any == atLeastDim(0)

  test "bounded and lower-bounded dimensions keep their limits":
    check boundedDim(1, 8).minLength == 1
    check boundedDim(1, 8).maxLength == 8
    check boundedDim(1, 8).hasUpperBound
    check atLeastDim(2).minLength == 2
    check not atLeastDim(2).hasUpperBound
    check boundedDim(3, 3) == staticDim(3)
    check boundedDim(3, 3).isStatic

  test "invalid dimensions are refused before reaching C":
    expect OpenVinoArgumentError:
      discard staticDim(-1)
    expect OpenVinoArgumentError:
      discard boundedDim(-1, 4)
    expect OpenVinoArgumentError:
      discard boundedDim(5, 4)
    expect OpenVinoArgumentError:
      discard boundedDim(2, -1)
    expect OpenVinoArgumentError:
      discard atLeastDim(-3)

  test "contains checks a length against the interval":
    check 4 in staticDim(4)
    check 5 notin staticDim(4)
    check 0 in dynamicDim()
    check 1_000_000 in dynamicDim()
    check 1 in boundedDim(1, 8)
    check 8 in boundedDim(1, 8)
    check 9 notin boundedDim(1, 8)
    check 0 notin boundedDim(1, 8)
    check 2 in atLeastDim(2)
    check 1 notin atLeastDim(2)
    check -1 notin dynamicDim()

  test "dimensions format the way OpenVINO prints them":
    check $staticDim(4) == "4"
    check $staticDim(0) == "0"
    check $dynamicDim() == "?"
    check $boundedDim(1, 8) == "1..8"
    check $boundedDim(0, 8) == "0..8"
    check $atLeastDim(2) == "2.."

suite "partial shapes":
  test "a known rank keeps its dimensions in order":
    let shape = initPartialShape([dynamicDim(), staticDim(4)])
    check shape.hasStaticRank
    check shape.rank == 2
    check shape.dims == @[dynamicDim(), staticDim(4)]
    check shape.isDynamic
    check not shape.isStatic

  test "a static Shape converts both ways":
    let shape = initPartialShape(initShape(1, 3, 224, 224))
    check shape.isStatic
    check shape.toShape == initShape(1, 3, 224, 224)
    check $shape == "[1, 3, 224, 224]"

  test "a scalar has rank 0 and is static, unlike ov_rank_is_dynamic says":
    let scalar = initPartialShape(initShape())
    check scalar.hasStaticRank
    check scalar.rank == 0
    check scalar.isStatic
    check scalar.toShape.rank == 0
    check $scalar == "[] (scalar)"
    check scalar == initPartialShape(newSeq[Dimension]())

  test "a zero-length dimension is static":
    let empty = initPartialShape([staticDim(0), staticDim(4)])
    check empty.isStatic
    check empty.toShape == initShape(0, 4)

  test "a dynamic rank refuses rank and dims rather than look like a scalar":
    let unknown = dynamicRankShape()
    check not unknown.hasStaticRank
    check unknown.isDynamic
    check $unknown == "[...]"
    expect OpenVinoArgumentError:
      discard unknown.rank
    expect OpenVinoArgumentError:
      discard unknown.dims
    check unknown != initPartialShape(initShape())
    check unknown == dynamicRankShape()

  test "toShape refuses anything dynamic and names the shape":
    try:
      discard initPartialShape([boundedDim(1, 8), staticDim(4)]).toShape
      check false
    except OpenVinoArgumentError as err:
      check "[1..8, 4]" in err.msg
    expect OpenVinoArgumentError:
      discard dynamicRankShape().toShape

  test "dims returns a copy":
    let shape = initPartialShape([staticDim(2)])
    var copy = shape.dims
    copy[0] = dynamicDim()
    check shape.dims == @[staticDim(2)]

  test "partial shapes format with commas and dimension notation":
    check $initPartialShape([dynamicDim(), staticDim(4)]) == "[?, 4]"
    check $initPartialShape([boundedDim(1, 8), staticDim(3), staticDim(224),
                             staticDim(224)]) == "[1..8, 3, 224, 224]"
    check $initPartialShape([atLeastDim(2)]) == "[2..]"

  test "equality compares rank knowledge and every dimension":
    check initPartialShape([dynamicDim(), staticDim(4)]) ==
      initPartialShape([atLeastDim(0), staticDim(4)])
    check initPartialShape([staticDim(1), staticDim(4)]) !=
      initPartialShape([staticDim(4), staticDim(1)])
    check initPartialShape([staticDim(4)]) !=
      initPartialShape([staticDim(4), staticDim(4)])

suite "accepts":
  test "an exact static shape is accepted and others are not":
    let shape = initPartialShape(initShape(1, 4))
    check shape.accepts(initShape(1, 4))
    check not shape.accepts(initShape(2, 4))
    check not shape.accepts(initShape(4))

  test "a dynamic batch accepts any batch size":
    let shape = initPartialShape([dynamicDim(), staticDim(4)])
    for batch in [0, 1, 3, 7, 1000]:
      check shape.accepts(initShape(batch, 4))
    check not shape.accepts(initShape(3, 5))

  test "a bounded dimension accepts only its interval":
    let shape = initPartialShape([boundedDim(1, 8), staticDim(4)])
    check shape.accepts(initShape(1, 4))
    check shape.accepts(initShape(8, 4))
    check not shape.accepts(initShape(9, 4))
    check not shape.accepts(initShape(0, 4))

  test "a dynamic rank accepts any shape, including a scalar":
    check dynamicRankShape().accepts(initShape())
    check dynamicRankShape().accepts(initShape(2, 3, 4))

  test "a scalar shape accepts only a scalar":
    let scalar = initPartialShape(initShape())
    check scalar.accepts(initShape())
    check not scalar.accepts(initShape(1))
