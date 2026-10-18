# Ownership and lifetimes

Who owns each piece of memory OpenVINO hands back, which function releases it,
and how long it stays valid. Every raw binding in this package is listed here;
if a function returns or fills anything, its row says what to do with it.

The model the managed layer uses is recorded in
[ADR 0002](decisions/0002-handle-model.md). The short version: one owner per
native pointer, a private pointer field, an idempotent `close()`, a destructor
as backstop, and every alias sharing one closed state.

## The three ownership kinds

| Kind | Meaning |
|---|---|
| **Owned** | The caller receives it and must release it with the named function |
| **Borrowed** | Valid only while something else lives; must never be released |
| **Static** | Valid for the process lifetime; must never be released |

Failing to release an owned allocation leaks memory. Releasing borrowed or
static memory can invalidate another owner's data or corrupt the heap. Use
the release function listed for each owned result below.

## Opaque handles

Each of these is created by a function that fills a `ptr ptr T`, and released
by exactly one function.

| Native type | Release function | Notes |
|---|---|---|
| `ov_core_t` | `ov_core_free` | Wrap only after the create call reported `OK` and left a non-nil pointer |
| `ov_model_t` | `ov_model_free` | |
| `ov_compiled_model_t` | `ov_compiled_model_free` | Same release for a compiled model and an imported one |
| `ov_infer_request_t` | `ov_infer_request_free` | Raw callers must not release a running request. The managed `close` and destructor cancel it where the device supports cancellation, wait for it, and only then release it |
| `ov_tensor_t` | `ov_tensor_free` | Releases the storage too when OpenVINO allocated it; when the tensor was built over caller memory, only the tensor is released. A request that has the tensor bound keeps its own reference, so releasing it after binding is safe |
| `ov_output_const_port_t` | `ov_output_const_port_free` | **Not** interchangeable with `ov_output_port_free` |
| `ov_output_port_t` | `ov_output_port_free` | Not produced by anything bound |
| `ov_layout_t` | `ov_layout_free` | Every function that takes one copies it, so it may be released right after the call |
| `ov_preprocess_prepostprocessor_t` | `ov_preprocess_prepostprocessor_free` | Holds a shared reference to the model it was created from, so that model may be released first |
| `ov_preprocess_input_info_t`, `_input_tensor_info_t`, `_preprocess_steps_t`, `_input_model_info_t`, `_output_info_t`, `_output_tensor_info_t` | The matching `_free` | Owned wrapper around a **borrowed** pointer into the parent. Release every child before its parent. The managed API never lets one escape `applyPreprocessing` |
| `ov_model_t` from `ov_preprocess_prepostprocessor_build` | `ov_model_free` | Shares, and has modified, the source model's graph. Either may be released first |

## Structs the caller provides and OpenVINO fills

| Native type | Filled by | Release | Notes |
|---|---|---|---|
| `ov_shape_t` | `ov_shape_create`, `ov_tensor_get_shape`, `ov_const_port_get_shape` | `ov_shape_free` | Releases the `dims` allocation. Apply only to a shape OpenVINO allocated, never to one the caller built over its own array |
| `ov_available_devices_t` | `ov_core_get_available_devices` | `ov_available_devices_free` | Copy every name first. Release on success **unconditionally**, including when `size` is zero |
| `ov_version_t` | `ov_get_openvino_version` | `ov_version_free` | Copy both strings first; they are borrowed from the struct |
| `ov_profiling_info_list_t` | `ov_infer_request_get_profiling_info` | `ov_profiling_info_list_free` | Copy the three strings of every entry first. Release on success regardless of `size` |
| `ov_partial_shape_t` | `ov_port_get_partial_shape`, `ov_partial_shape_create*`, `ov_shape_to_partial_shape` | `ov_partial_shape_free` | Releases `dims`, and is safe when `dims` is `nil` (a dynamic rank). `ov_partial_shape_create_static` allocates before it can fail, so release after a failure too. The managed layer reads only through `ov_port_get_partial_shape` and releases in a `finally` |

The managed reshape path builds `ov_partial_shape_t` itself, pointing `dims` at
a Nim array that lives for the duration of the call. OpenVINO allocates nothing
on that path, and such a struct must never reach `ov_partial_shape_free`.

The prototype released the profiling list only when `size` was non-zero. The
contract is that a successful call produces a list to release, not that a
non-empty one does.

## Strings

This is where the two easiest mistakes live, and the header states both rules
explicitly.

| Source | Kind | Release |
|---|---|---|
| `ov_get_error_info(status)` | **Static** | Never. The header says it must not be passed to `ov_free` |
| `ov_get_last_err_msg()` | **Owned** | `ov_free`. May return `nil` |
| `ov_core_get_property` out-parameter | Owned | `ov_free` |
| `ov_compiled_model_get_property` out-parameter | Owned | `ov_free` |
| `ov_model_get_friendly_name` out-parameter | Owned | `ov_free` |
| `ov_port_get_any_name` out-parameter | Owned | `ov_free` |
| `ov_partial_shape_to_string` result | Owned | `ov_free` |
| `ov_layout_to_string` result | Owned | `ov_free`. A `nil` layout still yields an allocated error text |
| `ov_version_t.buildNumber`, `.description` | Borrowed from the struct | Release the struct with `ov_version_free` |
| `ov_available_devices_t.devices[i]` | Borrowed from the list | Release the list with `ov_available_devices_free` |
| `ov_profiling_info_t.node_name`, `.exec_type`, `.node_type` | Borrowed from the list | Release the list with `ov_profiling_info_list_free` |
| A property key from `openvino/raw/property` | Borrowed from the loaded library | Never |

`src/openvino/private/conversions.nim` implements copy-then-release for each of
these so the rule is applied in one place rather than restated at every call
site. Each helper releases in a `finally`, so a failure while converting still
releases.

## The last-error ordering

Capturing a failure detail has a required order, because the runtime keeps one
global last-error slot rather than a per-thread one:

1. Call `ov_get_last_err_msg()` and keep the pointer.
2. Copy it into Nim memory.
3. Release it with `ov_free`, in a `finally`.
4. Only now call `ov_get_error_info(status)` for the stable description.
5. Build and raise the exception.

Step 4 must not come earlier. It is itself an OpenVINO call, and any OpenVINO
call may replace the last-error contents. Another thread's failure can do the
same, which is why the copy happens immediately rather than lazily.

`errors.checkStatus` is the only function in the package that does this, so the
ordering is correct everywhere by construction rather than by review.

## Borrowed views into tensor storage

`ov_tensor_data` returns a pointer into the tensor's own storage. It is
borrowed, must never be released, and becomes invalid when the tensor is freed
or its shape changes, because `ov_tensor_set_shape` may reallocate.

A tensor created with `ov_tensor_create_from_host_ptr` does not own its storage.
It borrows the caller's memory and requires that memory to stay alive, at a
stable address, with sufficient capacity, for as long as the tensor exists. The
managed layer exposes this only through a name containing `unsafe`, with those
obligations listed on the function.

## Nim memory that OpenVINO borrows

`ov_infer_request_set_callback` stores the **pointer** to its `ov_callback_t`
and calls through it on an OpenVINO thread. The managed layer therefore keeps
it in shared memory with a stable address, as recorded in
[ADR 0003](decisions/0003-async-completion.md).

| Nim allocation | Released by | Notes |
|---|---|---|
| Request box (native request, `ov_callback_t`, queue link) | `deallocShared`, after `ov_infer_request_free` and after detaching from its queue | If the request cannot be freed, the box is leaked on purpose rather than freed under a callback that might still fire |
| Completion queue (mutex, condition variable, ring) | `deallocShared`, when the queue is closed **and** every attached request has been released | Reference-counted; the trampoline only borrows it |

## Failure cleanup

- Zero-initialise every output pointer and struct before the call.
- Build an owner only after the status is `OK` **and** the output satisfies the
  contract. A failed call must never produce a live handle.
- Use `defer` or `finally` for every copy-then-release sequence, so that a
  conversion failure still releases.
- Release functions that return a status, such as `ov_shape_free`, have their
  status checked in ordinary logic and ignored on cleanup paths, where raising
  would mask the original failure. Every such `discard` carries that reason as
  a comment.

## Thread notes

- The loaded library handle is process-wide and cached. Two threads racing the
  first resolution both succeed; the platform loader reference-counts and both
  see identical symbol addresses.
- The last-error slot is global, not thread-local. A detail message read late
  can belong to another thread's failure. This is why it is copied immediately.
- No Nim code runs on an OpenVINO thread. The one C callback the package
  installs, for `CompletionQueue`, only takes an operating-system lock, records
  a pointer and signals a condition variable; users cannot install their own.

## Threads

The package adds no locking around managed handle operations. The table
distinguishes upstream thread-safety claims from behavior verified by this
project. Do not close any handle while another thread uses it.

| Type | Sharing across threads | Backing |
|---|---|---|
| `Core` | OpenVINO documents `ov::Core` as safe to share, and reading or compiling concurrently through one `Core` is the intended use | Upstream's claim. Not measured here |
| `Model` | Not claimed. One per thread is the simple answer | Not measured |
| `CompiledModel` | Creating requests from one compiled model on several threads is the shape OpenVINO is built for | Upstream's claim. Not measured here |
| `InferRequest` | **Not safe.** Bind, infer and read on one thread, or give each thread its own request. One thread may drive many requests asynchronously | Stated in the API docs. The one-request-per-thread pattern is what `createInferRequest` exists for |
| `CompletionQueue` | **Not safe** to call from several Nim threads. OpenVINO's threads write into it through the package's callback, under its own lock | Verified with ORC and ARC, valgrind and a 4 × 1000 pipeline; not under concurrent Nim callers |
| `Tensor` | **Not safe.** Mutable storage with no lock | Two `copyFrom` calls race; `setShape` may move the storage under another thread's pointer |
| `Shape`, `PartialShape`, `Dimension`, `Layout`, `PreprocessPlan`, `ElementType`, `Property` | Immutable or plain values, safe to copy | They hold owned Nim data and touch no native state |
| Exceptions | Each carries its own copied message and status | `lastErrorMessage` is read and copied before any other OpenVINO call, because the runtime keeps one global slot |

Apply these rules when managing objects across threads:

**`close()` is never concurrent with use.** The closed check refuses a call on a
closed handle, but it cannot help if another thread closes between the check and
the native call. Close an object when no other thread is using it. This is the
one case where the handle model's safety argument stops at the thread boundary.

**The global last-error slot is shared.** OpenVINO keeps one, so a failure on
another thread can overwrite it between a failed call and the attempt to read
its detail. This package reads and copies the detail immediately, in one place,
which is why `checkStatus` does the read itself rather than leaving it to a
caller.

**Profiling results are copies.** `profilingInfo()` returns Nim-owned strings
and numbers, and releases the native list before returning, so the result can
outlive the request and cross a thread boundary freely.

None of this has been measured under load. No concurrency test exists, and the
compatibility document lists multi-threaded use as untested rather than as
working.
