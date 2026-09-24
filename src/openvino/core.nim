# SPDX-License-Identifier: Apache-2.0

## `Core`: the entry point to the runtime. Device discovery, reading models,
## compiling them, and importing a previously exported blob.
##
## Everything here is explicit. No device is chosen for you, nothing falls back
## to another device after a failure, no cache is enabled behind your back and
## no directory is created. Those are all reasonable things for an application
## to do and all wrong things for a general-purpose binding to decide.

import std/os

import compiled_model
import errors
import model
import private/conversions
import private/handles

# Imported only where it is used. Everything this module needs from `paths`
# lives inside a `when defined(windows)` branch, so importing it
# unconditionally makes every Linux and macOS build report an unused import.
# That warning is noise on the platform where the code is correct, and noise
# is what stops anyone reading warnings.
when defined(windows):
  import private/paths
import properties
import raw/compiled_model as rawCompiled
import raw/core as rawCore
import raw/model as rawModel
import version

export compiled_model
export model
export properties

type
  RuntimeVersion* = object
    ## What the loaded runtime reports about itself.
    ##
    ## `build` is the runtime's own string, unparsed. It is kept verbatim
    ## because inventing a structured version from a string that did not parse
    ## would be worse than admitting the parse failed.
    build*: string
    description*: string
    major*: int
    minor*: int
    parsed*: bool
      ## Whether `major` and `minor` were recovered from `build`. When false,
      ## both are zero and only `build` is meaningful.

  Core* = object
    ## The OpenVINO runtime entry point.
    ##
    ## Owns one `ov_core_t`. Copying shares the native object and the closed
    ## state. There is deliberately no global default `Core`: a hidden one would
    ## make lifetime and configuration invisible.
    ##
    ## Threads: OpenVINO documents `ov::Core` as safe to share, and reading a
    ## model or compiling from several threads through one `Core` is the
    ## intended use. This package adds no lock of its own, and `close()` is the
    ## exception: closing while another thread is still calling is a use-after-
    ## close that the closed check cannot make safe. Nothing here has been
    ## tested under concurrency, so treat the sharing as OpenVINO's claim rather
    ## than as this package's measurement.
    handle: Handle[ov_core_t]

proc releaseCore(native: ptr ov_core_t) {.nimcall.} =
  ## Release function handed to the handle model.
  ov_core_free(native)

proc parseRuntimeVersion(build: string): tuple[major, minor: int; ok: bool] =
  ## Recovers a major and minor version from a build string.
  ##
  ## OpenVINO build strings begin with `<major>.<minor>.` but this is not part of
  ## any documented contract, so a failure to parse is reported rather than
  ## guessed at.
  result = (0, 0, false)
  var
    index = 0
    major = 0
    minor = 0
    digits = 0
  while index < build.len and build[index] in {'0' .. '9'}:
    major = major * 10 + int(ord(build[index]) - ord('0'))
    inc index
    inc digits
  if digits == 0 or index >= build.len or build[index] != '.':
    return
  inc index
  digits = 0
  while index < build.len and build[index] in {'0' .. '9'}:
    minor = minor * 10 + int(ord(build[index]) - ord('0'))
    inc index
    inc digits
  if digits == 0:
    return
  result = (major, minor, true)

proc runtimeVersion*(): RuntimeVersion =
  ## Returns the loaded runtime's version.
  ##
  ## Does not need a `Core`, so it is the cheapest way to find out whether a
  ## usable runtime is present at all. Copies both strings and releases
  ## OpenVINO's allocation before returning.
  ##
  ## Raises `OpenVinoLibraryError` when no runtime can be loaded, and
  ## `OpenVinoError` when the query itself fails.
  var native: ov_version_t
  checkStatus(ov_get_openvino_version(addr native), "get OpenVINO version")
  let copied = takeVersion(native)
  let parsed = parseRuntimeVersion(copied.build)
  result = RuntimeVersion(build: copied.build,
                          description: copied.description,
                          major: parsed.major, minor: parsed.minor,
                          parsed: parsed.ok)

proc isSupported*(version: RuntimeVersion): bool =
  ## Reports whether `version` is the baseline this package was verified
  ## against.
  ##
  ## An unparsable build string is reported as unsupported, because "we could
  ## not tell" is not the same as "it is fine".
  version.parsed and version.major == TargetOpenVinoMajor and
    version.minor == TargetOpenVinoMinor

proc requireSupportedRuntime*() =
  ## Raises `OpenVinoVersionError` unless the loaded runtime matches the pinned
  ## baseline.
  ##
  ## Not called automatically. A mismatched runtime often works, and refusing to
  ## start would be worse than letting the caller decide. Call this when you
  ## would rather fail early with a clear message than at some later symbol.
  let version = runtimeVersion()
  if not version.isSupported():
    let reason =
      if not version.parsed:
        "its build string could not be parsed for a major and minor version"
      else:
        "it reports " & $version.major & "." & $version.minor
    raise newVersionError(version.build, TargetOpenVinoVersion, reason)

proc newCore*(): Core =
  ## Creates a `Core`.
  ##
  ## This is where an incomplete deployment surfaces. Loading the C API library
  ## needs one file; creating a `Core` additionally needs `plugins.xml`, the
  ## device plugins and the model frontends from the same runtime directory.
  ##
  ## Raises `OpenVinoLibraryError` when the library cannot be loaded, and
  ## `OpenVinoError` when the runtime is present but incomplete.
  var native: ptr ov_core_t = nil
  checkStatus(ov_core_create(addr native), "create OpenVINO core")
  result = Core(handle: newHandle(native, releaseCore, "core"))

proc close*(core: Core) =
  ## Releases the core. Safe to call more than once.
  ##
  ## Close the models, compiled models and requests obtained from it first.
  core.handle.close()

proc isClosed*(core: Core): bool =
  ## Reports whether the core has been closed. Never raises.
  core.handle.isClosed()

proc availableDevices*(core: Core): seq[string] =
  ## Returns the device names OpenVINO can see, such as `CPU` or `GPU.0`.
  ##
  ## Discovered from the installed plugins at call time, not assumed at compile
  ## time. Copies every name and releases the native list before returning.
  ##
  ## Raises `OpenVinoArgumentError` if the core is closed.
  var devices: ov_available_devices_t
  checkStatus(ov_core_get_available_devices(core.handle.native(),
                                           addr devices),
              "list available devices")
  result = takeDeviceNames(devices)

proc getProperty*(core: Core; device, key: string): string =
  ## Reads one property of `device` as a string.
  ##
  ## Copies the value and releases OpenVINO's allocation before returning.
  ##
  ## Raises `OpenVinoError` for an unknown device or an unsupported property.
  var native: cstring = nil
  checkStatus(ov_core_get_property(core.handle.native(), device.cstring,
                                  key.cstring, addr native),
              "get device property", device & " " & key)
  result = takeString(native)

proc setProperties*(core: Core; device: string;
                    values: openArray[Property]) =
  ## Applies `values` to `device`.
  ##
  ## Raises `OpenVinoError` when the device rejects a property, and
  ## `OpenVinoArgumentError` if the core is closed.
  let native = core.handle.native()
  withRawProperties(values, rawProperties, count):
    checkStatus(ov_core_set_properties(native, device.cstring, count,
                                      rawProperties),
                "set device properties", device)

proc readModel*(core: Core; modelPath: string; weightsPath = ""): Model =
  ## Reads a model from `modelPath`.
  ##
  ## **Performs file I/O** and **blocks**. When `weightsPath` is empty OpenVINO
  ## derives the weights path itself, which is what you want for an IR pair.
  ##
  ## Checks that `modelPath` exists first, so a typo produces a message naming
  ## the file rather than whatever the runtime happens to say.
  ##
  ## Raises `OpenVinoArgumentError` when the path does not exist,
  ## `OpenVinoError` when OpenVINO cannot parse the model.
  if not fileExists(modelPath):
    raiseArgumentError("model file does not exist: " & modelPath)
  if weightsPath.len > 0 and not fileExists(weightsPath):
    raiseArgumentError("weights file does not exist: " & weightsPath)
  var native: ptr ov_model_t = nil
  let coreNative = core.handle.native()

  # On Windows a path that is not pure ASCII goes through the wide-character
  # entry point, where UTF-16 leaves no room for a code-page interpretation.
  # 2026.4's narrow entry point was measured to accept UTF-8 as well, so this is
  # insurance against an undocumented behaviour rather than a fix for a
  # reproduced failure; see src/openvino/private/paths.nim. ASCII keeps the
  # narrow call, which is the path OpenVINO itself exercises most.
  when defined(windows):
    if not isAscii(modelPath) or not isAscii(weightsPath):
      withWidePath(modelPath, widePath):
        var weightUnits = toUtf16(weightsPath)
        # invariant: `toUtf16` always returns at least the terminator, so index
        # 0 exists. `weightUnits` is a local that outlives the call below, and
        # the cast only names the element width the header declares for
        # `wchar_t` on Windows, which the ABI test verifies is 16 bits.
        let wideWeights =
          if weightsPath.len > 0:
            cast[ptr uint16](addr weightUnits[0])
          else:
            nil
        checkStatus(ov_core_read_model_unicode(coreNative, widePath,
                                              wideWeights, addr native),
                    "read model", modelPath)
      return wrapModel(native)

  let weights = if weightsPath.len > 0: weightsPath.cstring else: nil
  checkStatus(ov_core_read_model(coreNative, modelPath.cstring,
                                weights, addr native),
              "read model", modelPath)
  result = wrapModel(native)

proc compileModel*(core: Core; source: Model; device: string;
                   values: openArray[Property] = []): CompiledModel =
  ## Compiles `source` for `device`.
  ##
  ## **Blocks**, often for a long time. `device` is required: no default is
  ## chosen and no other device is tried if this one fails.
  ##
  ## Uses the non-variadic properties entry point, which is one of the reasons
  ## this package requires OpenVINO 2026.4.
  ##
  ## Raises `OpenVinoError` for an unknown device or a model the device cannot
  ## take, and `OpenVinoArgumentError` if either object is closed.
  let
    coreNative = core.handle.native()
    modelNative = source.unsafeRawHandle()
  var native: ptr ov_compiled_model_t = nil
  withRawProperties(values, rawProperties, count):
    checkStatus(ov_core_compile_model_props(coreNative, modelNative,
                                           device.cstring, count,
                                           rawProperties, addr native),
                "compile model", device)
  result = wrapCompiledModel(native)

proc compileModel*(core: Core; modelPath: string; device: string;
                   values: openArray[Property] = []): CompiledModel =
  ## Reads and compiles in one step.
  ##
  ## **Performs file I/O** and **blocks**. Equivalent to `readModel` followed by
  ## `compileModel`, but without producing a `Model` you would then close.
  ##
  ## Raises `OpenVinoArgumentError` when the path does not exist.
  if not fileExists(modelPath):
    raiseArgumentError("model file does not exist: " & modelPath)
  let coreNative = core.handle.native()
  var native: ptr ov_compiled_model_t = nil

  when defined(windows):
    if not isAscii(modelPath):
      withWidePath(modelPath, widePath):
        withRawProperties(values, rawProperties, count):
          checkStatus(ov_core_compile_model_from_file_unicode_props(
                        coreNative, widePath, device.cstring, count,
                        rawProperties, addr native),
                      "compile model from file", modelPath & " on " & device)
      return wrapCompiledModel(native)

  withRawProperties(values, rawProperties, count):
    checkStatus(ov_core_compile_model_from_file_props(
                  coreNative, modelPath.cstring, device.cstring, count,
                  rawProperties, addr native),
                "compile model from file", modelPath & " on " & device)
  result = wrapCompiledModel(native)

proc importModel*(core: Core; blob: string; device: string): CompiledModel =
  ## Imports a compiled model from a blob previously written by
  ## `CompiledModel.exportTo`.
  ##
  ## Takes the blob's bytes, not a path, so reading the file is the caller's
  ## visible decision. **Blocks**.
  ##
  ## A blob is only valid for the same device, the same runtime version and
  ## compatible hardware. OpenVINO reports a mismatch as an error; this package
  ## does not silently fall back to compiling.
  ##
  ## Raises `OpenVinoArgumentError` for an empty blob, `OpenVinoError` when the
  ## blob is not usable.
  if blob.len == 0:
    raiseArgumentError("cannot import a compiled model from an empty blob")
  var native: ptr ov_compiled_model_t = nil
  # invariant: `blob` is non-empty, checked above, so index 0 exists. The C
  # parameter is `const char*` with an explicit length, so the bytes need no
  # terminator and may contain zeros; the cast asserts nothing about content.
  # `blob` is the caller's string and outlives this call, which borrows it.
  checkStatus(ov_core_import_model(core.handle.native(),
                                 cast[cstring](unsafeAddr blob[0]),
                                 csize_t(blob.len), device.cstring,
                                 addr native),
              "import compiled model", device)
  result = wrapCompiledModel(native)

proc unsafeRawHandle*(core: Core): ptr ov_core_t =
  ## Returns the borrowed native handle for use with `openvino/raw`.
  core.handle.native()
