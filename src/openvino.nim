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
## At this development phase the managed surface is limited to compile-time
## package metadata. `Core`, `Model`, `Port`, `CompiledModel`,
## `InferRequest` and `Tensor` are introduced in later phases, as tracked by
## `OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md`.
##
## This package is community maintained and is not an official Intel or
## OpenVINO project.

import openvino/version

export version
