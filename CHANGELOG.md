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

Nothing yet.

## 0.1.0

Not released. Under development.

### Nim API

- Added the `openvino` Nimble package with `import openvino` as its stable
  entry point. The entry point exports managed API only and never re-exports
  the raw C ABI layer.
- Added `openvino/version` as the single source of truth for the package
  version, the minimum supported Nim version and the pinned OpenVINO
  baseline. The Nimble manifest derives its fields from this module, so the
  manifest cannot drift from the library.

### OpenVINO compatibility

- Established `2026.4.0` as the first verified baseline, pinned to upstream
  tag `2026.4.0` and release commit `99c8149`.
- Declared no compatibility with `2026.3`, `2027.x` or any patch release
  that has not been verified end to end.

### Project

- Added the Apache-2.0 `LICENSE` file. Previously the license was declared
  only in package metadata.
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
  is enforced without adding a non-Nim toolchain dependency.
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
