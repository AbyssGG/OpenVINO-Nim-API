# SPDX-License-Identifier: Apache-2.0

## Unit tests for the package metadata reachable through `import openvino`.
##
## These tests need no OpenVINO runtime and perform no native calls. They
## keep the single source of truth in `openvino/version` internally
## consistent, and they prove that the public entry point compiles while
## exporting managed symbols only.
##
## They deliberately do not assert anything about an installed runtime.
## Runtime version discovery is covered by the integration tests.

import std/[strutils, unittest]

import openvino

type VersionTriple = tuple[major, minor, patch: int]
  ## A three-part dotted numeric version, comparable lexicographically.

proc parseVersionTriple(version: string): VersionTriple =
  ## Parses a dotted numeric version such as `"2026.4.0"`.
  ##
  ## Raises `ValueError` when the input does not have exactly three
  ## non-negative integer components, so a malformed constant fails loudly
  ## instead of silently comparing as zero.
  let parts = version.split('.')
  if parts.len != 3:
    raise newException(ValueError,
      "version '" & version & "' has " & $parts.len & " components, expected 3")
  for part in parts:
    if part.len == 0 or not part.allCharsInSet(Digits):
      raise newException(ValueError,
        "version '" & version & "' has non-numeric component '" & part & "'")
  result = (parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2]))

suite "package metadata":
  test "public entry point exports the distribution name":
    check PackageName == "openvino-nim"

  test "the display name is for reading and the distribution name for tools":
    # The two differ only in case, and case is what a file system, a URL or a
    # package index will treat inconsistently. Pinned here so that a refactor
    # cannot make them the same and then use the mixed-case one where a
    # lowercase identifier is required.
    check ProjectDisplayName == "OpenVINO-Nim-API"
    check ProjectDisplayName != PackageName
    check PackageName == PackageName.toLowerAscii()
    check ProjectDisplayName != ProjectDisplayName.toLowerAscii()

  test "the display name lowercases to something close to the package name":
    # Not equal: the display name ends in -API and the distribution name does
    # not. Checked so that the relationship between them stays a deliberate
    # one rather than a coincidence nobody reviewed.
    check ProjectDisplayName.toLowerAscii() == "openvino-nim-api"
    check ProjectDisplayName.toLowerAscii().startsWith(PackageName)

  test "both names are recognisably about OpenVINO and Nim":
    # So that a reader who meets one of them can find the other.
    check "OpenVINO" in ProjectDisplayName
    check "Nim" in ProjectDisplayName
    check "openvino" in PackageName
    check "nim" in PackageName

  test "neither name contains a space":
    # A space would break a slug, a path and an archive name. The display name
    # is mixed case rather than spaced precisely so that it stays usable.
    check ' ' notin ProjectDisplayName
    check ' ' notin PackageName

  test "package version is a three-part numeric semantic version":
    checkpoint("PackageVersion=" & PackageVersion)
    let triple = parseVersionTriple(PackageVersion)
    check triple.major >= 0

  test "distribution name differs from the Nimble identifier and import root":
    # The Nimble identifier and the import root are both `openvino`, because
    # a Nimble package identifier may not contain a hyphen. A refactor that
    # accidentally unifies the two names would invalidate the install docs.
    check PackageName != "openvino"
    check PackageName.startsWith("openvino")

  test "minimum Nim version is not newer than the compiling Nim":
    checkpoint("MinimumNimVersion=" & MinimumNimVersion &
      " NimVersion=" & NimVersion)
    let
      minimum = parseVersionTriple(MinimumNimVersion)
      current = parseVersionTriple(NimVersion)
    check current >= minimum

suite "pinned OpenVINO baseline":
  test "target version decomposes into the declared major and minor":
    checkpoint("TargetOpenVinoVersion=" & TargetOpenVinoVersion &
      " major=" & $TargetOpenVinoMajor & " minor=" & $TargetOpenVinoMinor)
    let triple = parseVersionTriple(TargetOpenVinoVersion)
    check triple.major == TargetOpenVinoMajor
    check triple.minor == TargetOpenVinoMinor

  test "upstream tag matches the target version":
    # Header provenance is only auditable when the tag and the version it
    # describes refer to the same release.
    check TargetOpenVinoTag == TargetOpenVinoVersion

  test "upstream commit is recorded as a non-empty short hash":
    checkpoint("TargetOpenVinoCommit=" & TargetOpenVinoCommit)
    check TargetOpenVinoCommit.len >= 7
    check TargetOpenVinoCommit.allCharsInSet(HexDigits)

  test "baseline is the 2026.4 series the non-variadic properties API needs":
    # The package requires 2026.4 specifically because the `_props` entry
    # points exist there. Silently retargeting an older series would break
    # that guarantee without producing any compile error.
    check TargetOpenVinoMajor == 2026
    check TargetOpenVinoMinor == 4
