# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: runtime version and the Core handle.
##
## Source of truth: `ov_core.h` from OpenVINO `2026.4.0`, SHA-256
## `f2f8dfcd7e29cc16a9780b33b929f656fc8ad7e38248cd7ac38c154668617cb3`.
##
## Only the entry points the `0.1.0` synchronous path needs are bound here, and
## none of the variadic ones. `docs/c-api-coverage.md` lists what is excluded
## and why.

import common
import loader

{.push styleChecks: off.}

type
  ov_core_t* = object
    ## Opaque Core handle. Released with `ov_core_free`.
    ##
    ## Declared incomplete on purpose: the layout is private to OpenVINO, so
    ## `sizeof` must not compile.

  ov_version_t* = object
    ## Runtime version: a build number and a description.
    ##
    ## Both strings belong to OpenVINO. Copy them, then release the struct with
    ## `ov_version_free`.
    buildNumber*: cstring
    description*: cstring

  ov_available_devices_t* = object
    ## The device names OpenVINO can see.
    ##
    ## Copy every string before releasing the list with
    ## `ov_available_devices_free`. Release a successful result
    ## unconditionally, including when `size` is zero.
    devices*: cstringArray
    size*: csize_t

proc ov_get_openvino_version*(version: ptr ov_version_t): ov_status_e
  {.openvinoImport.}
  ## Fills `version` with the loaded runtime's version.
  ##
  ## Pair a successful call with `ov_version_free` after copying the strings.

proc ov_version_free*(version: ptr ov_version_t) {.openvinoImport.}
  ## Releases the strings inside `version`.

proc ov_core_create*(core: ptr ptr ov_core_t): ov_status_e {.openvinoImport.}
  ## Creates a Core and stores it in `core`.
  ##
  ## Succeeding here means more than loading the C API library: OpenVINO also
  ## needs `plugins.xml`, the device plugins and the model frontends from the
  ## same runtime directory.

proc ov_core_free*(core: ptr ov_core_t) {.openvinoImport.}
  ## Releases a Core. Passing `nil` is the caller's responsibility to avoid.

proc ov_core_get_available_devices*(core: ptr ov_core_t;
                                   devices: ptr ov_available_devices_t):
    ov_status_e {.openvinoImport.}
  ## Fills `devices` with the names of the devices OpenVINO can see.

proc ov_available_devices_free*(devices: ptr ov_available_devices_t)
  {.openvinoImport.}
  ## Releases the device-name list.

{.pop.}
