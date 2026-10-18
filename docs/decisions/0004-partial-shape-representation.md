# ADR 0004: Represent partial shapes in Nim and avoid quirky C helpers

Status: accepted, 2026-10-18 (proposed earlier the same day; accepted at Gate 2
of the 0.2 plan). Evidence for M-06 to M-08 recorded below.

Applies to `Dimension`, `PartialShape`, `Port.partialShape` and
`Model.reshape` in `0.2.0`.

## Context

`0.1.x` only reads static shapes; `Port.shape` raises on a dynamic port. The C
API models a dimension as `ov_dimension_t {int64_t min; int64_t max;}`, a
closed interval with `max == -1` meaning unbounded, and a partial shape as
`ov_partial_shape_t {ov_rank_t rank; ov_dimension_t* dims;}` where
`ov_rank_t` is the same struct.

Upstream behaviour, verified on 2026-10-18 against tag `2026.4.0` of the C
binding sources and by the Phase 0 probe (see Evidence):

- `ov_dimension_is_dynamic` and `ov_rank_is_dynamic` report `false` only when
  `min == max && max > 0` (`ov_dimension.cpp` line 9, `ov_rank.cpp` line 9).
  A static zero-length dimension and a rank-0 scalar are reported as dynamic.
- `check_dimension` rejects `max < min` (`ov_partial_shape.cpp` line 11), so
  `ov_partial_shape_create` and `ov_partial_shape_create_dynamic` **reject the
  very form a port reports for an unbounded dimension**, `{0, -1}`, and any
  lower-bounded open interval such as `{2, -1}`. Only `{-1, -1}` passes.
- `ov_partial_shape_create` rejects `rank <= 0` (line 20), and
  `ov_partial_shape_create_static` rejects any dimension `<= 0` (line 75)
  after it has already written `dims` into the output.
- `ov_partial_shape_to_shape` returns `PARAMETER_MISMATCH` (line 108) without
  freeing the `ov_shape_t` it allocated at line 101.
- A port reports dimensions through `get_min_length` and `get_max_length`
  (`ov_node.cpp` lines 60 to 74), so an unbounded dimension reads as `{0, -1}`.
- The reshape functions convert the struct with
  `partial_shape_convert_to_cpp_object` (`ov_model.cpp` lines 216 to 237). It
  passes `{min, max}` straight to `ov::Dimension` without `check_dimension`,
  and when `ov_rank_is_dynamic` is true it produces a **rank-1** shape `[?]`
  (line 225). Both a dynamic rank and rank 0 therefore turn into `[?]`
  silently.
- `ov_model_reshape*` take a `const ov_model_t*` but modify the graph in place
  (lines 255, 283, 311). `ov_model_reshape_single_input` is
  `reshape_by_port_indexes` with port 0 (line 318).

## Decision

1. `Dimension` and `PartialShape` are pure Nim value types in
   `src/openvino/partial_shape.nim`, which depends on `shape.nim` and on no
   raw module. Construction, comparison, formatting, `accepts` and `toShape`
   are therefore unit-testable without a runtime.
2. A dimension is valid when `0 <= lo` and either `hi == -1` or `lo <= hi`.
   The canonical unbounded form is `{0, -1}`; `{-1, -1}` read from C is
   normalised. Anything else raises `OpenVinoArgumentError` before C is
   called.
3. Static is decided in Nim: `lo == hi and hi >= 0`. A rank is known when
   `rank.min == rank.max and rank.max >= 0`, which includes rank 0.
4. The managed layer never calls `ov_dimension_is_dynamic`,
   `ov_rank_is_dynamic`, `ov_partial_shape_to_shape`,
   `ov_partial_shape_is_dynamic`, `ov_partial_shape_create`,
   `ov_partial_shape_create_dynamic` or `ov_partial_shape_create_static`. The
   raw layer still declares them, and their doc comments describe the quirks.
5. All conversions live in `src/openvino/private/partial_shapes.nim`.
   **Writing** fills an `ov_partial_shape_t` in Nim whose `dims` points into a
   Nim-owned array that lives for the duration of the reshape call. OpenVINO
   allocates nothing on this path, so nothing is freed with
   `ov_partial_shape_free`; the Nim-built struct must never be passed to it.
   **Reading** releases every `ov_partial_shape_t` filled by
   `ov_port_get_partial_shape` with `ov_partial_shape_free` in a `finally`.
6. `Model.reshape` has four overloads: single input, by index, by name, and a
   batch by name that issues one `ov_model_reshape` call so the change is
   atomic. Documentation states that the `Model` is modified in place and that
   an existing `CompiledModel` is unaffected.
7. `Model.reshape` rejects a shape with a dynamic rank and a rank-0 shape with
   `OpenVinoArgumentError`, naming the upstream C binding limitation, because
   the C layer would silently reshape to `[?]` (M-06, M-07). Zero-length
   dimensions are accepted; they reshape, compile and infer correctly.
8. `Port.shape` keeps its `0.1.x` behaviour; its error message now points to
   `partialShape`.
9. Constructors: `staticDim(n)`, `dynamicDim()`, `boundedDim(lo, hi)` with
   `0 <= lo <= hi`, and `atLeastDim(lo)` for an interval with no upper bound
   (`lo..`), which ports can report and the C reshape path accepts. A
   single-input `reshape(shape)` refuses a model with more than one input
   instead of silently reshaping input 0, and the batch form refuses an empty
   list, a repeated name, an empty name and a name containing NUL.

## Verification at acceptance

- `tests/unit/tpartial_shape.nim` (no runtime), `tests/integration/tdynamic_shape.nim`
  and `examples/dynamic_shape.nim` cover construction, formatting, `accepts`,
  reading, all four reshape forms, refusals, and one compiled `[?, 4]` model
  inferring batches 1, 3 and 7 with correct values.
- `nimble test`, `testLifecycle` (ORC and ARC), `testIntegration` (debug and
  release), `examples`, `testSmoke` and `testAbi` pass on Windows with
  OpenVINO `2026.4.0` and on Ubuntu 26.04 with `2026.4.1`.
- `nimble memcheck` on Linux now also runs `examples/dynamic_shape.nim`, which
  reads partial shapes and reshapes: 0 errors, 0 bytes definitely lost.

## Evidence

Measured on 2026-10-18 on Windows x86_64, OpenVINO `2026.4.0`, CPU plugin,
with the Phase 0 probe on `tests/fixtures/relu_1x4_f32.xml`. "Nim-built"
means an `ov_partial_shape_t` filled in Nim and passed by value to
`ov_model_reshape_single_input`.

| ID | Question | Result |
|---|---|---|
| M-06 | Values read back after reshape | `create_dynamic` with `{0,-1}` or `{2,-1}` and `create` with `{0,-1}` return `INVALID_C_PARAM`; `{-1,-1}` succeeds. Nim-built `[{-1,-1},4]` and `[{0,-1},4]` both read back as `[{0,-1},{4,4}]`, `to_string` `{?,4}`; `[{2,-1},4]` reads back as `{2..,4}`; `[{1,8},4]` as `{1..8,4}`. A Nim-built dynamic rank (`rank {0,-1}` or `{-1,-1}`, `dims = nil`) returns `OK` but reads back as rank 1, `{?}`. |
| M-07 | Rank 0 and zero-length dimensions | Nim-built `rank {0,0}` returns `OK` but reads back as rank 1, `{?}`: a scalar cannot be expressed through C. `[{0,0},4]` reads back as `{0,4}`, compiles on CPU, the request's input tensor has shape `[0, 4]`, and `infer` returns `OK`. |
| M-08 | Dynamic input before any tensor is bound | `[?,4]` compiled on CPU: `get_input_tensor` and `get_output_tensor` return `OK` with shape `[0, 4]` and size 0, and `infer` with nothing bound returns `OK`. Bound tensors of batch 1, 3, 7 and 2 on one request give output shapes `[b, 4]` with correct values. With `[1..8,4]`, binding batch 9 returns `GENERAL_ERROR` (incompatible shape), not `PARAMETER_MISMATCH`. The compiled model's input reads back as `{?,4}`. |

The `is_dynamic` quirk was also observed: `dim {0,0}` and `rank {0,0}` report
dynamic, `dim {4,4}` and `rank {2,2}` report static.

## Consequences

- The managed representation does not inherit the upstream misclassification
  of scalars and zero-length dimensions.
- No managed path can hit the `ov_partial_shape_to_shape` leak.
- `$` is implemented in Nim (`"?"`, `"1..8"`, `"2.."`, `"[...]"`) and does not
  depend on `ov_partial_shape_to_string`.

## Rejected alternatives

**Wrapping the C helpers directly.** It would report scalars as dynamic and
leak on a common error path.

**Building the write-side struct with `ov_partial_shape_create_dynamic`,** as
the development plan first proposed. It rejects `{0, -1}` and `{2, -1}`, so
the shape a port reports could not be written back, and lower-bounded open
intervals could not be expressed at all. Encoding unbounded as `{-1, -1}`
would work for `?` but not for `2..`.

**Exposing `ov_model_reshape_by_ports`.** It needs the mutable
`ov_output_port_t`, which stays deferred.

## Related

- 0.2 development plan, sections 2.3, 4 and 9; checklist items S-01 to S-08.
