# SPDX-License-Identifier: Apache-2.0

## Stable public entry point of the `openvino-nim` package.
##
## `import openvino` exposes only the managed API: types that privately own
## their native OpenVINO handles, report failures as Nim exceptions and
## document their ownership, copying and blocking behaviour.
##
## This module deliberately does *not* re-export the raw C ABI layer.
## Callers that need the header-faithful, unsafe declarations must import
## `openvino/raw` explicitly; that layer is not covered by the 0.x source
## stability promise.
##
## The managed surface includes `Core`, `Model`, `CompiledModel`,
## `InferRequest`, `Tensor`, static shapes and string-valued properties. The
## explicit raw declarations remain available through `openvino/raw`; they
## are not re-exported here. The supported synchronous surface and its
## deliberate omissions are documented in `docs/api-overview.md` and
## `docs/c-api-coverage.md`.
##
## Failures are reported as exceptions rather than status codes, and the four
## kinds are distinguished because they have four different fixes. See
## `openvino/errors`. Ownership and lifetime rules are documented in
## `docs/ownership.md`.
##
## This package is community maintained and is not an official Intel or
## OpenVINO project.

import openvino/core
import openvino/errors
import openvino/version

export core
export errors
export version
