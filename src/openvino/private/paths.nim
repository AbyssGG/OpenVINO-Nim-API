# SPDX-License-Identifier: Apache-2.0

## Path encoding for the Windows wide-character entry points.
##
## Why this file exists: `ov_core_read_model` takes `const char*`, and the C API
## does not document how Windows builds interpret those bytes. The two
## possibilities are "UTF-8" and "the process's active code page", and they
## disagree for exactly the paths users complain about: a Chinese directory
## name, an accented surname, an emoji in a folder name. Under the code-page
## reading, such a path is mangled before the file system sees it and the
## failure surfaces as "model file not found" for a file that plainly exists.
##
## Measured, not assumed: on a Windows machine with active code page 936
## (GB2312), OpenVINO 2026.4 read a model from a path containing both Chinese
## and Cyrillic through the *narrow* entry point successfully. So 2026.4 treats
## those bytes as UTF-8, and this module is not what makes non-ASCII paths work
## today.
##
## It is kept anyway, because "works in the version we measured" is not the same
## as "is specified to work". OpenVINO also ships a `_unicode` family taking
## `const wchar_t*`, which is 16 bits on Windows and therefore UTF-16: no code
## page enters into it, so the behaviour cannot depend on an undocumented
## interpretation that a later build or a differently configured host might
## change. `tests/integration/tcpu_inference.nim` records what the narrow entry
## point does rather than asserting that it fails, so the day that answer
## changes, the test says so instead of breaking.
##
## The conversion is written out here rather than delegated to `std/widestrs`,
## whose `WideCString` representation differs between memory managers; a
## `seq[uint16]` has one obvious layout and one obvious lifetime.
##
## Internal to the package. Nothing here appears in the public API.

import std/[strutils, unicode]

import ../errors

const
  surrogateFirst = 0xd800'u32
  surrogateLast = 0xdfff'u32
  lowSurrogateFirst = 0xdc00'u32
  supplementaryFirst = 0x10000'u32
  maximumCodePoint = 0x10ffff'u32

proc toUtf16*(text: string): seq[uint16] =
  ## Converts UTF-8 `text` to a zero-terminated UTF-16 code-unit sequence.
  ##
  ## The terminator is part of the result, so `addr result[0]` is a valid
  ## `wchar_t*` for a C call and the result is never empty.
  ##
  ## Raises `OpenVinoArgumentError` on input that is not valid UTF-8, and on an
  ## encoded surrogate. Both are refused rather than replaced: substituting
  ## U+FFFD would turn a caller's mistake into a path that cannot exist, and the
  ## resulting "file not found" would name a string the caller never wrote.
  let invalidAt = validateUtf8(text)
  if invalidAt >= 0:
    raiseArgumentError("path is not valid UTF-8; the first invalid byte is at " &
      "offset " & $invalidAt)

  result = newSeqOfCap[uint16](text.len + 1)
  for codePoint in text.runes:
    let code = uint32(int32(codePoint))
    if code >= surrogateFirst and code <= surrogateLast:
      raiseArgumentError("path contains an encoded UTF-16 surrogate " &
        "(U+" & toHex(int(code), 4) & "), which is not a valid code point")
    if code > maximumCodePoint:
      raiseArgumentError("path contains a code point above U+10FFFF")
    if code >= supplementaryFirst:
      let offset = code - supplementaryFirst
      result.add(uint16(surrogateFirst + (offset shr 10)))
      result.add(uint16(lowSurrogateFirst + (offset and 0x3ff)))
    else:
      result.add(uint16(code))
  result.add(0'u16)

proc isAscii*(text: string): bool =
  ## Reports whether every byte of `text` is ASCII.
  ##
  ## Used to decide whether the narrow entry point is safe, so that the common
  ## case keeps taking the path OpenVINO itself tests most.
  for character in text:
    if uint8(character) >= 0x80'u8:
      return false
  true

template withWidePath*(text: string; pointerName, body: untyped) =
  ## Runs `body` with `pointerName` bound to a `ptr uint16` holding `text` as
  ## zero-terminated UTF-16.
  ##
  ## The sequence is a local, so it stays alive for the whole of `body` and is
  ## reclaimed afterwards. A caller that returned the pointer instead would be
  ## handing out an address into freed memory.
  block:
    var units = toUtf16(text)
    let pointerName = cast[ptr uint16](addr units[0])
    body
