# Architecture

How `openvino-nim` is put together, and why the seams are where they are.

## Two layers, one direction

```text
your code
   |
   v
import openvino                 managed layer   src/openvino/*.nim
   |                            Nim types, exceptions, owned handles
   v
src/openvino/private/*.nim      internal        handles, conversions, paths
   |
   v
import openvino/raw             raw layer       src/openvino/raw/*.nim
   |                            one declaration per C prototype
   v
openvino_c.dll / libopenvino_c.so
```

Every arrow points one way. The managed layer imports the raw layer; the raw
layer knows nothing about the managed layer and imports nothing from it. That is
not a style preference: it is what makes the raw layer usable on its own by a
caller who needs an entry point the managed layer does not wrap, without
dragging in ownership machinery they did not ask for.

`src/openvino.nim` re-exports the managed layer and deliberately does **not**
re-export `raw`. `nimble lint` fails if it ever does. Otherwise `import openvino`
would put sixty `ov_*` symbols into every user's namespace, and the two layers
would stop being a choice.

## What each layer promises

| | Raw layer | Managed layer |
|---|---|---|
| Import | `import openvino/raw` | `import openvino` |
| Names | Upstream `ov_*`, unchanged | Nim conventions |
| Errors | Returns `ov_status_e`; raises nothing, except the loader | Raises `OpenVinoError` and friends |
| Memory | Yours to release, exactly as the C docs say | Owned handles with idempotent `close()` |
| Stability | Follows the C headers; changes when they do | Follows semantic versioning |
| Style checking | `--styleCheck:usages` | `--styleCheck:error` |

The raw layer keeps upstream spelling so that a C prototype and its Nim
declaration can be compared by eye. That is also why it is exempt from
`--styleCheck:error`: `ov_core_read_model` is not a Nim-style name and must not
become one.

The one documented exception to "the raw layer raises nothing" is the loader. A
call that never happened has no `ov_status_e` to return, and reusing
`GENERAL_ERROR` would merge "OpenVINO is not installed" with "you passed bad
arguments". See `docs/decisions/0001-symbol-loading.md`.

## How symbols are found

There is no `{.dynlib.}` pragma anywhere. `src/openvino/private/library.nim`
loads the library with `loadLib` on first use and resolves each symbol with
`symAddr`.

This was measured, not guessed. With `{.dynlib.}`, both the constant and the
variable form load the library during module initialisation and call `quit(1)`
when it is absent, before a single line of user code runs. That makes
`OpenVinoLibraryError` unreachable and a diagnostic message impossible. The
variable form additionally printed an empty library name. Decision record:
`docs/decisions/0001-symbol-loading.md`.

The `{.openvinoImport.}` macro pragma turns each declaration into a lazily
resolved function pointer. The imported C name is the Nim proc name, so the two
cannot disagree - which is the failure mode of a hand-written binding table.

## How handles are owned

Every managed type wraps `Handle[T]`, a shared `ref` holding the native pointer,
a release function and a closed flag. Copying a `Core` or a `Tensor` shares the
handle rather than duplicating ownership, so a double free is not expressible.
`close()` is idempotent; a destructor is a backstop for an abandoned handle, not
a substitute for closing. Decision record:
`docs/decisions/0002-handle-model.md`; the per-function ownership table is
`docs/ownership.md`.

## Where the boundary conversions live

`src/openvino/private/` holds the three jobs that would otherwise be repeated at
every call site:

| Module | Job |
|---|---|
| `library.nim` | Loading the library and resolving symbols, once, with a diagnostic that names what was tried |
| `handles.nim` | The ownership model: one owner, idempotent close, use-after-close refused before the C call |
| `conversions.nim` | Copy-then-release for every native string, list and struct the C API allocates |
| `paths.nim` | UTF-8 to UTF-16 for the Windows wide-character entry points |

`private` is not part of the public API. It is imported by the managed layer and
by tests that need to assert something about a boundary rule.

## What is deliberately absent

Absences are decisions too, and each of these was asked for at some point:

- **No global default `Core`.** A hidden one makes lifetime and configuration
  invisible, and two libraries in one process would fight over it.
- **No device fallback.** `compileModel` needs a device name. Falling back to
  CPU after a GPU failure turns a deployment error into a silent slowdown.
- **No implicit cache.** `cacheDirectory()` exists as a property. The package
  never creates a directory or enables caching on its own.
- **No `compileOrImportModel`.** Choosing between compiling and importing a blob
  needs application knowledge about staleness and hardware identity.
- **No async or batching in `0.1.0`.** The synchronous path is what is tested.
- **No `pointer`-valued property API.** It would make every pointer-valued
  property look equally safe, and they are not.

## What enforces all of this

| Check | Task | What it would catch |
|---|---|---|
| Layer direction | `nimble lint` | `src/openvino.nim` re-exporting `raw` |
| Naming per layer | `nimble lint` | A managed name in upstream style, or the reverse |
| Declarations against headers | `nimble testAbi` | A struct field order, enum value or type width that drifted from the C headers |
| Real symbol resolution | `nimble testSmoke` | A symbol that does not exist in the installed runtime |
| Ownership under ORC and ARC | `nimble testLifecycle` | A destructor that fires at a different time and frees twice |
| End-to-end behaviour | `nimble testIntegration` | Inference that returns the wrong numbers |
| Documentation and fixtures | `nimble lint` | A README example that no longer compiles; a fixture checksum that was never computed |
