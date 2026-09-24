# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Two kinds of change are tracked separately, because the Nim package version
and the OpenVINO runtime baseline evolve independently:

- **Nim API** changes to this package's own public surface.
- **OpenVINO compatibility** changes to the pinned runtime and header
  baseline.

## Unreleased

- Added an English-first README with a Chinese companion, quick-start path,
  feature matrix, project layout and support links.
- Added the documentation hub, getting-started guide, API overview, roadmap,
  examples guide and tests guide.
- Added generated API pages for every public managed module and the explicit
  raw entry point, with a merged symbol index under `build/docs`.
- Added `SECURITY.md`, `SUPPORT.md`, `CODE_OF_CONDUCT.md`, issue forms and a
  pull-request template.
- Corrected stale implementation, CI and C API coverage documentation so it
  describes the current repository rather than the original audit snapshot.
- Hardened the release archive date input: impossible and non-leap-year dates
  are rejected before an archive name can be generated.

## 0.1.0

Not released. Under development.

### Nim API

- Added the `openvino` Nimble package with `import openvino` as its stable
  entry point. The entry point exports managed API only and never re-exports
  the raw C ABI layer.
- Added `openvino/version` as the single source of truth for the package
  version, the minimum supported Nim version and the pinned OpenVINO
  baseline. The Nimble manifest repeats parser-compatible literals and
  `nimble releaseCheck` verifies that they cannot drift from this module.
- Added the error hierarchy: `OpenVinoError` carrying the operation name, the
  numeric status, the stable status description and the native detail captured
  at the moment of failure, plus `OpenVinoLibraryError`,
  `OpenVinoVersionError` and `OpenVinoArgumentError`. Argument mistakes are
  refused in Nim before entering the C layer.
- Added the handle model. Every managed type owns exactly one native handle
  behind a shared `ref`, offers an idempotent `close()`, refuses use after
  close with a message naming the type, and keeps a destructor as a backstop
  for an abandoned handle rather than as the normal release path.
- Added `Core` with device discovery, `readModel`, `compileModel` from a
  `Model` or from a path, `importModel` from a blob, and per-device
  properties. No default device, no fallback after a failure, no implicit
  cache and no directory creation.
- Added `Model` and `Port` with input and output counts, names, element types,
  shapes and a dynamic-shape query. Port indices are range-checked before
  conversion to `csize_t`.
- Added `CompiledModel` with properties, `createInferRequest` and `exportTo`
  for an explicit blob. Export and import are separate operations; there is no
  entry point that decides between compiling and importing for you.
- Added `InferRequest` with positional and by-name input binding, output
  tensors, a synchronous `infer`, and `profilingInfo` returning Nim-owned
  copies.
- Added `Shape` and `ElementType`. A shape is validated when built, so a
  negative dimension or an element count that would overflow `int64` is
  rejected once rather than at some later call. `ElementType` is a real Nim
  enum, and a value an installed runtime reports that this build does not know
  is refused at the boundary instead of stored as an illegal enumerator.
- Added `Tensor` with three constructors separated by ownership:
  `newTensor` for OpenVINO-allocated storage, `tensorFrom` for a checked copy
  of Nim data, and `unsafeTensorFromPointer` for a caller-owned buffer. Typed
  access checks element width and refuses sub-byte types rather than rounding
  a byte size.
- Added `Property` with `enableProfiling`, `cacheDirectory`,
  `inferenceThreadCount`, `streamCount` and `logLevel`. Keys are resolved from
  the runtime's own exported symbols rather than written as string literals.
- **Fixed** the Linux library search, which could not find a pip-installed
  OpenVINO. The only Linux candidate name was `libopenvino_c.so`; a pip wheel
  ships `libopenvino_c.so.2640` as its SONAME with no unversioned symlink, so
  the package raised `OpenVinoLibraryError` against a complete, working
  installation. Two candidates are now tried, unversioned first, and the
  versioned suffix is derived from `TargetOpenVinoMajor`, `TargetOpenVinoMinor`
  and the new `TargetOpenVinoPatch` so it cannot go stale. `nimble releaseCheck`
  asserts all three components against `TargetOpenVinoVersion`.
- The Linux loader hint now says that a pip installation keeps its libraries in
  `<site-packages>/openvino/libs` and ships no unversioned name, which is the
  case most likely to look like a missing installation.
- `openvino/core` imports `private/paths` only under `when defined(windows)`.
  Everything it needs from that module is Windows-only, so the unconditional
  import made every Linux and macOS build report an unused import.
- Non-ASCII model paths on Windows go through OpenVINO's wide-character entry
  points, so the result cannot depend on the process's active code page.
  Measured: `2026.4` also accepts UTF-8 through the narrow entry point on a
  host with code page 936, so this is insurance against an undocumented
  behaviour rather than a fix for a reproduced failure.

### OpenVINO compatibility

- Established `2026.4.0` as the first verified baseline, pinned to upstream
  tag `2026.4.0` and release commit `99c8149`.
- Declared no compatibility with `2026.3`, `2027.x` or any patch release
  that has not been verified end to end.

### Project

- Added the Apache-2.0 `LICENSE` file. Previously the license was declared
  only in package metadata.
- Added `NOTICE`, recording how this package relates to the OpenVINO C headers
  and why no upstream text is copied: what the raw layer reproduces is the set
  of names and numbers an ABI consists of, which a binding cannot differ from
  and still be a binding. It also states that no third-party source is bundled
  and that the runtime is loaded at run time and never shipped.
  `nimble releaseCheck` requires both `LICENSE` and `NOTICE` to exist.
- Added the full CI workflow: nine jobs covering static checks, unit tests, the
  ABI comparison, the runtime smoke test, lifetimes under ORC and ARC, CPU
  inference in debug and release, examples plus a packaging consumption test,
  documentation, and a scheduled valgrind job. Six of them run on both
  Windows and Linux.
- Every third-party GitHub Action is pinned to a commit SHA rather than a tag,
  with the tag it corresponded to recorded beside it.
- Updated `actions/checkout`, `actions/setup-python` and
  `actions/upload-artifact` to their Node.js 24 releases after GitHub warned
  that the previous Node.js 20 actions were deprecated. The new versions stay
  pinned to full commit SHAs.
- Added `ci/install-openvino.py`, which installs OpenVINO for CI from an
  immutable wheel URL verified against a published sha256, on both platforms
  from one implementation. It refuses to run if its pinned version disagrees
  with `TargetOpenVinoVersion`, so CI cannot test a version the library does
  not claim.
- Added `ci/collect-diagnostics.py`, uploaded on failure by every job that
  needs a runtime. It reports the platform, the OpenVINO layout and what the
  runtime sees through this package's own `list_devices` example. It never
  dumps the environment: values are printed only for an allowlist of path and
  version variables, everything else appears as a name and a length, and
  anything whose name suggests a credential is withheld entirely.
- Added the release workflow and `ci/release-archive.py`. The archive base name
  is derived from the package version, an explicitly supplied release date and
  the pinned OpenVINO version; the date has no default and the runner's clock is
  never read. Archives come from `git archive`, are read back to check that they
  contain exactly one top-level directory and no runtime or model files, carry
  `.sha256` sidecars that are re-verified, and are built twice and compared to
  show they are reproducible from a commit. A manual run is a dry run;
  `contents: write` is granted only to the publishing job, which only a pushed
  tag can reach.
- Completed the tag-triggered publish job. It downloads only the four archives
  and checksum sidecars produced by the verified archive job, validates their
  exact names and count, then creates or idempotently updates the GitHub
  Release from `RELEASE_NOTES.md`. It still never creates a tag or publishes a
  Nimble package.
- Added `nimble packagingCheck`, `nimble memcheck` and `nimble releaseArchive`.
- `nimble lint` now requires every `cast` in `src` and `examples` to have an
  invariant written within ten lines above it. The first version of the rule
  looked three lines back and reported every site that was in fact documented,
  because a real invariant takes several sentences; that is recorded next to
  the rule.
- Added `README.md`, `CONTRIBUTING.md`, `STYLE_GUIDE.md`, `.editorconfig`,
  `.clang-format` and `.gitignore`.
- Added `docs/resonance-audit.md` recording the audit of the Resonance
  prototype this package replaces, including the ABI defects that must not
  be carried forward.
- Added `nimble format`, `formatCheck`, `lint`, `test`, `docs` and
  `releaseCheck` tasks, plus a blocking CI workflow for Windows x86_64 and
  Linux x86_64.
- Added `tools/mdcheck.nim`, a Nim implementation of the mechanically
  checkable Markdown rules, wired into `nimble lint` so documentation style
  is enforced without adding a non-Nim toolchain dependency. It also requires
  the README's Nim example to be the same code as `examples/minimal.nim`, which
  `nimble examples` compiles and runs, so the first thing a reader tries cannot
  rot.
- Added `nimble testLifecycle`, running the lifetime and error-path suites
  under both ORC and ARC, because a destructor that fires at a different time
  is exactly the kind of difference that turns into a double free.
- Added `nimble testIntegration`, running the CPU inference suite in debug and
  release. Release changes bounds checking and object layout, which is where an
  ownership mistake starts behaving differently.
- Added `nimble examples`, which compiles **and runs** every example. An
  example that builds but fails at run time is worse than none, because it
  looks like a working reference.
- Added `nimble checkFixtures`, plus `tools/sha256.nim` and
  `tools/fixturecheck.nim`. The checker verifies its own SHA-256 implementation
  against published FIPS 180-4 vectors, then recomputes every digest recorded
  in `tests/fixtures/README.md` and fails on an undocumented fixture or a
  documented file that is absent. It exists because the first digest written
  into that file had never been computed and was wrong.
- Added `tests/unit/tlibrary.nim`, covering the shared-library version suffix,
  the per-platform candidate list and its order, and the text of both
  diagnostics. It needs no runtime, so a wrong library name fails on every
  platform's CI rather than only where OpenVINO is installed.
- Added `tests/fixtures/relu_1x4_f32.xml`, a hand-written IR model computing
  `max(0, x)` over shape `[1, 4]`. Hand-written so the licence is unambiguous,
  the expected output is obvious by inspection, and reproducing it needs no
  tooling. ReLU rather than an identity model, because an identity model cannot
  distinguish "inference ran" from "the output happens to hold the input".
- Added `examples/minimal.nim`, `list_devices.nim`, `sync_infer.nim`,
  `tensor_basics.nim` and `profiling.nim`. All use the public managed API only.
- Added `.gitattributes` declaring `* text=auto eol=lf`. The LF requirement
  now travels with the repository instead of depending on each contributor's
  `core.autocrlf` setting, which would otherwise produce CRLF working trees
  that fail `nimble lint`.
- Package metadata is declared as literals in `openvino.nimble` rather than
  derived from `openvino/version.nim` at manifest evaluation time. Nimble
  copies the manifest into the installed package, where `srcDir` has been
  flattened, so reading a file under `src/` broke `nimble install` for every
  consumer. `nimble releaseCheck` asserts each literal against the version
  module instead, and rejects any manifest that reads files while being
  evaluated.
- `openvino.nimble` excludes the Resonance prototype from installation via
  `skipDirs` and `skipFiles`, so the installed package cannot hand a consumer
  the prototype binding. The exclusions are removed when `src/resonance` is
  deleted.
- Added `openvino/raw` as the explicit entry point for the C ABI layer, with
  modules for common, error, property, shape, node, model, tensor, compiled
  model, infer request, core and the symbol loader. Bindings cover the
  synchronous `0.1.0` surface and no variadic entry point.
- Added `nimble testSmoke`, which loads a real runtime and checks the library
  load, 55 required symbols, every bound property key, the runtime version,
  Core lifetime, device enumeration and the by-value shape regression.
- The OpenVINO library loader reports a missing library and a missing symbol
  as `OpenVinoLibraryError` with a diagnostic naming the platform, the expected
  OpenVINO version, the names tried and how to fix the search path. It
  distinguishes a file that is absent from one that exists but cannot be
  loaded, because the latter means a dependency such as the bundled oneTBB is
  missing and needs a different fix.

### Removed

- Removed the Resonance prototype: `src/resonance/`, `src/resonance.nim`,
  `examples/basic_infer.nim` and `perf_count_wrapper.c`. The wrapper bridged
  MinGW to MSVC varargs so profiling could be enabled; the non-variadic
  `ov_compiled_model_set_properties` together with the exported
  `ov_property_key_enable_profiling` data symbol replaces it. The prototype
  remains available from the `archive/resonance-before-openvino-nim` tag.
- Removed the `skipDirs` and `skipFiles` install exclusions, which existed only
  to keep the prototype out of the installed package.

- Added `openvino/raw/common`, binding `ov_status_e` and `ov_element_type_e`
  from the pinned `2026.4.0` headers. Both are `cint` aliases with constants
  rather than Nim enums, so a value the runtime returns and the binding does
  not know stays representable instead of becoming an illegal enum value.
- Added a C ABI probe and the `nimble testAbi` entry point. The probe is
  compiled against the pinned headers and linked into the test, so every
  comparison is against a value the C compiler produced. The task fails with
  an explicit message when the headers cannot be found, and never skips.
- Added the `-d:openvinoLib=...` compile-time option, which overrides the
  name or full path of the OpenVINO C API library. It changes only which file
  is opened, never an API signature, and it is not a way to target an
  OpenVINO version other than the pinned baseline.

### Documentation

- Added `DEVLOG.md`, a bilingual English and Chinese development log recording
  decisions, measurements and overturned assumptions. `tools/mdcheck.nim`
  requires the file to exist and requires both language halves to carry the
  same number of entries, so one half cannot silently fall behind.
- Added `docs/c-api-coverage.md`, recording the pinned `2026.4.0` headers with
  their checksums and classifying every C entry point as bound, planned or out
  of scope, together with its ownership and by-value facts.
- Added `docs/decisions/0001-symbol-loading.md`, recording why the raw layer
  resolves symbols explicitly instead of using Nim's `dynlib` pragma.
- Added `docs/decisions/0002-handle-model.md`, recording why handles are shared
  `ref` objects rather than non-copyable value types: a copy that slipped
  through a value type would produce two owners of one pointer, and the `ref`
  makes a double free inexpressible.
- Added `docs/ownership.md`, listing per function what is owned, borrowed or
  static, which function releases it, how long it is valid, and the order in
  which a last-error message must be read and released.
- Added `docs/architecture.md`, describing the two layers, the direction of
  every dependency, where the boundary conversions live, what is deliberately
  absent and which task enforces each of those rules.
- Added `docs/compatibility.md`, separating combinations that were actually run
  from those that were not. Linux, macOS, GPU, NPU and `--mm:refc` are listed
  as unverified rather than claimed.
- Added `docs/troubleshooting.md`, ordered by how early each failure happens.
  It leads with the oneTBB search path, which is the dependency that makes a
  present `openvino_c.dll` look missing.
- Added `docs/resonance-migration.md`, mapping the prototype's API onto this
  one, listing the three behaviours that were deliberately not carried over,
  and naming the ABI defects the rewrite fixed.
- Added `tests/fixtures/README.md`, recording each fixture's format, shapes,
  computation, checksum, origin and licence, and the exact expected output for
  the input the tests use.
