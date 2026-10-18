# ADR 0003: Asynchronous inference and completion without Nim callbacks

Status: accepted, 2026-10-18 (proposed earlier the same day; accepted at Gate 3
of the 0.2 plan). Evidence for M-01 to M-05 recorded below.

Applies to `InferRequest` and the new `CompletionQueue` in `0.2.0`.

## Context

`0.1.x` exposes only the synchronous `infer`. The OpenVINO C API adds
`ov_infer_request_start_async`, `_wait`, `_wait_for`, `_cancel` and
`_set_callback`. Two upstream facts shape the design, both recorded in section
2.2 of the 0.2 development plan and confirmed in Phase 0 against tag
`2026.4.0` of `src/bindings/c/src/ov_infer_request.cpp` (line numbers under
Evidence):

- `ov_infer_request_set_callback` stores a lambda that captures the
  `const ov_callback_t*` **by pointer** and discards the
  `std::exception_ptr`. The `ov_callback_t` must therefore live at a stable
  address for as long as the request can fire it.
- The callback runs on an OpenVINO worker thread that Nim did not create.
  Nim code running there could allocate from a heap the thread does not own,
  raise an exception through C++ frames, or touch a `ref` that ORC or ARC is
  releasing on another thread.

`ov_infer_request_wait_for` takes milliseconds as `int64_t` and returns
`RESULT_NOT_READY (-9)` on timeout. Errors from the asynchronous run surface
only as the status of `wait` or `wait_for`.

## Decision

1. **No user code runs on OpenVINO threads.** The only function ever passed to
   `ov_infer_request_set_callback` is one package-internal trampoline marked
   `{.cdecl, raises: [], gcsafe.}`. It performs an atomic store, takes a
   `Lock`, writes an integer into a fixed-capacity ring buffer, signals a
   `Cond` and unlocks. It never allocates, never raises and never touches a
   Nim `ref`, `string` or `seq`. Users cannot register arbitrary closures.
2. **Errors come only from `wait` and `waitFor`.** A completion notification
   means "ready to collect"; the caller then calls `wait`, which returns at
   once and raises if the run failed.
3. **Blocking primitives first.** `startAsync`, `wait`,
   `waitFor(timeout: Duration): bool` and `cancel` work without any callback.
   `waitFor` maps `RESULT_NOT_READY` to `false` and never raises for a
   timeout. The managed layer tracks whether the request was ever started,
   because upstream `wait` and `wait_for` disagree on that case (M-03). `REQUEST_BUSY (-8)` maps to the new `OpenVinoBusyError` and
   `INFER_CANCELLED (-13)` to `OpenVinoCancelledError`, both subtypes of
   `OpenVinoError`, so `0.1.x` handlers keep working.
4. **A `RequestBox` owns the request.** `InferRequest` keeps its
   `Handle[T]` from [ADR 0002](0002-handle-model.md), but `T` becomes an
   internal `RequestBox` allocated with `allocShared0`. It holds the native
   pointer, the `ov_callback_t`, the completion slot and a `started` flag.
   `Handle[T]` itself does not change.
5. **One release order**, shared by `close` and the destructor backstop, none
   of which raises:
   1. if started and not known to be complete, `ov_infer_request_cancel` and
      then `ov_infer_request_wait`, ignoring both statuses;
   2. `ov_infer_request_free`;
   3. detach from the owning `CompletionQueue` with an atomic decrement;
   4. `deallocShared` the box.

   The `ov_callback_t` is freed only after the request, which satisfies the
   by-pointer capture. The order does not rely on whether
   `ov_infer_request_free` waits for a running inference (M-04).
6. **Bound tensors are not kept alive on the Nim side** (revised at Gate 3).
   The plan proposed storing the most recently bound `Tensor` in the request.
   Upstream makes that unnecessary: `ov::InferRequest::set_tensor` stores its
   own shared reference to the tensor implementation, so releasing the Nim
   `Tensor` (and its `ov_tensor_t` wrapper) during a run leaves the binding
   intact. `tasync_inference.nim` binds a tensor, closes it, runs
   asynchronously and checks the output. Host memory behind
   `unsafeTensorFromPointer` remains the caller's responsibility either way,
   which a Nim-side reference could not have changed.
7. **`CompletionQueue`** is shared memory (an OS mutex and condition variable,
   a ring of request-box pointers and a reference count) allocated with
   `allocShared0`, owned through a `Handle` like every other managed object.
   `attach` installs the trampoline and fails with `OpenVinoBusyError` while
   the request is running; a request belongs to at most one queue, for its
   whole life. Each box carries a `queued` flag, protected by the queue lock,
   so a request occupies at most one ring entry however often it completes
   before `next` is called; the ring therefore cannot overflow, and attaching
   beyond capacity raises `OpenVinoArgumentError`. Releasing a request removes
   its entry. The memory is released when the queue is closed and every
   attached request has been released, in either order. `next` waits on the
   condition variable with a monotonic deadline, in chunks of at most an hour.
8. **The trampoline calls the operating system directly.** `private/trampoline`
   uses `EnterCriticalSection`/`WakeConditionVariable` on Windows and
   `pthread_mutex_*`/`pthread_cond_*` elsewhere, with stack traces, line
   traces and runtime checks off, so no Nim runtime code runs on the OpenVINO
   thread. `nimble lint` rejects allocation, strings, `echo`, `try:` and
   `raise` in that module.

## Verification at acceptance

- `tests/integration/tasync_inference.nim`: start and wait, `waitFor` timeout
  and completion, never-started requests, negative timeouts, a closed bound
  tensor, `OpenVinoBusyError` on start, infer, bind and read during a run,
  `OpenVinoCancelledError` and reuse after cancel, queue ids, cancelled runs
  reported, synchronous runs not, merged double completion, attach refusals,
  and four requests pipelined through one queue for 1000 rounds with every
  output checked.
- `tests/lifecycle/tasync_lifetime.nim`: closing a running request, the
  destructor releasing a running attached request, a pending completion
  removed on close, and the queue and its requests closed in either order.
- Both pass under ORC and ARC, debug and release, on Windows (OpenVINO
  `2026.4.0`) and Ubuntu 26.04 (`2026.4.1`). The `0.1` tests pass unchanged.
- `nimble memcheck` on Linux now also runs `examples/async_infer.nim`: 0
  errors, 0 bytes definitely lost.
- ThreadSanitizer could not be used: OpenVINO loads `libtbbbind` with
  `RTLD_DEEPBIND`, which the sanitizer runtime refuses, the same class of
  limitation that rules out AddressSanitizer in `nimble memcheck`.
- The optional `asyncdispatch` adapter is not part of `0.2.0`; no evidence
  that `AsyncEvent.trigger` is safe from a foreign thread was produced.

## Hardware evidence (Phase 5)

`nimble testHardware` on the Windows host (OpenVINO `2026.4.0`) ran 100
completions through a `CompletionQueue` on `GPU`, `GPU.0`, `GPU.1` and `NPU`
with every output correct. The Intel NPU plugin does **not** support
cancellation: `ov_infer_request_cancel` returns `GENERAL_ERROR` ("Inference
cancellation is not supported by the Intel NPU plugin"), so the managed
`cancel` raises `OpenVinoError` there. The release order is unaffected because
it ignores the cancel status and then waits; closing a running NPU request was
tested and is safe. This is why decision 5 never depends on cancellation
succeeding.

## Evidence

Measured on 2026-10-18 on Windows x86_64, OpenVINO `2026.4.0`, CPU plugin,
with a Phase 0 probe that declares the new symbols locally through
`openvinoImport` and uses `tests/fixtures/relu_1x4_f32.xml`. A "busy" request
is the fixture reshaped to `[1, 32000000]`, whose synchronous inference takes
about 36 to 40 ms. The probe becomes the M-series regression in
`tests/abi/tsmoke_runtime.nim` in Phase 1.

| ID | Question | Result |
|---|---|---|
| M-01 | Status of calls on a busy request | `start_async`, `infer`, `set_input_tensor_by_index` **and** `get_output_tensor_by_index` all return `REQUEST_BUSY (-8)` with message "Infer Request is busy", in 3 of 3 rounds. `wait_for(0)` before and after them returned `RESULT_NOT_READY`, proving the run was still in flight. |
| M-02 | `wait` after `cancel`; `cancel` on a finished request | `cancel` returns `OK`; the following `wait` returns `INFER_CANCELLED (-13)` in 10 of 10 runs, and a second `wait` returns `-13` again. The request is reusable afterwards. `cancel` on a completed, idle or never-started request returns `OK` and a later `wait` returns `OK`. |
| M-03 | `wait` and `wait_for` on a never-started request | `wait` returns `OK` at once. `wait_for(0)` and `wait_for(10)` return `RESULT_NOT_READY` (the latter after the full timeout). `wait_for(-1)` returns `GENERAL_ERROR` ("Timeout can't be less than 0"). |
| M-04 | `ov_infer_request_free` during a run (isolated process) | Blocks for about 15 ms, never invokes the callback, process survives; 3 of 3 runs. Background only; the managed release order does not rely on it. |
| M-05 | Has the callback finished before `wait` returns? | Yes in 2000 of 2000 rounds, and before `wait_for(0)` first reports `OK` in 2000 of 2000 rounds. The callback runs for a cancelled run (once, before `wait` returns `-13`). A synchronous `infer` does **not** invoke it. |

Upstream source (tag `2026.4.0`): `ov_infer_request.cpp` lines 296 and 300
(`wait_for` in milliseconds, `RESULT_NOT_READY` on timeout), lines 309 to 310
(callback captured by pointer, exception discarded); `common.h` lines 26 to 27
(`ov::Busy` to `REQUEST_BUSY`, `ov::Cancelled` to `INFER_CANCELLED`).

Consequences for the design:

- `OpenVinoBusyError` applies to every call on a running request, including
  reading tensors, not just to starting it. `inputTensor` and `outputTensor`
  document this.
- Because `wait_for` on a never-started request reports `RESULT_NOT_READY`
  while `wait` reports `OK`, the managed layer tracks `started` itself.
  `waitFor` on a request that was never started returns `true` without calling
  C, matching `wait`. A negative timeout is rejected with
  `OpenVinoArgumentError` before C is called.
- The cancelled status is sticky until the next start, so `wait` keeps raising
  `OpenVinoCancelledError` until the request is started again.
- A `CompletionQueue` receives a completion for asynchronous runs, including
  cancelled ones, but not for synchronous `infer`. This is documented on
  `attach`.
- Because the callback has finished before `wait` returns, the release order
  (cancel, wait, free, detach, deallocate) cannot free the slot while the
  trampoline is still using it.

## Consequences

- One Nim thread can drive many requests. Sharing one `InferRequest` across
  Nim threads is still not supported in `0.2.0`.
- Tests run under `--mm:orc --threads:on` and `--mm:arc --threads:on`, and the
  asynchronous tests join the valgrind memcheck run on Linux.
- `nimble lint` gains a text rule for the trampoline module: no `new`, `&`,
  `$`, `echo`, or `seq` and `string` construction.
- Closing a running request is now defined behaviour (cancel, wait, free)
  instead of the `0.1.x` "do not do this".

## Rejected alternatives

**Letting users register Nim closures as callbacks.** It would run user code
on a foreign thread, where any allocation or exception is undefined
behaviour. No amount of documentation makes that safe.

**Storing `ov_callback_t` in the Nim object or on the stack.** Both move or
disappear while OpenVINO still holds the pointer.

**Depending on `ov_infer_request_free` to wait.** It is C++ implementation
behaviour, not part of the C header contract.

**`asyncdispatch` integration in the core.** Kept optional until it is shown
that `AsyncEvent.trigger` is safe to call from a non-Nim thread on both IOCP
and epoll. It will be an appendix to this ADR if it lands.

## Related

- 0.2 development plan, sections 2.2, 5 and 9; checklist items A-01 to A-10.
- [ADR 0002](0002-handle-model.md), whose handle model this extends.
