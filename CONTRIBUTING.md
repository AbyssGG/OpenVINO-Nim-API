# Contributing

Thanks for helping with `openvino-nim`. This document covers how to build,
check and submit changes. Read [STYLE_GUIDE.md](STYLE_GUIDE.md) before
writing code, and
[OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md)
for the phase-by-phase scope of `0.1.0`.

## Prerequisites

| Component | Requirement | Needed for |
|---|---|---|
| Nim | 2.0.0 or newer; 2.2.12 is the pinned primary version | everything |
| OpenVINO Runtime | `2026.4.x` | ABI, integration and example tasks |
| OpenVINO C headers | From the same `2026.4.x` release | regenerating bindings, ABI probes |
| `clang-format` | Version pinned by CI | handwritten C |

Unit tests, linting and formatting do not require OpenVINO. Tasks that do
require it fail with an explicit message naming the missing prerequisite.
They never skip silently and report success.

## Everyday commands

```shell
nimble check         # Nimble's own package validation
nimble lint          # style, whitespace and layering checks
nimble format        # rewrite handwritten Nim with the pinned nimpretty
nimble formatCheck   # fail if anything is not already formatted
nimble test          # unit tests, no OpenVINO runtime required
nimble docs          # generate API docs into build/docs
nimble releaseCheck  # verify version metadata consistency
```

`nimble check` is Nimble's built-in package validation and cannot be
overridden by a task of the same name. Strict compiler checking
(`nim check --styleCheck:error`) therefore runs inside `nimble lint`.

### Runtime and release tasks

These entry points are available in the current task set. Tasks that need an
OpenVINO installation fail with an explicit prerequisite message instead of
silently reporting a skip as a pass:

| Task | Introduced with |
|---|---|
| `nimble testAbi` | C ABI probe |
| `nimble testSmoke` | runtime symbol smoke test |
| `nimble testLifecycle` | CPU lifecycle and error paths |
| `nimble testIntegration` | CPU inference closed loop |
| `nimble examples` | runnable public examples |
| `nimble packagingCheck` | clean-directory package consumer |
| `nimble releaseArchive` | release packaging dry run |

## Before you open a change

1. `nimble formatCheck` passes with a zero diff.
2. `nimble lint` passes.
3. `nimble test` passes.
4. `nimble check` passes.
5. Every new public symbol has a doc comment stating ownership, copying,
   blocking behaviour and exceptions.
6. Every new public symbol has at least one success test and at least one
   related failure-path test.
7. `docs/c-api-coverage.md` or the managed API list is updated.
8. `CHANGELOG.md` is updated whenever user-observable behaviour changes.
9. `DEVLOG.md` records any decision, measurement or overturned assumption
   worth remembering. It is bilingual: add the entry to both the `## English`
   and the `## 中文` half in the same commit. `nimble lint` fails when the two
   halves hold a different number of entries.

## Working with the raw layer

The raw layer is not a convenience wrapper. It is an audited transcription
of a pinned C ABI.

- Never guess a signature, ownership rule or thread-safety property. Check
  the pinned `2026.4.x` headers. If the headers do not settle the question,
  record a blocking issue and a decision record rather than implementing a
  guess.
- Never rename an upstream symbol to satisfy Nim naming, including upstream
  typos.
- Never call a C varargs entry point. Use the non-variadic properties API.
- Never hand-edit generated bindings. Change the generator and commit the
  regenerated output together.
- `{.push styleChecks: off.}` is permitted only inside `src/openvino/raw`
  and must be closed immediately with `{.pop.}`.

## Commits

- One atomic, explainable change per commit, ideally matching one phase
  sub-goal.
- Keep pure reformatting separate from semantic change.
- Ship a generator change together with its generated output.
- Update tests, documentation and the changelog in the same commit as a
  public API change.
- The commit message answers What, Why, Test and Risk. "Fix issue" is not
  acceptable.
- Prefer small, complete changes. A handwritten semantic diff approaching
  1000 lines should be split. Generated files are counted separately and may
  not be used to disguise handwritten complexity.

Conventional Commit style, with the scope naming the layer:

```text
feat(raw): bind OpenVINO 2026.4 core and property APIs
test(raw): add OpenVINO 2026.4 ABI probe
feat(runtime): add tensor and synchronous inference
docs: document handle ownership rules
```

Branch names: `feat/...`, `fix/...`, `docs/...`, `test/...`, `chore/...`.

## Review order

Reviewers work through a change in this order, because an early problem
makes later comments moot:

1. Scope and layering
2. ABI correctness and ownership
3. API shape and naming
4. Tests
5. Cross-platform behaviour and documentation
6. Formatting and lint

Generated diffs are reviewed through their input version, the generator
change, the coverage diff and the ABI probe results, not by scanning
thousands of lines by eye.

## What does not belong here

`openvino-nim` is a general-purpose binding. The following belong in a
downstream application, not in this package:

- Choosing a default device, ordering device preferences or falling back to
  another device after a failure.
- Cache file naming, cache directories, cache invalidation or
  "import if the blob exists, otherwise compile and export" policies.
- Model discovery, downloading, preprocessing, postprocessing or result
  interpretation.
- Logging, CLI handling, configuration files, task scheduling or infer
  request pooling.

Import and export of a compiled model are offered as explicit operations.
Deciding *when* to use them is the application's job.

## Release actions

Creating tags, pushing, opening pull requests, publishing releases and
publishing to the Nimble package index all require explicit authorisation
from the project owner for that specific action. Nothing in the development
plan or in this document grants that authorisation implicitly.

## License

Contributions are accepted under Apache-2.0, matching
[LICENSE](LICENSE). Every handwritten source file starts with
`SPDX-License-Identifier: Apache-2.0`.
