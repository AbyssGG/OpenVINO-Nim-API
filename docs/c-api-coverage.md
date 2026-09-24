# OpenVINO C API coverage

Which OpenVINO C entry points `openvino-nim` binds, and where each one comes
from. This document is the contract between the pinned headers and
`src/openvino/raw/`. A raw declaration that cannot be located in the table
below does not belong in the package.

## Pinned source of truth

| Item | Value |
|---|---|
| Upstream release | `2026.4.0` |
| Upstream Git tag | `2026.4.0` |
| Upstream release commit | `99c8149` |
| Header set | `src/bindings/c/include/openvino/c/*.h` in the tag, shipped as `runtime/include/openvino/c/*.h` in the release package |
| C API library | `openvino_c.dll` on Windows, `libopenvino_c.so` on Linux |

Reference URLs, all pinned to the tag rather than a branch:

- [Release `2026.4.0`](https://github.com/openvinotoolkit/openvino/releases/tag/2026.4.0)
- [`openvino/c/openvino.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/openvino.h)
- [`ov_common.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_common.h)
- [`ov_property.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_property.h)
- [`ov_core.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_core.h)
- [`ov_tensor.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_tensor.h)
- [`ov_infer_request.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.0/src/bindings/c/include/openvino/c/ov_infer_request.h)
- [OpenVINO 2026 C API reference](https://docs.openvino.ai/2026/api/c_cpp_api/group__ov__c__api.html)

### Header checksums

SHA-256 of the headers as installed from the `2026.4.0` release package, used
as the working reference for this document. Recorded 2026-09-24 from
`C:\Program Files (x86)\Intel\openvino_2026.4.0\runtime\include\openvino\c`.

```text
4f0848514cbd06361e8b3b933ceb810f82dade251cf546dd9f23e46a0bd3111b  deprecated.h
d5e92d0f526199c46d288c07ae82c4dc4e074f5adde1d5ce836c72a47220b1a0  openvino.h
a5dd4572f231054e3f2a8c7f77558f257f43b8bc9dbc2c1ffc2b3999dd9e50fd  ov_common.h
f49bbf08a264d06d834b3c2bd43bff826d255766e90e64092d27037bac07e218  ov_compiled_model.h
f2f8dfcd7e29cc16a9780b33b929f656fc8ad7e38248cd7ac38c154668617cb3  ov_core.h
6902eef9978a7ea551e2c562e76f66cf04611fb52225fb4863d3fbcbd5afd6ab  ov_dimension.h
094d1373417110201add3a9474d65017114fee051000a9dd842f50a67553d47c  ov_infer_request.h
812efb23a0aa81aebdbde7ade704fc8476861a7a0e2fb2efb015744b7af88282  ov_layout.h
c30d0f655c3065197fbec3a7575a65214bb75b8b51984351ff54ac0f74232ae6  ov_model.h
d3bf280719c445139680347fc411dbf3088dcd510bfc3b5faa765f0430b04ab9  ov_node.h
a242870caaef1ec9f6a50d01883fbc6d8721ead2b30e6dd4aa32ce9ce077bf7b  ov_partial_shape.h
7643323d197dd17068f01f75669d299297fc3d82891b35532ebea17fa3f518cb  ov_prepostprocess.h
22b8d5366cf57cd6fd41c224a26368cc6d399ac9b34ee5f67d9b9c39f5a18fec  ov_property.h
10ff53b49b5911b92edd96004711639003aeb577ab9a26d783e1812d1ee99267  ov_rank.h
cc3ae68e51e3161bd7f2bc443a2ba38071d22e3325e43b0084f7064aa1fe78bd  ov_remote_context.h
a12a4c241bccbc9cd3cf68f39b13c91701a78cd062a97004ae8f1612b10d4650  ov_shape.h
01c3e0de53079e6c099a078b1ca166eaf10b7fdf604124666a04e7657e6a7240  ov_tensor.h
1602a78a8a3e29c4810629d5a362177f988fe2889a2fb0da07ff7493bb068846  ov_util.h
```

The release archive URL and its own checksum are recorded when a CI job
downloads it, so that CI is not verified against a local installation.

## Conventions used below

| Column | Meaning |
|---|---|
| Header | Header that declares the item |
| Status | `bound` present in `src/openvino/raw/`; `planned` in scope for `0.1.0`, not yet written; `out of scope` not in `0.1.0` |
| Notes | Ownership, by-value structs and other ABI facts a caller must know |

Ownership of returned memory is recorded per function here and summarised in
`docs/ownership.md`.

## Types

| C type | Header | Kind | Status | Notes |
|---|---|---|---|---|
| `ov_status_e` | `ov_common.h` | enum | planned | 18 values, `OK = 0` and `-1` to `-17`. Bound as a `cint` alias plus constants, not a Nim enum, so an unknown value from the runtime stays representable |
| `ov_element_type_e` | `ov_common.h` | enum | planned | 26 values, `DYNAMIC = 0U` rising implicitly to `F8E8M0 = 25`. Same `cint` treatment |
| `ov_shape_t` | `ov_shape.h` | struct | planned | `{ int64_t rank; int64_t* dims; }`. Passed **by value** to the tensor constructors and to `ov_tensor_set_shape` |
| `ov_property_t` | `ov_property.h` | struct | planned | `{ const char* key; const void* value; }`. `value` is `const void*`, so a string value is a `const char*` reinterpreted |
| `ov_version_t` | `ov_core.h` | struct | planned | `{ const char* buildNumber; const char* description; }`. Released by `ov_version_free` |
| `ov_core_version_t` | `ov_core.h` | struct | out of scope | `{ const char* device_name; ov_version_t version; }`, used only by per-device version queries |
| `ov_core_version_list_t` | `ov_core.h` | struct | out of scope | Released by `ov_core_versions_free` |
| `ov_available_devices_t` | `ov_core.h` | struct | planned | `{ char** devices; size_t size; }`. Released by `ov_available_devices_free` |
| `ov_profiling_info_t` | `ov_infer_request.h` | struct | planned | First field is an **anonymous nested `enum Status`** with `NOT_RUN`, `OPTIMIZED_OUT`, `EXECUTED`. Its size is C `int` in practice and must be probed, not assumed |
| `ov_profiling_info_list_t` | `ov_infer_request.h` | struct | planned | Released by `ov_profiling_info_list_free` |
| `ov_callback_t` | `ov_infer_request.h` | struct | out of scope | `{ void (CALLBACK* callback_func)(void*); void* args; }`. Layout and calling convention are still probed, per plan section 8.3 |
| `ov_encryption_callbacks` | `ov_common.h` | struct | out of scope | Function pointers for cache encryption |
| `ov_core_t` | `ov_core.h` | opaque | planned | Released by `ov_core_free` |
| `ov_model_t` | `ov_model.h` | opaque | planned | Released by `ov_model_free` |
| `ov_compiled_model_t` | `ov_compiled_model.h` | opaque | planned | Released by `ov_compiled_model_free` |
| `ov_infer_request_t` | `ov_infer_request.h` | opaque | planned | Released by `ov_infer_request_free` |
| `ov_tensor_t` | `ov_tensor.h` | opaque | planned | Released by `ov_tensor_free` |
| `ov_output_port_t` | `ov_node.h` | opaque | planned | Released by `ov_output_port_free` |
| `ov_output_const_port_t` | `ov_node.h` | opaque | planned | Released by `ov_output_const_port_free`. Distinct release function from the mutable port |
| `ov_partial_shape_t` | `ov_partial_shape.h` | struct | out of scope | Needed only once dynamic shapes are supported |
| `ov_remote_context_t` | `ov_remote_context.h` | opaque | out of scope | Device-specific, excluded by plan section 3.3 |

## Base and error handling

| C function | Header | Status | Notes |
|---|---|---|---|
| `ov_get_error_info` | `ov_common.h` | planned | Returns a pointer valid for the process lifetime. **Must never be passed to `ov_free`**, stated in the header |
| `ov_get_last_err_msg` | `ov_common.h` | planned | Returns an allocated string the caller must release with `ov_free`. Copy it immediately after a failure, before any other C call |
| `ov_free` | `ov_common.h` | planned | Releases strings returned through `char**` out-parameters and by `ov_get_last_err_msg` |
| `ov_get_openvino_version` | `ov_core.h` | planned | Fills `ov_version_t`; release with `ov_version_free` after copying |
| `ov_version_free` | `ov_core.h` | planned | Releases the two strings inside `ov_version_t` |
| `ov_shutdown` | `ov_core.h` | out of scope | Process-wide teardown; interacts with Nim's exit handling and needs its own decision record |

## Core

| C function | Header | Status | Notes |
|---|---|---|---|
| `ov_core_create` | `ov_core.h` | planned | |
| `ov_core_free` | `ov_core.h` | planned | |
| `ov_core_create_with_config` | `ov_core.h` | out of scope | Takes a `plugins.xml` path; explicit plugin configuration is not in `0.1.0` |
| `ov_core_create_with_config_unicode` | `ov_core.h` | out of scope | Windows-only variant of the above |
| `ov_core_get_available_devices` | `ov_core.h` | planned | Copy every string, then release the list unconditionally on success |
| `ov_available_devices_free` | `ov_core.h` | planned | |
| `ov_core_read_model` | `ov_core.h` | planned | Narrow path |
| `ov_core_read_model_unicode` | `ov_core.h` | planned | Windows only, guarded by `OPENVINO_ENABLE_UNICODE_PATH_SUPPORT`. Required by checklist item E15 for non-ASCII paths. `wchar_t` width must be verified per platform |
| `ov_core_read_model_from_memory_buffer` | `ov_core.h` | out of scope | |
| `ov_core_compile_model_props` | `ov_core.h` | planned | Non-variadic form. One of the reasons this package requires `2026.4` |
| `ov_core_compile_model_from_file_props` | `ov_core.h` | planned | Non-variadic form |
| `ov_core_compile_model_from_file_unicode_props` | `ov_core.h` | planned | Windows only, non-ASCII model paths |
| `ov_core_set_properties` | `ov_core.h` | planned | Non-variadic form |
| `ov_core_get_property` | `ov_core.h` | planned | Returns `char**`; release with `ov_free` |
| `ov_core_import_model` | `ov_core.h` | planned | Takes the blob as `const char*` plus a size |
| `ov_core_compile_model` | `ov_core.h` | out of scope | Variadic. The managed layer must never call it; see plan section 8.6 |
| `ov_core_compile_model_from_file` | `ov_core.h` | out of scope | Variadic |
| `ov_core_compile_model_from_file_unicode` | `ov_core.h` | out of scope | Variadic |
| `ov_core_set_property` | `ov_core.h` | out of scope | Variadic |
| `ov_core_add_extension` | `ov_core.h` | out of scope | |
| `ov_core_get_versions_by_device_name` | `ov_core.h` | out of scope | |
| `ov_core_versions_free` | `ov_core.h` | out of scope | |
| `ov_core_create_context` and `_props` | `ov_core.h` | out of scope | Remote context |
| `ov_core_compile_model_with_context` and `_props` | `ov_core.h` | out of scope | Remote context |
| `ov_core_get_default_context` | `ov_core.h` | out of scope | Remote context |

## Property keys

Property keys are exported `const char*` **data** symbols, not macros and not
functions. The loader must resolve a data symbol and read the pointer, which
is a different operation from resolving a function.

| Symbol | Header | Status | Notes |
|---|---|---|---|
| `ov_property_key_enable_profiling` | `ov_property.h` | planned | The only supported way to turn profiling on. Replaces the prototype's hand-written `"PERF_COUNT"` string |
| `ov_property_key_available_devices` | `ov_property.h` | planned | |
| `ov_property_key_device_full_name` | `ov_property.h` | planned | |
| `ov_property_key_supported_properties` | `ov_property.h` | planned | |
| `ov_property_key_cache_dir` | `ov_property.h` | planned | Bound as a generic property. Deciding *when* to enable caching stays downstream, per plan section 7.2 |
| `ov_property_key_num_streams`, `ov_property_key_inference_num_threads`, `ov_property_key_hint_*`, `ov_property_key_log_level`, `ov_property_key_device_priorities`, `ov_property_key_enable_mmap`, `ov_property_key_force_tbb_terminate`, `ov_property_key_auto_batch_timeout`, `ov_property_key_model_name`, `ov_property_key_optimal_*`, `ov_property_key_max_batch_size`, `ov_property_key_range_for_*`, `ov_property_key_device_capabilities`, `ov_property_key_cache_mode` | `ov_property.h` | planned | Bound for completeness as string-valued keys |
| `ov_property_key_cache_encryption_callbacks` | `ov_property.h` | out of scope | Value is a function-pointer struct, not a string. Needs its own lifetime design |
| `ov_property_key_intel_gpu_config_file` | `ov_property.h` | out of scope | Device specific |

## Model and ports

| C function | Header | Status | Notes |
|---|---|---|---|
| `ov_model_free` | `ov_model.h` | planned | |
| `ov_model_inputs_size` | `ov_model.h` | planned | |
| `ov_model_outputs_size` | `ov_model.h` | planned | |
| `ov_model_const_input_by_index` | `ov_model.h` | planned | Yields a const port, which is what the metadata getters need |
| `ov_model_const_output_by_index` | `ov_model.h` | planned | |
| `ov_model_const_input_by_name` | `ov_model.h` | planned | |
| `ov_model_const_output_by_name` | `ov_model.h` | planned | |
| `ov_model_is_dynamic` | `ov_model.h` | planned | Returns C99 `bool`; its size must be probed |
| `ov_model_get_friendly_name` | `ov_model.h` | planned | Returns `char**`; release with `ov_free` |
| `ov_model_input*`, `ov_model_output*` mutable variants | `ov_model.h` | out of scope | The mutable port is only needed for reshaping |
| `ov_model_reshape*` | `ov_model.h` | out of scope | Dynamic shapes. Note `ov_model_reshape_input_by_name` and `ov_model_reshape_single_input` take `ov_partial_shape_t` **by value** |
| `ov_port_get_any_name` | `ov_node.h` | planned | Takes a **const** port. Returns `char**`; release with `ov_free` |
| `ov_port_get_element_type` | `ov_node.h` | planned | Takes a **const** port |
| `ov_const_port_get_shape` | `ov_node.h` | planned | Takes a const port, fills `ov_shape_t`; release with `ov_shape_free` |
| `ov_port_get_shape` | `ov_node.h` | out of scope | Mutable-port variant |
| `ov_port_get_partial_shape` | `ov_node.h` | out of scope | Dynamic shapes |
| `ov_output_const_port_free` | `ov_node.h` | planned | |
| `ov_output_port_free` | `ov_node.h` | out of scope | Only needed with mutable ports |

The const and mutable ports are separate types with separate release
functions, and the metadata getters accept only the const one. Treating them
as interchangeable is the kind of guess plan section 8.2 forbids.

## Shape and tensor

| C function | Header | Status | Notes |
|---|---|---|---|
| `ov_shape_create` | `ov_shape.h` | planned | Allocates `dims`; release with `ov_shape_free` |
| `ov_shape_free` | `ov_shape.h` | planned | Returns a status. Release only shapes OpenVINO allocated |
| `ov_tensor_create` | `ov_tensor.h` | planned | OpenVINO allocates the storage. The safe default for the managed `newTensor`, and absent from the prototype entirely |
| `ov_tensor_create_from_host_ptr` | `ov_tensor.h` | planned | Borrows caller memory. Reaches the managed layer only through an `unsafe` name |
| `ov_tensor_set_shape` | `ov_tensor.h` | planned | Takes `ov_shape_t` **by value**. The prototype passed a pointer. Covered by a dedicated regression test, checklist item C17 |
| `ov_tensor_get_shape` | `ov_tensor.h` | planned | Fills `ov_shape_t`; release with `ov_shape_free` |
| `ov_tensor_get_element_type` | `ov_tensor.h` | planned | |
| `ov_tensor_get_size` | `ov_tensor.h` | planned | Element count |
| `ov_tensor_get_byte_size` | `ov_tensor.h` | planned | |
| `ov_tensor_data` | `ov_tensor.h` | planned | Borrowed pointer into the tensor; invalid after free or reshape |
| `ov_tensor_free` | `ov_tensor.h` | planned | |
| `ov_tensor_create_from_string_array` | `ov_tensor.h` | out of scope | String tensors |
| `ov_tensor_set_string_data` | `ov_tensor.h` | out of scope | String tensors |

## Compiled model

| C function | Header | Status | Notes |
|---|---|---|---|
| `ov_compiled_model_create_infer_request` | `ov_compiled_model.h` | planned | |
| `ov_compiled_model_inputs_size` | `ov_compiled_model.h` | planned | |
| `ov_compiled_model_outputs_size` | `ov_compiled_model.h` | planned | |
| `ov_compiled_model_input_by_index` | `ov_compiled_model.h` | planned | Yields a const port |
| `ov_compiled_model_output_by_index` | `ov_compiled_model.h` | planned | Yields a const port |
| `ov_compiled_model_set_properties` | `ov_compiled_model.h` | planned | Non-variadic form |
| `ov_compiled_model_get_property` | `ov_compiled_model.h` | planned | Returns `char**`; release with `ov_free` |
| `ov_compiled_model_export_model` | `ov_compiled_model.h` | planned | Explicit export only. No implicit cache directory |
| `ov_compiled_model_free` | `ov_compiled_model.h` | planned | |
| `ov_compiled_model_set_property` | `ov_compiled_model.h` | out of scope | Variadic |
| `ov_compiled_model_get_runtime_model` | `ov_compiled_model.h` | out of scope | |
| `ov_compiled_model_get_context` | `ov_compiled_model.h` | out of scope | Remote context |
| `ov_compiled_model_input`, `_output`, `_by_name` | `ov_compiled_model.h` | out of scope | Index-based access covers `0.1.0` |

## Infer request

| C function | Header | Status | Notes |
|---|---|---|---|
| `ov_infer_request_set_input_tensor_by_index` | `ov_infer_request.h` | planned | |
| `ov_infer_request_get_output_tensor_by_index` | `ov_infer_request.h` | planned | |
| `ov_infer_request_get_input_tensor_by_index` | `ov_infer_request.h` | planned | |
| `ov_infer_request_set_tensor` | `ov_infer_request.h` | planned | By tensor name |
| `ov_infer_request_get_tensor` | `ov_infer_request.h` | planned | By tensor name |
| `ov_infer_request_infer` | `ov_infer_request.h` | planned | Blocking |
| `ov_infer_request_get_profiling_info` | `ov_infer_request.h` | planned | Release the list on success regardless of its size |
| `ov_profiling_info_list_free` | `ov_infer_request.h` | planned | |
| `ov_infer_request_free` | `ov_infer_request.h` | planned | |
| `ov_infer_request_start_async`, `_wait`, `_wait_for`, `_cancel` | `ov_infer_request.h` | out of scope | Optional for `0.1.0`, gated on lifetime and thread tests |
| `ov_infer_request_set_callback` | `ov_infer_request.h` | out of scope | No callback API in `0.1.0`; a Nim exception must never cross a C callback boundary |
| `ov_infer_request_set_tensor_by_port`, `_by_const_port`, `get_tensor_by_*` | `ov_infer_request.h` | out of scope | Index and name access cover `0.1.0` |
| `ov_infer_request_set_input_tensor`, `set_output_tensor`, `get_input_tensor`, `get_output_tensor` | `ov_infer_request.h` | out of scope | Single-port shorthands that hide which port is meant |

## Headers deliberately not bound

| Header | Reason |
|---|---|
| `ov_partial_shape.h`, `ov_dimension.h`, `ov_rank.h` | Dynamic shapes are not in `0.1.0` |
| `ov_layout.h` | Layout handling is not in `0.1.0` |
| `ov_prepostprocess.h` | Pre and post processing is out of scope, and it still contains variadic entry points |
| `ov_remote_context.h` | Device-specific memory sharing |
| `ov_util.h` | Utility surface not required by the synchronous path |
| `deprecated.h` | Deprecated by upstream |

## Variadic entry points

`2026.4` still declares variadic functions: `ov_core_compile_model`,
`ov_core_compile_model_from_file`, `ov_core_compile_model_from_file_unicode`,
`ov_core_set_property`, `ov_compiled_model_set_property`,
`ov_core_create_context` and `ov_core_compile_model_with_context`.

None of them is bound. Each has a non-variadic `_props` or `_properties`
counterpart that this package uses instead. No general variadic bridge is
kept, and `perf_count_wrapper.c` from the prototype is deleted rather than
ported.
