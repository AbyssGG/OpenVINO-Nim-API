# SPDX-License-Identifier: Apache-2.0

## Names and locations of the OpenVINO C API shared library.
##
## This is the single place in the package that knows a platform-specific
## library name. No other module may hard-code one, so retargeting a platform
## means editing this file and nothing else.
##
## The module is nearly a leaf: it imports `std/os` for path joining and
## `openvino/version` for the pinned baseline, and nothing else from this
## package. `version` is itself import-free, so there is no cycle. It is
## imported rather than duplicated because upstream derives the versioned
## library name from the release number, and a second hand-written copy of
## that number is exactly the kind of thing that stops matching. Both the raw
## layer and the managed layer may use this module.
##
## This module deliberately does *not* load anything, does not touch process
## environment variables and does not search the filesystem for an OpenVINO
## installation. It only reports which names are worth trying. Loading, and
## the diagnostics for a failed load, belong to `openvino/raw/loader`.

import std/os

import ../version

const
  openvinoLib* {.strdefine.} = ""
    ## Compile-time override for the library name or full path, set with
    ## `-d:openvinoLib=...`. Empty means "use the platform defaults".
    ##
    ## This overrides only which file is opened. It never changes an API
    ## signature, and it is not a way to select a different OpenVINO version:
    ## the package is only verified against the pinned baseline recorded in
    ## `openvino/version`.

const soVersionSuffix* =
  $(TargetOpenVinoMajor mod 100) & $TargetOpenVinoMinor & $TargetOpenVinoPatch
  ## Upstream's shared-library version suffix for the pinned release: the last
  ## two digits of the year, then the minor, then the patch. `2026.4.0` gives
  ## `2640`, which is the suffix observed on a real installation.
  ##
  ## Derived rather than written out, so bumping the baseline in
  ## `openvino/version` cannot leave a stale library name behind. The scheme
  ## is upstream's and is ambiguous for a two-digit minor; that is not
  ## something this package can fix, and no such release exists.

when defined(windows):
  const platformLibraries = ["openvino_c.dll"]
    ## Windows DLLs carry no version in the file name, in either the archive
    ## or the pip layout, so there is only one name to try.
elif defined(macosx):
  const platformLibraries = ["libopenvino_c.dylib"]
    ## Only the unversioned name. Upstream also ships
    ## `libopenvino_c.<suffix>.dylib`, but nothing on macOS has been measured
    ## by this project, and adding a name on the strength of a guess would
    ## make the candidate list look better tested than it is. See
    ## docs/compatibility.md.
else:
  const platformLibraries = [
    "libopenvino_c.so",
    "libopenvino_c.so." & soVersionSuffix]
    ## Two names, in this order, because two common Linux installations
    ## disagree about which exists.
    ##
    ## The archive and apt packages ship the versioned file plus an
    ## unversioned development symlink, so the first name resolves. The pip
    ## wheel ships only `libopenvino_c.so.<suffix>`, with that as its SONAME
    ## and no symlink, because a wheel has no reason to carry a link that only
    ## a linker would use. Measured on OpenVINO 2026.4.0 installed with pip:
    ## with only the first name, loading failed on an installation that was
    ## complete and working.

const platformName* =
  when defined(windows): "Windows"
  elif defined(macosx): "macOS"
  elif defined(linux): "Linux"
  else: "an unsupported platform"
  ## Human-readable target platform, used in load diagnostics so that a
  ## failure report states which platform's names were tried.

proc candidateLibraries*(): seq[string] =
  ## Returns the library names or paths to try, in order.
  ##
  ## When `openvinoLib` is set it is the only candidate, because an explicit
  ## override that silently falls back to a default would hide a typo. A
  ## candidate containing a path separator is used as given; a bare name is
  ## left for the platform loader to resolve against its own search path.
  if openvinoLib.len > 0:
    return @[openvinoLib]
  result = @[]
  for name in platformLibraries:
    result.add(name)

proc isExplicitPath*(candidate: string): bool =
  ## Reports whether `candidate` names a specific file rather than a bare
  ## library name that the platform loader must resolve.
  candidate.contains(DirSep) or candidate.contains(AltSep)

proc loaderHint*(): string =
  ## Returns an actionable hint for a failed load, naming how this platform
  ## finds a shared library.
  ##
  ## Kept free of machine-specific paths on purpose: a hint that quotes one
  ## developer's installation directory is misleading everywhere else.
  when defined(windows):
    "Ensure the OpenVINO runtime directory and its 3rdparty dependency " &
      "directories are on the DLL search path. Running the official " &
      "setupvars.bat does this. Pointing -d:openvinoLib at openvino_c.dll " &
      "alone is not enough, because that library loads further libraries " &
      "from other directories."
  elif defined(macosx):
    "Ensure libopenvino_c.dylib is on the dynamic loader path, for example " &
      "via DYLD_LIBRARY_PATH or the official setupvars.sh, or set " &
      "-d:openvinoLib=<full path to libopenvino_c.dylib>."
  else:
    "Ensure the OpenVINO runtime library directory is on the loader path, " &
      "for example via LD_LIBRARY_PATH, an ldconfig entry or the official " &
      "setupvars.sh. A pip installation keeps its libraries in " &
      "<site-packages>/openvino/libs and ships only the versioned name, so " &
      "that directory has to be on the path even though nothing there is " &
      "called libopenvino_c.so. As a last resort set " &
      "-d:openvinoLib=<full path to the library>."

proc deploymentHint*(): string =
  ## Returns the warning that resolving the C API library is not the same as
  ## having a usable runtime.
  ##
  ## Loading `openvino_c` succeeds as soon as that one file is found, but
  ## creating a Core still needs `plugins.xml`, the device plugins and the
  ## model frontends from the same official runtime layout. Copying a single
  ## library out of an installation produces a confusing failure much later,
  ## at model load time.
  "Note that loading the C API library alone is not a complete deployment: " &
    "Core also needs plugins.xml, the device plugins and the model " &
    "frontends from the same OpenVINO runtime directory."
