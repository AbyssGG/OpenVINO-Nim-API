# OpenVINO C API coverage

This document is the coverage contract between the pinned OpenVINO `2026.4.1`
(and `2026.4.0`) headers and `src/openvino/raw/`. It describes the current
repository, not an old implementation plan. Every item marked **bound** is
present in the raw layer and is exercised by the ABI or smoke checks; every
item marked **deferred** is intentionally not bound. The `0.2.0` additions
(asynchronous inference, partial shapes, reshape, layouts and preprocessing)
are bound in the raw layer; their managed API is under development.

## Pinned source of truth

| Item | Value |
|---|---|
| Upstream release | `2026.4.1` (headers byte-identical to `2026.4.0`) |
| Upstream tag and commit | `2026.4.1`, `e213a14` (`2026.4.0` commit `99c8149`) |
| Header location | `runtime/include/openvino/c/*.h` in the release package |
| Windows library | `openvino_c.dll` |
| Linux libraries | `libopenvino_c.so`, `libopenvino_c.so.2641` and `libopenvino_c.so.2640` |

The fixed upstream references are [the release](https://github.com/openvinotoolkit/openvino/releases/tag/2026.4.1),
[`ov_common.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.1/src/bindings/c/include/openvino/c/ov_common.h),
[`ov_core.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.1/src/bindings/c/include/openvino/c/ov_core.h),
[`ov_tensor.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.1/src/bindings/c/include/openvino/c/ov_tensor.h),
and [`ov_infer_request.h`](https://raw.githubusercontent.com/openvinotoolkit/openvino/2026.4.1/src/bindings/c/include/openvino/c/ov_infer_request.h).

The 18 installed header SHA-256 values are recorded in the repository history
and are checked against the pinned runtime by CI. The ABI probe also checks the
values and layout that cannot be established by a Nim declaration alone.

The recorded header digests are:

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

## Bound raw modules

| Header | Raw module | Coverage |
|---|---|---|
| `ov_common.h` | `raw/common`, `raw/error` | Status codes, element types, static error text, last-error copy and `ov_free` |
| `ov_core.h` | `raw/core` | Runtime version, Core creation, device listing, model read, non-variadic compile/property APIs and blob import |
| `ov_property.h` | `raw/property` | Exported profiling, device, cache, stream, thread, hint and log-level key symbols currently exposed by OpenVINO |
| `ov_model.h` | `raw/model` | Model lifetime, input/output counts, const ports by index/name, dynamic flag, friendly name, and reshape by names, by name, single input and port indexes |
| `ov_node.h` | `raw/node` | Const-port names, element types, static and partial shapes and const-port release |
| `ov_shape.h` | `raw/shape` | Shape allocation/release; `ov_shape_t` is passed by value where the header requires it |
| `ov_tensor.h` | `raw/tensor` | Safe OpenVINO allocation, borrowed host pointer construction, shape/type/size/data access and release |
| `ov_compiled_model.h` | `raw/compiled_model` | Request creation, I/O counts and ports, non-variadic properties, export and release |
| `ov_infer_request.h` | `raw/infer_request` | Tensor binding by index/name/const port and for the single input or output, synchronous infer, `start_async`, `wait`, `wait_for`, `cancel`, `set_callback` with `ov_callback_t`, profiling list and release |
| `ov_dimension.h`, `ov_rank.h` | `raw/dimension` | `ov_dimension_t`, `ov_rank_t` and both `_is_dynamic` predicates (bound, not used by the managed layer) |
| `ov_partial_shape.h` | `raw/partial_shape` | `ov_partial_shape_t` and all eight functions; the managed layer uses only `ov_partial_shape_free` |
| `ov_layout.h` | `raw/layout` | Layout create, format and release |
| `ov_prepostprocess.h` | `raw/prepostprocess` | All 39 non-variadic functions, the seven opaque child types and the color format, resize algorithm and padding mode enumerations |

The `0.2.0` additions were checked against the upstream C binding sources at
tag `2026.4.0` and measured on the runtime in Phase 0 of the 0.2 plan. The
evidence, including the upstream defects listed below, is recorded in
[ADR 0003](decisions/0003-async-completion.md),
[ADR 0004](decisions/0004-partial-shape-representation.md) and
[ADR 0005](decisions/0005-preprocessing-api.md).

## ABI-sensitive facts

- `ov_status_e` has `OK = 0` and `-1` through `-17`; `ov_element_type_e`
  contains all 26 values through `F8E8M0 = 25`. Nim keeps both as `cint`
  aliases so an unknown future value remains representable.
- `ov_shape_t` is passed by value to tensor constructors and
  `ov_tensor_set_shape`. Treating it as a pointer is an ABI error.
- `ov_property_t.value` is a borrowed `const void*`; property keys and values
  must remain alive for the duration of the C call.
- Strings returned through `char**` and `ov_get_last_err_msg` are copied and
  released with `ov_free`. `ov_get_error_info` returns process-lifetime static
  text and must never be passed to `ov_free`.
- Successful profiling and device-list calls are released even when their size
  is zero.
- The Windows Unicode path entry points are declared only on Windows and use
  explicit UTF-16 element widths. The managed path layer validates conversion.
- No C varargs call is bound. The managed layer uses the `_props` and
  `_properties` forms so that Nim never has to guess a platform varargs ABI.
  For preprocessing, `ov_preprocess_input_tensor_info_set_color_format_with_subname`
  is excluded and its array form `_with_subnames` is bound; `nimble lint`
  rejects any `varargs` declaration in the raw layer.
- `ov_dimension_t` is `{int64 min; int64 max}` (16 bytes) and
  `ov_partial_shape_t` is a rank followed by a dims pointer (24 bytes on
  x86_64). `ov_partial_shape_t` is passed by value to the reshape functions,
  `_to_shape`, `_is_dynamic` and `_to_string`.
- Upstream defects the managed layer avoids: `ov_partial_shape_create*`
  reject the `{0,-1}` unbounded form that ports report; the reshape functions
  turn a dynamic rank or rank 0 into `[?]`; `ov_partial_shape_to_shape` leaks
  on failure; the `_is_dynamic` predicates call zero-length dimensions and
  rank 0 dynamic.
- `ov_callback_t` is a `cdecl` function pointer then an argument pointer.
  OpenVINO keeps the pointer to the struct, so it must outlive the request.
- `ov_infer_request_wait_for` takes milliseconds and returns
  `RESULT_NOT_READY` on timeout, including on a never-started request where
  `wait` returns `OK`.
- `ov_preprocess_prepostprocessor_build` returns a model sharing, and having
  modified, the source model's graph. Child objects point into their parent and
  must be released first.

## Deliberately deferred

| Header or API family | Reason |
|---|---|
| `ov_preprocess_input_tensor_info_set_color_format_with_subname` | Variadic; the array form `_with_subnames` is bound instead |
| `ov_preprocess_input_tensor_info_set_memory_type` in the managed API | Bound raw; GPU surfaces belong to remote contexts |
| `ov_remote_context.h` | Device-specific memory ownership |
| Mutable ports, `ov_model_reshape_by_ports`, `_set_tensor_by_port`, `_get_tensor_by_port` | Need `ov_output_port_t`; name- and index-based forms cover the managed API |
| String tensors and cache-encryption callbacks | Need dedicated managed representations and lifetime rules |
| `ov_shutdown` and device-version lists | Process-wide or multi-result teardown is not needed by the supported path |

The managed API may expose fewer functions than the raw layer. That is
intentional: an unsafe declaration is not promoted to the default import root
until ownership, blocking behaviour, errors and tests are documented. See
[the API overview](api-overview.md) and [ownership](ownership.md).
