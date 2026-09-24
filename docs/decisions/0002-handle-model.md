# ADR 0002: Own native handles through a shared `ref`, not a value type

Status: accepted, 2026-09-24.

Applies to every managed type that owns an OpenVINO object: `Core`, `Model`,
`Port`, `CompiledModel`, `InferRequest` and `Tensor`.

## Context

Each managed object owns exactly one native pointer that exactly one `ov_*_free`
can release. The development plan requires, in section 10.1, that every alias
share one closed state **or** that the type be strictly non-copyable with a
correct move implementation, and that the package pick one model and use it
everywhere.

Nim offers two shapes.

A non-copyable value type with `=destroy`, `=copy {.error.}` and `=sink` gives
deterministic release at end of scope and no reference counting. It also makes
ordinary use awkward: the object cannot be stored in a `seq` alongside others
without moves, cannot be captured, and cannot be handed to two places that both
want to read from it. Every such case becomes a compile error the caller has to
work around.

A `ref object` with `=destroy` releases when the last reference dies. Aliases
are free and, importantly, they share one state.

## Decision

Handles are `ref` objects. `src/openvino/private/handles.nim` implements the
model once, generically, and every managed type uses it rather than repeating
a destructor.

The native pointer is private. `native()` is the only way to reach it and it
raises `OpenVinoArgumentError` when the handle is closed. `close()` releases
and clears, and is idempotent. `=copy` on the underlying object is an error, so
the owning state cannot be duplicated; aliasing the `ref` is the supported way
to share.

## Why aliases sharing state is the safer half of the requirement

The two options are not equally safe in the same way.

With a value type, the danger is that a copy slips through and two owners each
release the same pointer. The compiler catches most of these, but every
workaround a caller writes is a chance to hold a pointer past its release.

With a shared `ref`, double release is impossible by construction: there is one
pointer field, `close` clears it, and every alias reads the same field. The
remaining risk is the opposite one, that release happens later than the reader
expected. That is a performance and resource-pressure question rather than a
memory-safety one, and it is why `close()` exists and is documented as
preferred over waiting for the destructor.

Trading a memory-safety risk for a resource-timing risk is the right direction
for a binding whose failures would otherwise be native crashes.

## Consequences

- Release timing is not lexical. A handle kept alive by another reference is
  released later than its enclosing scope. Callers who need release at a known
  point call `close()`, which the API documentation states.
- The model is verified under both ORC and ARC by `nimble testLifecycle`,
  because a destructor firing at a different moment is exactly the difference
  that turns into a double free. `refc` is not claimed until measured.
- `close()` and `=destroy` never raise. A release function resolves its symbol
  on first use and can therefore fail on an incomplete runtime; that failure is
  contained rather than reported, because a destructor may not raise and there
  is nothing a caller could do at that point. It cannot hide a real problem:
  the required-symbol check in the smoke test fails loudly when a release
  symbol is absent.
- `handles.nim` takes its release function as a parameter and knows nothing
  about OpenVINO, so the lifetime tests run with a counting stub and no runtime
  installed. Counting releases is what makes "released exactly once" testable
  at all.

## Rejected alternatives

**A finalizer via `new(x, finalizer)`.** Superseded by `=destroy` under ARC and
ORC, and it does not compose with the generic handle.

**Reference counting the native pointer ourselves.** The `ref` already does
this correctly. A second scheme would be a second thing to get wrong.

**No destructor, `close()` only.** Rejected because an abandoned handle would
leak silently, and the plan requires a backstop.

## Related

- Development plan sections 10.1 to 10.4, checklist items D05 to D14.
- [ADR 0001](0001-symbol-loading.md) for how the release symbols are resolved.
