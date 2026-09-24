# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: properties.
##
## Source of truth: `ov_property.h` from OpenVINO `2026.4.0`, SHA-256
## `22b8d5366cf57cd6fd41c224a26368cc6d399ac9b34ee5f67d9b9c39f5a18fec`.
##
## Property keys are exported `const char*` **data** symbols, not macros and
## not functions. A Nim `const` cannot hold a value resolved at run time, so
## each key is exposed as a nullary procedure that reads the symbol. The Nim
## name still matches the C symbol exactly; only the call syntax differs, and
## that difference is unavoidable rather than a style choice.

import loader

{.push styleChecks: off.}

type ov_property_t* = object
  ## One key and value pair for the non-variadic properties entry points.
  ##
  ## `value` is `const void*` in the header, so a string value is a
  ## `const char*` reinterpreted. Both pointers are borrowed for the duration
  ## of the call: the caller must keep the key and the value alive until the
  ## call returns.
  key*: cstring
  value*: pointer

proc ov_property_key_enable_profiling*(): cstring =
  ## Key that turns per-node profiling on. The only supported way to do so.
  stringDataSymbol("ov_property_key_enable_profiling")

proc ov_property_key_available_devices*(): cstring =
  ## Key that reports the devices a plugin exposes.
  stringDataSymbol("ov_property_key_available_devices")

proc ov_property_key_device_full_name*(): cstring =
  ## Key that reports a device's full product name.
  stringDataSymbol("ov_property_key_device_full_name")

proc ov_property_key_supported_properties*(): cstring =
  ## Key that reports which properties a device accepts.
  stringDataSymbol("ov_property_key_supported_properties")

proc ov_property_key_cache_dir*(): cstring =
  ## Key that selects OpenVINO's own compiled-model cache directory.
  ##
  ## Bound as an ordinary property. Deciding whether to enable caching, where
  ## to put it and when to invalidate it is an application decision and stays
  ## out of this package.
  stringDataSymbol("ov_property_key_cache_dir")

proc ov_property_key_num_streams*(): cstring =
  ## Key that selects the number of inference streams.
  stringDataSymbol("ov_property_key_num_streams")

proc ov_property_key_inference_num_threads*(): cstring =
  ## Key that caps the number of inference threads.
  stringDataSymbol("ov_property_key_inference_num_threads")

proc ov_property_key_hint_performance_mode*(): cstring =
  ## Key that selects a performance hint.
  stringDataSymbol("ov_property_key_hint_performance_mode")

proc ov_property_key_hint_inference_precision*(): cstring =
  ## Key that hints at an inference precision.
  stringDataSymbol("ov_property_key_hint_inference_precision")

proc ov_property_key_log_level*(): cstring =
  ## Key that sets a plugin's log level.
  stringDataSymbol("ov_property_key_log_level")

{.pop.}
