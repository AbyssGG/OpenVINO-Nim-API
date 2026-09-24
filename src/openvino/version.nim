# SPDX-License-Identifier: Apache-2.0

## Compile-time metadata for the `openvino-nim` package.
##
## This module is the single source of truth for the package version, the
## pinned OpenVINO baseline and the minimum supported Nim version. The
## Nimble manifest repeats the fields as parser-compatible literals, and
## `nimble releaseCheck` verifies that it cannot drift from these constants.
##
## This module deliberately does *not* query the installed OpenVINO
## runtime. Discovering the runtime version requires loading the dynamic
## library and is provided by `openvino/core.runtimeVersion`. Nothing declared
## here implies that a compatible runtime is present on the host, and nothing
## here performs I/O or native calls.

const
  ProjectDisplayName* = "OpenVINO-Nim-API"
    ## Human-readable project name, for titles, prose and the repository
    ## description.
    ##
    ## It is deliberately **not** the distribution name. It differs in case,
    ## and case is exactly the kind of difference that a file system, a URL or
    ## a package index will treat inconsistently across platforms. Anywhere a
    ## tool reads a name — the Nimble package, an import path, a release
    ## archive, a tag — the answer is `PackageName`, which is lowercase for
    ## that reason.
    ##
    ## Kept here rather than only in the README so that `nimble releaseCheck`
    ## can assert the README still uses it, and so that a rename has one place
    ## to happen.

  RepositoryName* = "OpenVINO-Nim-API"
    ## Exact public GitHub repository name. GitHub repository names may use
    ## mixed case and hyphens, so this intentionally matches the project
    ## display name rather than the lowercase release archive prefix.

  PackageName* = "openvino-nim"
    ## Public distribution and release archive prefix. The repository name is
    ## `RepositoryName`; the Nimble package identifier and Nim import root are
    ## both `openvino`, because Nimble identifiers may not contain a hyphen.

  PackageVersion* = "0.1.0"
    ## SemVer version of this Nim package. Versioned independently of the
    ## OpenVINO runtime: see `TargetOpenVinoVersion`.

  MinimumNimVersion* = "2.0.0"
    ## Lowest Nim version the package claims to support. The claim is only
    ## valid for combinations actually exercised by CI.

  TargetOpenVinoVersion* = "2026.4.0"
    ## Exact OpenVINO release this package is developed and verified
    ## against. Raw bindings are derived from this release's C headers.

  TargetOpenVinoMajor* = 2026
    ## Major component of `TargetOpenVinoVersion`, kept separately so that
    ## consistency can be checked mechanically.

  TargetOpenVinoMinor* = 4
    ## Minor component of `TargetOpenVinoVersion`, kept separately so that
    ## consistency can be checked mechanically.

  TargetOpenVinoPatch* = 0
    ## Patch component of `TargetOpenVinoVersion`.
    ##
    ## Needed for more than bookkeeping: upstream builds the shared-library
    ## version suffix from all three components, so `private/library.nim`
    ## derives the versioned library name from these constants rather than
    ## carrying a second copy of the number.

  TargetOpenVinoTag* = "2026.4.0"
    ## Upstream Git tag the pinned C headers are taken from.

  TargetOpenVinoCommit* = "99c8149"
    ## Upstream release commit for `TargetOpenVinoTag`, recorded so that
    ## header provenance stays auditable.
