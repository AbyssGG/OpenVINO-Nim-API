# SPDX-License-Identifier: Apache-2.0

## Lazy loading of the optional OpenVINO GenAI C shared library.

import std/[dynlib, macros, os]

import ../../version

const openvinoGenAiLib* {.strdefine.} = ""
  ## Compile-time override, for example `-d:openvinoGenAiLib=/path/to/lib`.

const genAiSoSeriesPrefix =
  $(TargetOpenVinoMajor mod 100) & $TargetOpenVinoMinor
const genAiSoVersionSuffix = genAiSoSeriesPrefix & $TargetOpenVinoPatch

type GenAiLibraryError* = object of CatchableError
  symbol*: string
  attempted*: seq[string]

when defined(windows):
  const platformLibraries = ["openvino_genai_c.dll"]
elif defined(macosx):
  const platformLibraries = ["libopenvino_genai_c.dylib"]
else:
  const platformLibraries = [
    "libopenvino_genai_c.so",
    "libopenvino_genai_c.so." & genAiSoVersionSuffix]

var genAiHandle: LibHandle = nil

proc candidateGenAiLibraries*(): seq[string] =
  if openvinoGenAiLib.len > 0:
    return @[openvinoGenAiLib]
  let configured = getEnv("OPENVINO_GENAI_C_LIBRARY")
  if configured.len > 0:
    return @[configured]
  result = @[]
  for name in platformLibraries:
    result.add(name)
  when not defined(windows) and not defined(macosx):
    for patch in countdown(TargetOpenVinoPatch - 1, 0):
      result.add("libopenvino_genai_c.so." & genAiSoSeriesPrefix & $patch)

proc genAiLibrary(): LibHandle =
  if genAiHandle != nil:
    return genAiHandle
  let candidates = candidateGenAiLibraries()
  for candidate in candidates:
    let handle = loadLib(candidate)
    if handle != nil:
      genAiHandle = handle
      return handle
  var message = "Could not load the optional OpenVINO GenAI C API library.\n"
  message.add("  Expected GenAI baseline: 2026.4.1.0\n")
  message.add("  Library names tried:\n")
  for candidate in candidates:
    message.add("    " & candidate & "\n")
  message.add("  Install/build the matching `openvino_genai_c` library and " &
    "its OpenVINO GenAI, OpenVINO Runtime and tokenizer dependencies, or " &
    "set `-d:openvinoGenAiLib=<full path>`. See docs/genai.md.")
  var err = newException(GenAiLibraryError, message)
  err.attempted = candidates
  raise err

proc genAiFunctionSymbol*(name: string): pointer =
  let address = genAiLibrary().symAddr(name.cstring)
  if address == nil:
    var err = newException(GenAiLibraryError,
      "The OpenVINO GenAI C API library does not export '" & name &
      "'; it may not match GenAI 2026.4.1.0.")
    err.symbol = name
    err.attempted = candidateGenAiLibraries()
    raise err
  result = address

proc missingGenAiSymbols*(names: openArray[string]): seq[string] =
  let handle = genAiLibrary()
  result = @[]
  for name in names:
    if handle.symAddr(name.cstring) == nil:
      result.add(name)

macro genaiImport*(procedure: untyped): untyped =
  ## Lazily resolves a declaration by its upstream C name.
  procedure.expectKind(nnkProcDef)
  if procedure.body.kind != nnkEmpty:
    error("genaiImport expects a declaration without a body", procedure)

  let
    nameNode = procedure.name
    plainName = if nameNode.kind == nnkPostfix: nameNode[1] else: nameNode
    symbolName = newLit($plainName)
    cache = genSym(nskVar, $plainName & "Symbol")
    signature = nnkProcTy.newTree(procedure.params.copyNimTree,
                                  nnkPragma.newTree(ident("cdecl")))

  var call = nnkCall.newTree(cache)
  for index in 1 ..< procedure.params.len:
    let parameter = procedure.params[index]
    for nameIndex in 0 .. parameter.len - 3:
      let argument = parameter[nameIndex]
      call.add(if argument.kind == nnkPostfix: argument[1] else: argument)

  let returnsValue = procedure.params[0].kind != nnkEmpty
  let forward = if returnsValue: nnkAsgn.newTree(ident("result"), call)
                else: call

  # invariant: the function pointer type is built from this C declaration,
  # and the loader refuses a missing symbol before that pointer is called.
  procedure.body = quote do:
    if `cache` == nil:
      `cache` = cast[`signature`](genAiFunctionSymbol(`symbolName`))
    `forward`

  result = newStmtList(
    nnkVarSection.newTree(
      nnkIdentDefs.newTree(cache, signature, newNilLit())),
    procedure)
