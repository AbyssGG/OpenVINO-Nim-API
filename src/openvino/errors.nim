# SPDX-License-Identifier: Apache-2.0

## Error types for the managed API, and the single place a status code is
## turned into an exception.
##
## Four failures are distinguished, because they have four different fixes:
##
## - `OpenVinoError`: an OpenVINO call happened and returned a non-OK status.
## - `OpenVinoLibraryError`: the library or a required symbol is missing, so
##   the call never happened. Defined in `openvino/raw/loader` and re-exported
##   here so that callers need only one import.
## - `OpenVinoVersionError`: the runtime is present but its major or minor
##   version is not the one this package was verified against.
## - `OpenVinoArgumentError`: the caller's arguments were rejected before
##   entering the C layer. Derives from `ValueError`, so existing handlers for
##   bad arguments still work.
##
## Every status check in the package goes through `checkStatus`. Building the
## message in one place is what makes the last-error handling below correct
## everywhere rather than in most places.

import std/strutils

import raw/common
import raw/error
import raw/loader

export OpenVinoLibraryError

type
  OpenVinoError* = object of CatchableError
    ## An OpenVINO C call returned a status other than `OK`.
    operation*: string
      ## What was attempted, in the words of the managed API rather than the
      ## C API.

    status*: ov_status_e
      ## The raw numeric status, kept so that a caller can branch on it
      ## without parsing the message.

    statusInfo*: string
      ## OpenVINO's own stable description of `status`, from
      ## `ov_get_error_info`.

    nativeDetail*: string
      ## The detail message OpenVINO recorded for this specific failure, from
      ## `ov_get_last_err_msg`. Empty when the runtime recorded none.

    context*: string
      ## Caller-supplied context such as a device name, an index or a file
      ## name. Never secret material.

  OpenVinoVersionError* = object of CatchableError
    ## The loaded runtime is not a version this package supports.
    detectedBuild*: string
      ## The runtime's own build number, unparsed.

    expectedVersion*: string
      ## The version this package was verified against.

  OpenVinoArgumentError* = object of ValueError
    ## An argument was rejected before any C call was made.
    ##
    ## Covers a negative or out-of-range index, an invalid shape, a capacity
    ## or element-type mismatch, and a call on an object that was already
    ## closed.

proc lastNativeDetail(): string =
  ## Copies and releases the runtime's last error message.
  ##
  ## Ordering is not incidental. The pointer is fetched first, copied into Nim
  ## memory, and released with `ov_free` in a `finally` so that a failure while
  ## converting still releases it. The prototype returned the converted string
  ## and never released anything, leaking on every failure.
  ##
  ## This must run before any other OpenVINO call, including
  ## `ov_get_error_info`: the runtime keeps one global last-error slot, so
  ## another call, or another thread's failure, can overwrite it.
  let native = ov_get_last_err_msg()
  if native == nil:
    return ""
  try:
    result = $native
  finally:
    ov_free(native)

proc formatMessage(operation: string; status: ov_status_e;
                   statusInfo, nativeDetail, context: string): string =
  ## Builds the human-readable message from the structured fields.
  result = operation & " failed with status " & $status
  if statusInfo.len > 0:
    result.add(" (" & statusInfo & ")")
  if context.len > 0:
    result.add(" [" & context & "]")
  if nativeDetail.len > 0 and nativeDetail != statusInfo:
    result.add(": " & nativeDetail.strip())

proc newOpenVinoError*(operation: string; status: ov_status_e;
                       context = ""): ref OpenVinoError =
  ## Builds an `OpenVinoError` for a failed call, capturing the runtime's
  ## detail message before anything else can overwrite it.
  ##
  ## Exposed separately from `checkStatus` so that a caller which must clean up
  ## before raising can capture the detail at the right moment and raise later.
  let detail = lastNativeDetail()
  # Only now is it safe to make another OpenVINO call. `ov_get_error_info`
  # returns a static, process-lifetime pointer and must never be released.
  let info = $ov_get_error_info(status)
  result = newException(OpenVinoError,
    formatMessage(operation, status, info, detail, context))
  result.operation = operation
  result.status = status
  result.statusInfo = info
  result.nativeDetail = detail
  result.context = context

proc checkStatus*(status: ov_status_e; operation: string; context = "") =
  ## Raises `OpenVinoError` unless `status` is `OK`.
  ##
  ## The single status-checking entry point for the whole package. Nothing else
  ## may inspect a status and build its own exception, because the last-error
  ## ordering above would then have to be repeated correctly in every caller.
  if status != OK:
    raise newOpenVinoError(operation, status, context)

proc raiseArgumentError*(message: string) {.noreturn.} =
  ## Raises `OpenVinoArgumentError`. Used for failures detected before any C
  ## call, so no status code or native detail exists.
  raise newException(OpenVinoArgumentError, message)

proc raiseClosedError*(kind: string) {.noreturn.} =
  ## Raises `OpenVinoArgumentError` for use of an object after `close`.
  ##
  ## A separate entry point because this is the single most likely lifetime
  ## mistake, and a uniform message makes it recognisable.
  raise newException(OpenVinoArgumentError,
    "this " & kind & " is closed; it cannot be used after close()")

proc newVersionError*(detectedBuild, expectedVersion,
                      reason: string): ref OpenVinoVersionError =
  ## Builds an `OpenVinoVersionError` naming both versions and why they are
  ## incompatible.
  result = newException(OpenVinoVersionError,
    "unsupported OpenVINO runtime: " & reason &
    ". Detected build '" & detectedBuild & "', expected " & expectedVersion &
    ". This package is only verified against the version it pins; see " &
    "docs/compatibility.md.")
  result.detectedBuild = detectedBuild
  result.expectedVersion = expectedVersion
