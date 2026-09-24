# SPDX-License-Identifier: Apache-2.0

## Compile-time metadata for the `openvino-nim` package.
##
## This module is the single source of truth for the package version, the
## pinned OpenVINO baseline and the minimum supported Nim version. The
## Nimble manifest derives its own fields from these constants, so the
## manifest cannot drift from the library source.
##
## This module deliberately does *not* query the installed OpenVINO
## runtime. Discovering the runtime version requires loading the dynamic
## library and is provided by the managed API in a later development phase.
## Nothing declared here implies that a compatible runtime is present on
## the host, and nothing here performs I/O or native calls.

const
  PackageName* = "openvino-nim"
    ## Public distribution name: repository name, release archive prefix and
    ## the name used in documentation. The Nimble package identifier and the
    ## Nim import root are both `openvino` instead, because Nimble package
    ## identifiers may not contain a hyphen.

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
