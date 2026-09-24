# SPDX-License-Identifier: Apache-2.0

## String-valued OpenVINO properties.
##
## A `Property` is a key and a string value. That covers everything `0.1.0`
## needs, including profiling and the cache directory. Properties whose value is
## a pointer, a callback struct or a device handle are deliberately absent: each
## would need its own lifetime design, and a single `pointer`-valued API would
## make every one of them look equally safe.
##
## The keys come from the runtime's own exported symbols rather than from
## hand-written strings. The prototype wrote `"PERF_COUNT"` by hand, which is
## the kind of thing that silently stops matching after an upstream rename.

import errors
import raw/property

type Property* = object
  ## One property key and its string value.
  ##
  ## Both parts are owned Nim strings, so a `Property` can be stored and passed
  ## around freely. Conversion to the borrowed form the C API wants happens only
  ## for the duration of a call; see `withRawProperties`.
  key: string
  value: string

proc initProperty*(key, value: string): Property =
  ## Builds a property from an explicit key and value.
  ##
  ## Raises `OpenVinoArgumentError` on an empty key, which OpenVINO would
  ## otherwise reject with a less specific message.
  if key.len == 0:
    raiseArgumentError("a property key cannot be empty")
  result = Property(key: key, value: value)

proc key*(property: Property): string =
  ## Returns the property key.
  property.key

proc value*(property: Property): string =
  ## Returns the property value.
  property.value

proc `$`*(property: Property): string =
  ## Returns `key=value`.
  property.key & "=" & property.value

proc enableProfiling*(enabled = true): Property =
  ## Builds the property that turns per-node profiling on or off.
  ##
  ## This is the only supported way to enable profiling. There is deliberately
  ## no `compileModelWithProfiling`: profiling is a property like any other, not
  ## a separate compilation mode.
  ##
  ## Resolves the key from the runtime, so this performs the first library load
  ## if none has happened yet and may raise `OpenVinoLibraryError`.
  initProperty($ov_property_key_enable_profiling(),
               if enabled: "YES" else: "NO")

proc cacheDirectory*(path: string): Property =
  ## Builds the property that points OpenVINO's own compiled-model cache at
  ## `path`.
  ##
  ## Offered as a property and nothing more. This package never creates the
  ## directory, never chooses a path and never enables caching on its own;
  ## deciding all of that is the application's job.
  ##
  ## May raise `OpenVinoLibraryError` while resolving the key.
  initProperty($ov_property_key_cache_dir(), path)

proc inferenceThreadCount*(threads: int): Property =
  ## Builds the property that caps the number of inference threads.
  ##
  ## Raises `OpenVinoArgumentError` for a non-positive count. May raise
  ## `OpenVinoLibraryError` while resolving the key.
  if threads <= 0:
    raiseArgumentError("inference thread count must be positive, got " &
      $threads)
  initProperty($ov_property_key_inference_num_threads(), $threads)

proc streamCount*(streams: int): Property =
  ## Builds the property that selects the number of inference streams.
  ##
  ## Raises `OpenVinoArgumentError` for a non-positive count. May raise
  ## `OpenVinoLibraryError` while resolving the key.
  if streams <= 0:
    raiseArgumentError("stream count must be positive, got " & $streams)
  initProperty($ov_property_key_num_streams(), $streams)

proc logLevel*(level: string): Property =
  ## Builds the property that sets a plugin's log level.
  ##
  ## The accepted values are the runtime's, not this package's, so the value is
  ## passed through unchanged. May raise `OpenVinoLibraryError`.
  initProperty($ov_property_key_log_level(), level)

template withRawProperties*(properties: openArray[Property];
                            rawName, countName: untyped; body: untyped) =
  ## Exposes `properties` to `body` as the borrowed form the C API expects.
  ##
  ## Inside `body`, `rawName` is a `ptr ov_property_t` and `countName` is a
  ## `csize_t`. For an empty list, `rawName` is `nil` and `countName` is zero,
  ## which is what the `_props` entry points expect for "no properties".
  ##
  ## A template rather than a procedure on purpose. The C API borrows the key
  ## and value pointers for the duration of the call, so the Nim strings they
  ## point into must stay alive and unmoved across that call. Keeping the
  ## backing storage in the caller's scope is what guarantees that; returning a
  ## built array from a procedure would let it die first.
  var keyStorage = newSeq[string](properties.len)
  var valueStorage = newSeq[string](properties.len)
  var rawStorage = newSeq[ov_property_t](properties.len)
  for index, property in properties:
    keyStorage[index] = property.key
    valueStorage[index] = property.value
  for index in 0 ..< properties.len:
    rawStorage[index] = ov_property_t(
      key: keyStorage[index].cstring,
      value: cast[pointer](valueStorage[index].cstring))
  let countName = csize_t(properties.len)
  let rawName =
    if properties.len == 0: nil
    else: addr rawStorage[0]
  block:
    body
  # Referenced after the call so that neither sequence can be considered dead
  # while the C API still holds pointers into it.
  discard keyStorage.len
  discard valueStorage.len
