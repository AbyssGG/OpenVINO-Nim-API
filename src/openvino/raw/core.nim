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
import compiled_model
import loader
import model
import property

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

proc ov_core_read_model*(core: ptr ov_core_t; model_path: cstring;
                         bin_path: cstring;
                         model: ptr ptr ov_model_t): ov_status_e
  {.openvinoImport.}
  ## Reads a model from `model_path`, with weights from `bin_path`.
  ##
  ## `bin_path` may be `nil`, in which case OpenVINO derives it. Paths are
  ## narrow strings; on Windows use `ov_core_read_model_unicode` for a path
  ## that is not representable in the active code page.

when defined(windows):
  proc ov_core_read_model_unicode*(core: ptr ov_core_t;
                                   model_path: ptr uint16;
                                   bin_path: ptr uint16;
                                   model: ptr ptr ov_model_t): ov_status_e
    {.openvinoImport.}
    ## Windows-only wide-path form of `ov_core_read_model`.
    ##
    ## Declared only on Windows, where the header guards it with
    ## `OPENVINO_ENABLE_UNICODE_PATH_SUPPORT` and `wchar_t` is 16 bits. The
    ## parameters are `ptr uint16` rather than a Nim wide-string type so that
    ## the element width is stated explicitly instead of assumed; the ABI test
    ## verifies the width rather than trusting it.

proc ov_core_compile_model_props*(core: ptr ov_core_t; model: ptr ov_model_t;
                                  device_name: cstring;
                                  num_properties: csize_t;
                                  properties: ptr ov_property_t;
                                  compiled_model:
                                    ptr ptr ov_compiled_model_t): ov_status_e
  {.openvinoImport.}
  ## Compiles `model` for `device_name`. Non-variadic form.
  ##
  ## Pass zero and `nil` for no properties. Every key and value pointer must
  ## stay alive until the call returns. This entry point existing in `2026.4`
  ## is one of the reasons this package requires that baseline.

proc ov_core_compile_model_from_file_props*(
    core: ptr ov_core_t; model_path: cstring; device_name: cstring;
    num_properties: csize_t; properties: ptr ov_property_t;
    compiled_model: ptr ptr ov_compiled_model_t): ov_status_e
  {.openvinoImport.}
  ## Reads and compiles in one step. Non-variadic form.

proc ov_core_set_properties*(core: ptr ov_core_t; device_name: cstring;
                             num_properties: csize_t;
                             properties: ptr ov_property_t): ov_status_e
  {.openvinoImport.}
  ## Applies properties to `device_name`. Non-variadic form.

proc ov_core_get_property*(core: ptr ov_core_t; device_name: cstring;
                           property_key: cstring;
                           property_value: ptr cstring): ov_status_e
  {.openvinoImport.}
  ## Reads one property of `device_name` as a string.
  ##
  ## Allocates the value, so the caller must copy it and release the original
  ## with `ov_free`.

proc ov_core_import_model*(core: ptr ov_core_t; content: cstring;
                           content_size: csize_t; device_name: cstring;
                           compiled_model:
                             ptr ptr ov_compiled_model_t): ov_status_e
  {.openvinoImport.}
  ## Imports a compiled model from a blob previously written by
  ## `ov_compiled_model_export_model`.
  ##
  ## `content` is a byte buffer, not a path, and is borrowed for the call.
  ## Deciding when to import rather than compile is an application decision
  ## and stays out of this package.

{.pop.}
