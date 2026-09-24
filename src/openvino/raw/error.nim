# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: error description and the string release function.
##
## Source of truth: `ov_common.h` from OpenVINO `2026.4.0`, SHA-256
## `a5dd4572f231054e3f2a8c7f77558f257f43b8bc9dbc2c1ffc2b3999dd9e50fd`.
##
## The two string-returning functions here have opposite ownership rules, and
## the header says so explicitly. Getting them the wrong way round leaks on
## every failure, which is exactly what the Resonance prototype did.

import common
import loader

{.push styleChecks: off.}

proc ov_get_error_info*(status: ov_status_e): cstring {.openvinoImport.}
  ## Returns a human-readable description of `status`.
  ##
  ## The returned pointer is static and valid for the lifetime of the process.
  ## It must **never** be passed to `ov_free`. The header states this
  ## requirement directly.

proc ov_get_last_err_msg*(): cstring {.openvinoImport.}
  ## Returns the detail message of the most recent failure.
  ##
  ## The returned string is **allocated** and the caller must release it with
  ## `ov_free`. Copy it immediately after a failing call and before any further
  ## OpenVINO call, because the underlying state is global and another thread's
  ## failure can overwrite it.
  ##
  ## May return `nil`, in which case there is nothing to copy or release.

proc ov_free*(content: cstring) {.openvinoImport.}
  ## Releases a string OpenVINO allocated.
  ##
  ## Applies to the result of `ov_get_last_err_msg` and to `char**`
  ## out-parameters such as the one `ov_core_get_property` fills. Never apply
  ## it to the result of `ov_get_error_info`.

{.pop.}
