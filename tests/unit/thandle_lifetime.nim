# SPDX-License-Identifier: Apache-2.0

## Lifetime tests for the shared handle model.
##
## These need no OpenVINO runtime. The handle takes its release function as a
## parameter, so a counting stub stands in for `ov_*_free` and the tests can
## assert exactly how many times a release happened. That is the property that
## matters: releasing twice is the bug, and a test that cannot count releases
## cannot detect it.

import std/[strutils, unittest]

import openvino/errors
import openvino/private/handles

type Probe = object
  ## Stand-in for an opaque OpenVINO object.
  marker: int

var
  releaseCount = 0
    ## How many times the stub release ran. Global because a `nimcall` release
    ## procedure cannot capture.

  lastReleased: ptr Probe = nil

proc countingRelease(native: ptr Probe) {.nimcall.} =
  inc releaseCount
  lastReleased = native

proc failingRelease(native: ptr Probe) {.nimcall.} =
  inc releaseCount
  raise newException(ValueError, "release failed")

proc freshProbe(): ptr Probe =
  ## Allocates a probe whose address stands in for a native handle.
  result = cast[ptr Probe](alloc0(sizeof(Probe)))

suite "handle creation":
  setup:
    releaseCount = 0
    lastReleased = nil

  test "a handle refuses a nil native pointer":
    expect OpenVinoArgumentError:
      discard newHandle[Probe](nil, countingRelease, "probe")

  test "a fresh handle is open and exposes its pointer":
    let native = freshProbe()
    let handle = newHandle(native, countingRelease, "probe")
    check not handle.isClosed()
    check handle.native() == native
    check handle.label() == "probe"
    handle.close()
    dealloc(native)

  test "a nil handle reports itself closed without raising":
    let handle: Handle[Probe] = nil
    check handle.isClosed()

suite "close":
  setup:
    releaseCount = 0
    lastReleased = nil

  test "close releases the native object exactly once":
    let native = freshProbe()
    let handle = newHandle(native, countingRelease, "probe")
    handle.close()
    check releaseCount == 1
    check lastReleased == native
    check handle.isClosed()
    dealloc(native)

  test "closing three times still releases only once":
    # Idempotence is the property that makes double free impossible.
    let native = freshProbe()
    let handle = newHandle(native, countingRelease, "probe")
    handle.close()
    handle.close()
    handle.close()
    check releaseCount == 1
    dealloc(native)

  test "closing a nil handle is harmless":
    let handle: Handle[Probe] = nil
    handle.close()
    check releaseCount == 0

  test "every alias shares one closed state":
    # Aliases are the supported way to share a handle, so closing through one
    # name must be visible through the others. Otherwise the second alias would
    # release an already-released pointer.
    let native = freshProbe()
    let first = newHandle(native, countingRelease, "probe")
    let second = first
    let third = second
    check not third.isClosed()
    second.close()
    check first.isClosed()
    check third.isClosed()
    third.close()
    first.close()
    check releaseCount == 1
    dealloc(native)

  test "close does not propagate a failure from the release function":
    # Neither close nor a destructor may raise. A release that fails is
    # contained rather than reported, and the required-symbol test is what
    # catches a genuinely missing release symbol.
    let native = freshProbe()
    let handle = newHandle(native, failingRelease, "probe")
    handle.close()
    check releaseCount == 1
    check handle.isClosed()
    dealloc(native)

suite "use after close":
  setup:
    releaseCount = 0

  test "reading the native pointer after close raises before reaching C":
    let native = freshProbe()
    let handle = newHandle(native, countingRelease, "probe")
    handle.close()
    expect OpenVinoArgumentError:
      discard handle.native()
    dealloc(native)

  test "the closed message names the kind of object":
    let native = freshProbe()
    let handle = newHandle(native, countingRelease, "tensor")
    handle.close()
    try:
      discard handle.native()
      check false
    except OpenVinoArgumentError as err:
      checkpoint(err.msg)
      check "tensor" in err.msg
      check "closed" in err.msg
    dealloc(native)

  test "reading the native pointer of a nil handle raises":
    let handle: Handle[Probe] = nil
    expect OpenVinoArgumentError:
      discard handle.native()

suite "destructor backstop":
  setup:
    releaseCount = 0
    lastReleased = nil

  test "a handle that leaves scope without close is still released":
    let native = freshProbe()
    block:
      let handle = newHandle(native, countingRelease, "probe")
      check not handle.isClosed()
    # ORC and ARC both release the ref once the last reference dies. The
    # collection point is not guaranteed to be the end of the block, so the
    # check is that release happened by now, not exactly when.
    GC_fullCollect()
    check releaseCount == 1
    check lastReleased == native
    dealloc(native)

  test "an explicit close means the destructor releases nothing further":
    let native = freshProbe()
    block:
      let handle = newHandle(native, countingRelease, "probe")
      handle.close()
      check releaseCount == 1
    GC_fullCollect()
    check releaseCount == 1
    dealloc(native)

  test "a handle abandoned while an exception unwinds is still released":
    let native = freshProbe()
    try:
      let handle = newHandle(native, countingRelease, "probe")
      check not handle.isClosed()
      raise newException(ValueError, "simulated mid-operation failure")
    except ValueError:
      discard
    GC_fullCollect()
    check releaseCount == 1
    dealloc(native)

suite "many handles":
  setup:
    releaseCount = 0

  test "a thousand create and close cycles release exactly a thousand times":
    # The lifetime stress requirement, run without a runtime so that it also
    # executes on a machine with no OpenVINO installed.
    const cycles = 1000
    for _ in 1 .. cycles:
      let native = freshProbe()
      let handle = newHandle(native, countingRelease, "probe")
      discard handle.native()
      handle.close()
      handle.close()
      dealloc(native)
    check releaseCount == cycles

  test "a thousand abandoned handles are all released by the collector":
    const cycles = 1000
    var natives: seq[ptr Probe] = @[]
    for _ in 1 .. cycles:
      let native = freshProbe()
      natives.add(native)
      discard newHandle(native, countingRelease, "probe")
    GC_fullCollect()
    check releaseCount == cycles
    for native in natives:
      dealloc(native)
