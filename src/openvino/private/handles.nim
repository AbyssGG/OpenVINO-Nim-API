# SPDX-License-Identifier: Apache-2.0

## The one ownership model every managed OpenVINO object uses.
##
## The rules, which apply without exception across the package:
##
## - Exactly one `Handle` owns a given native pointer, and exactly one release
##   function can free it.
## - The native pointer is private. Reaching it goes through `native`, which
##   refuses once the handle is closed.
## - `close` is idempotent. The first call releases and clears; later calls do
##   nothing and are not an error.
## - Every alias shares one closed state, because `Handle` is a `ref`. Closing
##   through one name is visible through all of them, which is what makes
##   double-free impossible without forbidding aliases.
## - The destructor is a backstop, not a substitute for `close`. It never
##   raises and never allocates.
##
## The choice of a `ref` over a non-copyable value type is recorded in
## `docs/decisions/0002-handle-model.md`.
##
## This module knows nothing about OpenVINO. It takes a release function and a
## label, which makes it testable with a counting stub and no runtime
## installed.

import ../errors

type
  ReleaseProc*[T] = proc (native: ptr T) {.nimcall.}
    ## Releases one native object. Supplied by the managed type that owns it,
    ## normally a thin wrapper around the matching `ov_*_free`.

  HandleObj*[T] = object
    ## The owning state. Not used directly; see `Handle`.
    native: ptr T
    release: ReleaseProc[T]
    label: string

  Handle*[T] = ref HandleObj[T]
    ## An owning reference to one native OpenVINO object.

proc releaseNow[T](self: var HandleObj[T]) =
  ## Releases the native object if it is still held, then clears the pointer.
  ##
  ## Clearing before the call would lose the pointer if the release itself
  ## failed; clearing after, as done here, means a second entry finds `nil` and
  ## does nothing. Either order is safe because the pointer is private, and this
  ## one keeps the value available for the call.
  if self.native == nil:
    return
  let native = self.native
  let release = self.release
  self.native = nil
  if release != nil:
    # A release function resolves a symbol on first use and can therefore fail
    # when the runtime is incomplete. Neither `close` nor a destructor may
    # raise, and there is nothing a caller could do about it at this point, so
    # the failure is contained. It cannot hide a real problem: the
    # required-symbol test fails loudly if a release symbol is absent.
    try:
      release(native)
    except CatchableError:
      discard

proc `=destroy`*[T](self: var HandleObj[T]) =
  ## Backstop that releases the native object if `close` was never called.
  ##
  ## Never raises and never allocates, as required of a destructor.
  releaseNow(self)

proc `=copy`*[T](destination: var HandleObj[T]; source: HandleObj[T]) {.error.}
  ## Copying the owning state is forbidden, because two copies would each try
  ## to release the same pointer. Aliasing the `ref` is the supported way to
  ## share a handle, and it shares one closed state.

proc newHandle*[T](native: ptr T; release: ReleaseProc[T];
                   label: string): Handle[T] =
  ## Wraps `native` as the sole owner.
  ##
  ## Call this only after the creating C function reported success and left a
  ## non-nil pointer, so that a failed call never produces an owner. Rejects
  ## `nil` rather than producing a handle that looks alive but is not.
  if native == nil:
    raiseArgumentError("cannot create a " & label & " from a nil pointer")
  result = Handle[T](native: native, release: release, label: label)

proc isClosed*[T](self: Handle[T]): bool =
  ## Reports whether the handle has been closed or was never opened.
  ##
  ## Does not raise, so it is safe to ask at any time.
  self == nil or self.native == nil

proc label*[T](self: Handle[T]): string =
  ## Returns the human-readable kind name used in error messages.
  if self == nil: "handle" else: self.label

proc close*[T](self: Handle[T]) =
  ## Releases the native object. Safe to call more than once.
  ##
  ## Explicit release is preferred over waiting for the destructor, because it
  ## makes the point of release visible in the code.
  if self != nil:
    releaseNow(self[])

proc native*[T](self: Handle[T]): ptr T =
  ## Returns the borrowed native pointer for a call into the C layer.
  ##
  ## Raises `OpenVinoArgumentError` when the handle is closed, so use after
  ## close becomes a predictable Nim error instead of undefined behaviour
  ## inside OpenVINO. Every public method must obtain its pointer this way.
  ##
  ## The result is borrowed: the caller must not release it and must not retain
  ## it beyond the call.
  if self == nil:
    raiseClosedError("handle")
  if self.native == nil:
    raiseClosedError(self.label)
  result = self.native
