# SPDX-License-Identifier: Apache-2.0

## Tests the UTF-8 to UTF-16 path conversion used by the Windows wide-character
## entry points.
##
## These run on every platform even though only Windows calls the conversion,
## because the encoding rules are platform-independent and a test that only runs
## where the bug hurts is a test that catches the bug late.
##
## Needs no OpenVINO runtime: the conversion touches no C API.

import std/[strutils, unittest]

import openvino/errors
import openvino/private/paths

suite "ASCII detection":
  test "plain ASCII is recognised":
    check isAscii("C:/models/relu.xml")
    check isAscii("")

  test "anything above U+007F is not ASCII":
    check not isAscii("C:/模型/relu.xml")
    check not isAscii("café")

suite "UTF-16 conversion":
  test "ASCII widens one code unit per character, plus a terminator":
    let units = toUtf16("abc")
    check units == @[uint16(0x61), 0x62, 0x63, 0x00]

  test "an empty string still produces a terminator":
    # The terminator is what makes `addr result[0]` a valid wchar_t* for a C
    # call, so the sequence must never be empty.
    check toUtf16("") == @[uint16(0x00)]

  test "a code point in the basic plane becomes one code unit":
    # U+6A21 MODEL, first character of 模型.
    let units = toUtf16("模")
    check units == @[uint16(0x6a21), 0x00]

  test "a supplementary code point becomes a surrogate pair":
    # U+1F600 GRINNING FACE: offset 0xF600, so high = D800 + (F600 >> 10) =
    # D83D and low = DC00 + (F600 and 3FF) = DE00. Worked out by hand, because
    # an expectation produced by the code under test proves nothing.
    let units = toUtf16("\u{1F600}")
    check units == @[uint16(0xd83d), 0xde00, 0x00]

  test "a mixed path keeps its characters in order":
    let units = toUtf16("C:/模/a")
    check units == @[uint16(0x43), 0x3a, 0x2f, 0x6a21, 0x2f, 0x61, 0x00]

  test "the length is code units, not bytes or characters":
    # 模 is three bytes in UTF-8 and one code unit in UTF-16. A conversion that
    # confused the two would size the buffer wrongly.
    check toUtf16("模模").len == 3

suite "rejected input":
  test "a lone continuation byte is refused":
    expect OpenVinoArgumentError:
      discard toUtf16("a\x80b")

  test "a truncated multi-byte sequence is refused":
    expect OpenVinoArgumentError:
      discard toUtf16("\xe6\xa8")

  test "the message names the offset of the first invalid byte":
    try:
      discard toUtf16("ab\xffcd")
      check false
    except OpenVinoArgumentError as err:
      check "offset 2" in err.msg

  test "an encoded surrogate is refused rather than passed through":
    # U+D800 encoded as UTF-8, which some encoders emit. Passing it on would
    # produce a UTF-16 sequence containing an unpaired surrogate.
    expect OpenVinoArgumentError:
      discard toUtf16("\xed\xa0\x80")

suite "the wide pointer template":
  test "the pointer addresses the first code unit":
    withWidePath("ab", wide):
      check wide != nil
      check cast[ptr UncheckedArray[uint16]](wide)[0] == uint16(0x61)
      check cast[ptr UncheckedArray[uint16]](wide)[1] == uint16(0x62)
      check cast[ptr UncheckedArray[uint16]](wide)[2] == uint16(0x00)

  test "an invalid path raises before the body runs":
    var bodyRan = false
    expect OpenVinoArgumentError:
      withWidePath("\xff", wide):
        discard wide
        bodyRan = true
    check not bodyRan
