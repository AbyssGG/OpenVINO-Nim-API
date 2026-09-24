# SPDX-License-Identifier: Apache-2.0

## The candidate library names, and the version suffix they are built from.
##
## Needs no OpenVINO runtime: `candidateLibraries` only reports which names are
## worth trying. Checking it here rather than through a load means a wrong name
## fails on every platform's CI instead of only where a runtime is installed.
##
## This file exists because of a measured defect. The Linux candidate list held
## only `libopenvino_c.so`, and a pip installation of OpenVINO ships only
## `libopenvino_c.so.2640` with that as its SONAME and no unversioned symlink.
## The package therefore refused to load against a complete, working
## installation. These tests pin both the suffix scheme and the resulting
## names.

import std/[strutils, unittest]

import openvino/private/library
import openvino/version

suite "the shared library version suffix":
  test "the suffix is built from the pinned release":
    # Derived, not transcribed: bumping the baseline must not be able to leave
    # a stale library name behind.
    check soVersionSuffix == $(TargetOpenVinoMajor mod 100) &
      $TargetOpenVinoMinor & $TargetOpenVinoPatch

  test "the suffix for the current baseline is the one a real install uses":
    # The literal is the name observed on OpenVINO 2026.4.0 installed with pip:
    # libopenvino_c.so.2640. Asserting the derivation alone would keep passing
    # if the scheme itself were wrong, so the measured value is pinned too.
    check TargetOpenVinoVersion == "2026.4.0"
    check soVersionSuffix == "2640"

  test "the version components agree with the version string":
    let parts = TargetOpenVinoVersion.split('.')
    check parts.len == 3
    check parts[0] == $TargetOpenVinoMajor
    check parts[1] == $TargetOpenVinoMinor
    check parts[2] == $TargetOpenVinoPatch

suite "candidate library names":
  test "there is at least one candidate and none is empty":
    let candidates = candidateLibraries()
    check candidates.len >= 1
    for candidate in candidates:
      check candidate.len > 0

  test "the platform name is reported":
    check platformName.len > 0

  when defined(windows):
    test "Windows tries the single unversioned DLL name":
      # Windows DLLs carry no version in the file name in either layout.
      check candidateLibraries() == @["openvino_c.dll"]

  elif defined(macosx):
    test "macOS tries the unversioned dylib only":
      # Deliberately not extended with a versioned name: nothing on macOS has
      # been measured, and a guessed candidate would make the list look better
      # tested than it is.
      check candidateLibraries() == @["libopenvino_c.dylib"]

  else:
    test "Linux tries the unversioned name first, then the versioned one":
      # Order matters. The archive and apt layouts provide the symlink, which
      # is the name upstream documents; the pip wheel provides only the
      # versioned file. Trying the documented name first keeps the common case
      # on the path OpenVINO's own instructions describe.
      let candidates = candidateLibraries()
      check candidates.len == 2
      check candidates[0] == "libopenvino_c.so"
      check candidates[1] == "libopenvino_c.so." & soVersionSuffix

    test "the versioned candidate is the pip wheel's SONAME":
      check "libopenvino_c.so.2640" in candidateLibraries()

suite "explicit paths":
  test "a bare library name is not an explicit path":
    check not isExplicitPath("libopenvino_c.so")
    check not isExplicitPath("openvino_c.dll")

  test "anything with a separator is an explicit path":
    check isExplicitPath("/opt/intel/lib/libopenvino_c.so")
    when defined(windows):
      check isExplicitPath("C:\\openvino\\openvino_c.dll")

suite "diagnostic text":
  test "the loader hint names how this platform finds a library":
    # The hint is what a user reads when nothing loads, so it must be
    # actionable rather than merely present.
    let hint = loaderHint()
    check hint.len > 0
    when defined(windows):
      check "DLL search path" in hint
    elif not defined(macosx):
      check "LD_LIBRARY_PATH" in hint
      # The pip layout ships no unversioned name, which is the case most
      # likely to look like a missing installation.
      check "site-packages" in hint

  test "the deployment hint warns that the library alone is not enough":
    check "plugins.xml" in deploymentHint()
