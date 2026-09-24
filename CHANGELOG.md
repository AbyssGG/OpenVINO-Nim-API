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
