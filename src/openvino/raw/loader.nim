# SPDX-License-Identifier: Apache-2.0

## Explicit loading of the OpenVINO C API library and resolution of its
## symbols.
##
## Nim's `dynlib` pragma is not used. It loads during module initialisation and
## aborts the process on failure, before any Nim code runs, so the diagnostics
## the development plan requires are unreachable with it. Both the constant and
## the variable form were measured; see
## `docs/decisions/0001-symbol-loading.md`.
##
## Loading is lazy: it happens on the first symbol resolution, so importing the
## package does not require OpenVINO to be installed.
##
## This module is the one place in the raw layer that raises. Every bound
## function still reports operational failure through `ov_status_e`; only the
## "the library or symbol does not exist" case becomes an exception, because a
## call that never happened has no status to return.

import std/[dynlib, macros, os]

import ../private/library
import ../version

type OpenVinoLibraryError* = object of CatchableError
  ## Raised when the OpenVINO C API library, or a symbol this package needs,
  ## cannot be resolved.
  ##
  ## This is distinct from `OpenVinoError`, which reports a status code from a
  ## call that did happen. Seeing this type means the runtime is missing,
  ## unreachable by the dynamic loader, or not the expected version.
  symbol*: string
    ## Symbol that failed to resolve, or the empty string when the library
    ## itself could not be loaded.

  attempted*: seq[string]
    ## Library names or paths that were tried, in order.

var
  runtimeHandle: LibHandle = nil
    ## Cached library handle. Process-wide by nature: the dynamic loader has
    ## one notion of a loaded library.
    ##
    ## Deliberately unguarded by a lock. Two threads racing the first
    ## resolution can both call `loadLib`, which is harmless: the platform
    ## loader reference-counts, both calls return a handle for the same
    ## mapping, and symbol addresses are identical. The only cost is one extra
    ## reference. A lock here would buy nothing and add a global.

proc describeFailure(reason: string; attempted: seq[string]): string =
  ## Builds the diagnostic for a failed load or a missing symbol.
  ##
  ## Names the platform, every candidate tried, the expected OpenVINO version
  ## and how this platform finds a shared library, because a bare "could not
  ## load" leaves the reader with nothing to act on.
  result = reason & "\n"
  result.add("  Target platform: " & platformName & "\n")
  result.add("  Expected OpenVINO: " & TargetOpenVinoVersion & "\n")
  var foundOnDisk = false
  if attempted.len > 0:
    result.add("  Library names tried:\n")
    for candidate in attempted:
      var note = ""
      if isExplicitPath(candidate):
        if fileExists(candidate):
          note = " (file exists but could not be loaded)"
          foundOnDisk = true
        else:
          note = " (no such file)"
      result.add("    " & candidate & note & "\n")

  if foundOnDisk:
    # Distinguishing these two cases matters because the fix is different. A
    # library that exists and still fails to load is missing a dependency of
    # its own, which no amount of pointing at the right file will solve.
    result.add("  The file was found, so this is not a missing-file " &
      "problem: one of its own dependencies could not be loaded. The " &
      "OpenVINO C API library needs openvino.dll or libopenvino.so from the " &
      "same directory, and those in turn need the bundled oneTBB library " &
      "from the runtime's 3rdparty directory, which is not the same " &
      "directory. Running the official setupvars script puts all of them on " &
      "the search path.\n")
  result.add("  " & loaderHint() & "\n")
  result.add("  " & deploymentHint())

proc raiseLibraryError(reason, symbol: string;
                       attempted: seq[string]) {.noreturn.} =
  ## Raises `OpenVinoLibraryError` carrying both the readable diagnostic and
  ## the structured fields a caller might want to inspect.
  var err = newException(OpenVinoLibraryError,
                         describeFailure(reason, attempted))
  err.symbol = symbol
  err.attempted = attempted
  raise err

proc runtimeLibrary(): LibHandle =
  ## Returns the loaded OpenVINO C API library, loading it on first use.
  ##
  ## Raises `OpenVinoLibraryError` when no candidate can be loaded.
  if runtimeHandle != nil:
    return runtimeHandle

  let candidates = candidateLibraries()
  for candidate in candidates:
    let handle = loadLib(candidate)
    if handle != nil:
      runtimeHandle = handle
      return handle

  raiseLibraryError("Could not load the OpenVINO C API library.", "",
                    candidates)

proc functionSymbol*(name: string): pointer =
  ## Resolves the exported function `name` and returns its address.
  ##
  ## Raises `OpenVinoLibraryError` when the library cannot be loaded or the
  ## symbol is absent. A missing symbol usually means the installed runtime is
  ## older than the pinned baseline, so the message says which version is
  ## expected.
  # The conversion is explicit because Nim is making the implicit form an
  # error, and because `symAddr` only reads the name.
  let address = runtimeLibrary().symAddr(name.cstring)
  if address == nil:
    raiseLibraryError("The OpenVINO C API library does not export '" & name &
      "'. This usually means the installed runtime is older than the version " &
      "this package requires.", name, candidateLibraries())
  result = address

proc dataSymbol*(name: string): pointer =
  ## Resolves the exported data symbol `name` and returns the address of the
  ## variable itself, not its value.
  ##
  ## Property keys are exported `const char*` variables rather than macros or
  ## functions, so reading one means dereferencing this address. Kept separate
  ## from `functionSymbol` so that call sites state which kind they expect.
  ##
  ## Raises `OpenVinoLibraryError` on failure.
  let address = runtimeLibrary().symAddr(name.cstring)
  if address == nil:
    raiseLibraryError("The OpenVINO C API library does not export the data " &
      "symbol '" & name & "'.", name, candidateLibraries())
  result = address

proc stringDataSymbol*(name: string): cstring =
  ## Resolves the exported `const char*` variable `name` and returns its
  ## value.
  ##
  ## The returned pointer is borrowed from the library's own data and stays
  ## valid as long as the library is loaded. It must never be released.
  let slot = cast[ptr cstring](dataSymbol(name))
  result = slot[]

proc isRuntimeLoaded*(): bool =
  ## Reports whether the library has already been loaded.
  ##
  ## Intended for tests and diagnostics. Does not attempt a load, so it never
  ## raises.
  runtimeHandle != nil

proc missingSymbols*(names: openArray[string]): seq[string] =
  ## Returns the subset of `names` the loaded library does not export.
  ##
  ## Raises `OpenVinoLibraryError` when the library itself cannot be loaded,
  ## because that is a different failure with a different fix. An empty result
  ## means every name resolved.
  let handle = runtimeLibrary()
  result = @[]
  for name in names:
    if handle.symAddr(name.cstring) == nil:
      result.add(name)

macro openvinoImport*(procedure: untyped): untyped =
  ## Turns a bodyless procedure declaration into a lazily resolved forwarder.
  ##
  ## Written as a pragma so that a binding stays a single declaration that
  ## reads like the C prototype it mirrors, which is what makes the raw layer
  ## auditable against the header:
  ##
  ## ```nim
  ## proc ov_core_create*(core: ptr ptr ov_core_t): ov_status_e
  ##   {.openvinoImport.}
  ## ```
  ##
  ## The expansion declares a private cached procedure pointer, resolves it
  ## through `functionSymbol` on first call, and forwards the arguments. The
  ## imported C name is the Nim procedure's own name, so the two can never
  ## disagree.
  ##
  ## The calling convention is always `cdecl`, matching what the OpenVINO
  ## headers expand `OPENVINO_C_API` to on every supported platform.
  procedure.expectKind(nnkProcDef)
  if procedure.body.kind != nnkEmpty:
    error("openvinoImport expects a declaration without a body", procedure)

  let
    nameNode = procedure.name
    plainName = (if nameNode.kind == nnkPostfix: nameNode[1] else: nameNode)
    symbolName = newLit($plainName)
    cache = genSym(nskVar, $plainName & "Symbol")
    signature = nnkProcTy.newTree(procedure.params.copyNimTree,
                                  nnkPragma.newTree(ident("cdecl")))

  var call = nnkCall.newTree(cache)
  for index in 1 ..< procedure.params.len:
    let parameter = procedure.params[index]
    # An IdentDefs may declare several parameters of one type, so forward each
    # name rather than assuming one name per group.
    for nameIndex in 0 .. parameter.len - 3:
      let argument = parameter[nameIndex]
      call.add(if argument.kind == nnkPostfix: argument[1] else: argument)

  let returnsValue = procedure.params[0].kind != nnkEmpty
  let forward = if returnsValue: nnkAsgn.newTree(ident("result"), call)
                else: call

  procedure.body = quote do:
    if `cache` == nil:
      `cache` = cast[`signature`](functionSymbol(`symbolName`))
    `forward`

  result = newStmtList(
    nnkVarSection.newTree(
      nnkIdentDefs.newTree(cache, signature, newNilLit())),
    procedure)
