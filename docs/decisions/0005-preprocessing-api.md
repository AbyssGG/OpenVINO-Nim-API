# ADR 0005: A declarative preprocessing plan instead of PPP sub-handles

Status: accepted, 2026-10-18 (proposed earlier the same day; accepted at Gate 4
of the 0.2 plan). Evidence for M-09 and M-10 recorded below.

Applies to `Layout`, `ColorFormat`, `ResizeAlgorithm`, `PaddingMode`,
`PreprocessPlan` and `applyPreprocessing` in `0.2.0`.

## Context

The C pre/post-processing API (`ov_prepostprocess.h`) has a parent
`ov_preprocess_prepostprocessor_t` and six kinds of child object: input info,
input tensor info, preprocess steps, input model info, output info and output
tensor info. Section 2.4 of the 0.2 development plan records the following,
confirmed in Phase 0 against tag `2026.4.0` of `ov_prepostprocess.cpp` (line
numbers under Evidence):

- The parent holds a `shared_ptr` to the model, so closing the Nim `Model`
  does not leave it dangling.
- Every child stores a raw pointer into the parent, for example
  `&(preprocess->object->input(i))`. A child must not outlive its parent;
  freeing a child deletes only the wrapper.
- `build` returns a new `ov_model_t`, but C++ `PrePostProcessor::build`
  modifies the source model in place, so both refer to the same graph.
- `set_layout`, `convert_layout` and `model_info_set_layout` copy the layout,
  so an `ov_layout_t` can be freed right after the call.
- `ov_preprocess_input_tensor_info_set_color_format_with_subname` is variadic.

## Decision

1. The raw layer binds every non-variadic function in `ov_prepostprocess.h`
   and `ov_layout.h`, together with `ov_color_format_e`,
   `ov_preprocess_resize_algorithm_e` and `ov_padding_mode_e`. The variadic
   `_with_subname` is not bound; the array form `_with_subnames` is.
2. The managed layer exposes no PPP child handle. Users describe the work as a
   pure Nim value, `PreprocessPlan`, with chained builders on
   `InputPreprocess` and `OutputPostprocess`.
3. `applyPreprocessing(model, plan): Model` creates the parent, applies each
   input's tensor description, steps in call order and model layout, applies
   each output's element type, calls `build`, and in a `finally` frees every
   child and then the parent in reverse creation order. Temporary
   `ov_layout_t` values are freed right after the call that uses them. No
   child escapes the procedure.
4. Validation happens in Nim first: non-negative indices, non-empty names,
   channel counts in `1 .. int32.high`, equal-length `crop` and `pad` arrays,
   positive spatial sizes, and sub-names that are non-empty and free of NUL.
   Managed enums map to raw values through tables, never through `ord`.
5. A C failure raises `OpenVinoError` whose context locates it. A failure of
   an individual call names the input and step, for example
   `input[0].steps[3] (pskResize)` or `input[5]`. OpenVINO, however, checks
   most step semantics (a channel count that does not match, a resize without
   a known layout, an unsupported color conversion) only inside `build`;
   such a failure carries a one-line summary of the whole plan instead, for
   example `build input[0]: tensor{[N,C,H,W]} steps[mean([1.0, 2.0, 3.0,
   4.0])]`, next to OpenVINO's own explanation.
6. Documentation and the doc comment state that after `applyPreprocessing`
   the source model has been modified and shares its graph with the result
   (confirmed by M-09), so it should normally be closed.
7. The output side exposes only the element type, because that is all the C
   API offers.
8. `tensorFrom(sample)` records only the sample's element type and shape, so
   the plan stays a plain value; `applyPreprocessing` creates a temporary
   tensor of that description for `set_from` and releases it at once (safe
   by M-10). A `Layout` holds OpenVINO's canonical text and is turned back
   into an `ov_layout_t` for each call that needs one.
9. Builders return `var` and are `{.discardable.}`, so a chain such as
   `plan.input(0).tensorElementType(etU8).resize(raNearest)` needs no
   `discard`. Asking for the same input or output again continues its
   description.

## Verification at acceptance

- `tests/unit/tpreprocess_plan.nim` (no runtime) covers building, chaining,
  target reuse, value semantics, formatting and every Nim-side check.
- `tests/integration/tpreprocess.nim` checks each step numerically against a
  Nim reference on `relu_1x3x4x4_f32.xml`: element type conversion in and
  out, `tensorFrom`, layout conversion, scalar and per-channel mean and
  scale, channel reversal, BGR to RGB, nearest resize exactly and linear
  resize by range, crop, and constant and edge padding. It also checks a
  two-plane NV12 input splitting into `input/y` and `input/uv`, the
  source-model aliasing, plan reuse, and error locations.
- `examples/preprocess.nim` converts u8 BGR NHWC 2x2 images for an f32 RGB
  NCHW 4x4 model and prints the hand-computed `R=95 G=65 B=35`.
- All `nimble` gate tasks pass on Windows (`2026.4.0`) and Ubuntu 26.04
  (`2026.4.1`); `nimble memcheck` now also applies a plan: 0 errors, 0 bytes
  definitely lost.

## Evidence

Measured on 2026-10-18 on Windows x86_64, OpenVINO `2026.4.0`, CPU plugin,
with the Phase 0 probe on `tests/fixtures/relu_1x4_f32.xml`.

| ID | Question | Result |
|---|---|---|
| M-09 | Does `build` modify the source model? | Yes. After setting the input tensor element type to `u8` and building, the source model's input type changed from `f32` to `u8`, and the source and built `ov_model_t` wrap the **same** `ov::Model` object (identical stored pointer). The built model stays valid after the source `ov_model_t` is freed; compiled on CPU, `u8 [0,7,128,255]` gives `f32 [0,7,128,255]`. |
| M-10 | `set_from` and then free the tensor before `build` | `build` returns `OK`. The built input is `u8` with static shape `{1,4}` taken from the sample, and `u8 [3,0,200,9]` gives `f32 [3,0,200,9]`. |

Upstream source (tag `2026.4.0`, `ov_prepostprocess.cpp`): the parent holds a
`shared_ptr` to the model (line 44); children store `&(...)` pointers into
the parent (lines 64, 80, 96, 117, 137, 428, 445, 462, 484, 518); layouts are
copied (lines 246, 299, 537); `build` at line 551; `set_from` takes the tensor
by reference (line 286). Further facts found during the review:

- An out-of-range resize algorithm or padding mode reaches
  `std::map::at` (lines 156 and 572) and comes back as
  `UNKNOW_EXCEPTION (-17)`; an unknown color format silently becomes
  `UNDEFINED` (line 33). The managed tables make both unreachable.
- The non-variadic `ov_preprocess_input_tensor_info_set_color_format` simply
  calls the variadic function with zero names (line 336). Binding it is safe
  because Nim calls an ordinary non-variadic C function.
- `mean_multi_channels` and `scale_multi_channels` reject `value_size <= 0`
  (lines 180 and 209); `crop` and `pad` do not check their array pointers.

Layouts, measured with `ov_layout_create` and `ov_layout_to_string`: `NCHW`
becomes `[N,C,H,W]`, `nchw` is upper-cased to `[N,C,H,W]`, `NC?` becomes
`[N,C,?]`, `...C` becomes `[...,C]`, the empty string is accepted as `[...]`,
and `NCHWN` fails with `GENERAL_ERROR` ("Dimension (N) is defined multiple
times"). `initLayout` follows upstream and does not add its own grammar.

## Consequences

- Use-after-free through a child handle is impossible from managed code.
- A plan is a reusable value that can be built and unit-tested without a
  runtime; only `initLayout` needs OpenVINO.
- Advanced users who need a child object can still use `openvino/raw`.

## Rejected alternatives

**Six managed child handles.** Each would need a parent-closed check, an
explicit `close` and documentation of its borrowed lifetime, and would be
easy to misuse.

**Binding the variadic setter.** The package does not guess a platform
varargs ABI, as established in `0.1.x`.

## Related

- 0.2 development plan, sections 2.4, 2.5, 6 and 9; checklist items P-01 to
  P-08.
- [ADR 0002](0002-handle-model.md) for the handle model the returned `Model`
  uses.
