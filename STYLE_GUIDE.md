# Style guide

This guide is binding for `openvino-nim`. It fixes the rules that CI
enforces, so that upgrading an upstream style document never silently
changes what CI accepts.

Google publishes no official Nim style guide. This project therefore
combines three sources rather than transliterating Google C++ into Nim.

## Rule precedence

When the sources below disagree, the higher rule wins:

1. **ABI correctness.** Faithfulness to the pinned OpenVINO C API.
2. **Nim language convention.** The
   [Nim Standard Library Style Guide (NEP 1)](https://nim-lang.org/docs/nep1.html).
3. **Google maintainability principles.** Readability, short functions,
   explicit interfaces and comment quality from the
   [Google Style Guides](https://google.github.io/styleguide/).
4. **Personal preference.** Never a justification on its own.

Every exception must be local, must state its reason next to the code, and
must be covered by a test.

## Pinned tools

| Tool | Pin | Used by |
|---|---|---|
| Nim | 2.2.12 for the primary job; 2.0.0 as the minimum-supported job | build, `nim check` |
| `nimpretty` | The one shipped with the pinned Nim | `nimble format`, `nimble formatCheck` |
| `clang-format` | Pinned in CI; configured by `.clang-format` | handwritten C |

Never upgrade a formatter in the same commit as a functional change. A
formatter upgrade is its own commit containing the configuration change and
the resulting mechanical reformatting, and nothing else.

## Formatting

- Handwritten Nim, C and Markdown target a maximum of 80 columns.
- Exceptions to the column limit: URLs, unsplittable string literals,
  tables, generated declarations and commands that break when wrapped.
- Two-space indentation. No tabs. No trailing whitespace.
- UTF-8, LF line endings, exactly one trailing newline.
- Do not align `=`, types or comments into vertical columns across lines.
- `nimpretty --indent:2 --maxLineLen:80` is authoritative for Nim. Its
  output must be semantically identical to its input.

`.editorconfig` carries the same rules for editors. `nimble lint` fails on
tabs, CR characters, trailing whitespace and a missing final newline.

## Naming

| Subject | Rule | Example |
|---|---|---|
| Managed types, exceptions, enums | `PascalCase`, abbreviations as words | `OpenVinoError`, `CompiledModel` |
| Procs, funcs, variables, parameters, fields | `lowerCamelCase` | `compileModel`, `deviceName` |
| Public managed constants | `PascalCase` | `TargetOpenVinoMajor` |
| Private constants | `lowerCamelCase` | `defaultLibraryName` |
| Nim modules | lowercase `snake_case`, one responsibility | `compiled_model.nim` |
| Raw C types, functions, constants | Upstream spelling and value, verbatim | `ov_core_create`, `ov_status_e`, `F32` |
| C probe functions and variables | lowercase `snake_case` | `probe_shape_size` |
| C macros | `UPPER_SNAKE_CASE`, only when unavoidable | `OV_NIM_ASSERT_SIZE` |
| Test files | `t<subject>_<behavior>.nim` | `ttensor_lifecycle.nim` |
| Test helper modules | `m<subject>.nim` | `mopenvino_fixture.nim` |

Additional rules:

- Names state intent. Do not invent abbreviations to save characters.
  Community-standard short names such as `len`, `idx`, `ptr` and `msg` are
  fine.
- `i` and `j` are acceptable for tight loop counters only.
- Replace ambiguous boolean parameters with an enum or an options object
  rather than stacking bare `bool` arguments.
- Side-effect-free O(1) getters are named as properties: `shape`, `len`.
  Anything that triggers a native call, allocation, I/O or real computation
  uses `get...` or an action verb.
- Use one stable term per concept. Do not alternate between `request`,
  `req` and `infer` for the same thing.
- No type prefixes, Hungarian notation or author initials.

### Upstream spellings are ABI, not style

The raw layer preserves upstream underscores, all-caps values and upstream
typos. Two concrete cases in the pinned baseline:

- `UNKNOW_EXCEPTION` (status `-17`) is spelled that way upstream.
- `F8E5M3` is the symbol name even though its own header comment says
  `f8e5m2`.

Renaming either to satisfy Nim naming is forbidden. The managed layer may
present friendlier display text, but raw symbol names and values are fixed.

## Imports and module organisation

Three groups, separated by a blank line, alphabetical within each group:
`std`, third-party, then project-local.

```nim
import std/[options, strutils]

import third_party_package

import openvino/errors
import openvino/raw/core
```

- Import what you use. Never rely on another module's transitive imports.
- No unused imports and no cycles.
- No `include` for ordinary implementation code. Deterministic generated
  fragments are the only exception, and the reason must be recorded.
- Qualify raw calls with a module name or a clear alias so the unsafe
  boundary is visible at the call site.
- One responsibility per module. The file name, the module doc comment and
  the exported symbols must agree.
- Export explicitly. The top-level entry point must never leak raw, private
  or experimental modules.
- A module passing roughly 500 lines, or holding two independent ownership
  domains, triggers a split review. It is a review trigger, not an automatic
  failure.

## Layering

Dependencies flow downward only:

```text
src/openvino.nim          stable public entry point
src/openvino/*.nim        managed API
src/openvino/raw/*.nim    OpenVINO C ABI
src/openvino/private/     internal helpers, never re-exported
```

- `raw` must not depend on the managed layer.
- `private` must not be re-exported by `src/openvino.nim`.
- The package must not import Resonance or Isvik. The dependency direction
  is one-way: downstream applications depend on `openvino`, never the
  reverse.
- Low-level modules such as `errors`, `properties` and `handles` must not
  depend back on `core` or `model`.
- No implicit global `Core` and no global mutable configuration.

## Functions and interfaces

- One job per function. Passing roughly 40 logical lines triggers a split
  review.
- Prefer guard clauses and early return. Avoid nesting beyond three levels.
- Inputs first, outputs and mutable parameters last.
- Beyond roughly four parameters, or with several optional or boolean
  arguments, introduce an options object with named fields.
- Return values instead of C-style output pointers. Only the raw ABI layer
  keeps upstream output parameters.
- `let` by default. `var` only where the binding is actually reassigned.
- Prefer writing to the implicit `result`. Use `return` mainly for early
  exits that simplify control flow.
- Prefer plain `proc` and `func`. Reach for a template, macro, converter or
  elaborate generic only when a plain procedure cannot express the need.
- No implicit global state, hidden I/O or hidden environment mutation.
- Never disguise an expensive native call as a field access.

## Comments and API documentation

- Every handwritten source file starts with
  `SPDX-License-Identifier: Apache-2.0`. No personal author lines.
- The module doc states what the module is responsible for *and* what it is
  explicitly not responsible for.
- Every public type, field and proc carries a `##` doc comment.
  Non-obvious private helpers document their contract too.
- Public documentation states purpose, parameters, return value,
  ownership or borrowing, copying behaviour, blocking behaviour, exceptions,
  thread restrictions and invalidation conditions.
- Implementation comments explain *why* and state invariants. They do not
  restate what the code does.
- Complete sentences, consistent terminology, inclusive language.
- `TODO` must be trackable: `TODO(#123): ...`. An unowned `TODO`, `FIXME`
  or "later" note is not acceptable.
- Every unsafe block, `cast`, borrowed pointer and ignored native status
  explains its safety precondition in place. If it cannot be explained, it
  does not merge.

## Errors, ownership and unsafe code

- Never bare-`discard` an OpenVINO status. A status that genuinely must be
  ignored needs a local comment and a test that justifies it.
- No magic status numbers, property strings or dtype numbers. Use verified
  constants.
- No untyped `pointer` crossing a managed public boundary.
- `cast`, `unsafeAddr` and pointer arithmetic stay in the smallest possible
  scope inside `raw` or `private`.
- Every managed escape hatch has `unsafe` in its name and lists the
  caller's obligations in its doc comment.
- Catch specific exceptions. A broad `except:` needs a documented reason to
  rethrow or convert.
- Acquire and release a resource in the same readable scope, using `defer`
  or `finally` for exception safety.
- Close and destructor code stays simple, idempotent, allocation-free,
  log-free and exception-free.

## C files, ABI probes and generated code

- Handwritten `.c` and `.h` follow `.clang-format`.
- Probes are C, never C++. Include order: the matching project header, C
  standard library headers, then OpenVINO and third-party headers.
- No varargs, compiler-private ABI attributes or platform APIs unless the
  pinned C API offers no alternative, and then only with a dedicated
  decision record and test.
- Generated raw files record the generator, the input tag or commit, and a
  "do not edit" notice. Hand-editing generated output is a gate failure.
- Re-running a generator must produce a zero diff. The generator change and
  its output ship in the same commit.
- Formatters must not rename raw C symbols or change field order, types or
  calling conventions.

Raw declarations that need to bypass Nim naming checks use an approved,
immediately closed region:

```nim
{.push styleChecks: off.}

# Generated or header-faithful OpenVINO C declarations only.

{.pop.}
```

`nimble lint` rejects `styleChecks: off` anywhere outside
`src/openvino/raw`. Repository-wide style suppression is never acceptable,
including "to accommodate the raw layer".

## Tests

- Test names describe observable behaviour and its precondition. Not
  `test1`, `works` or `misc`.
- One primary behaviour per test. Failure messages include the operation,
  the input condition and both expected and actual values.
- Arrange, act, assert order. Section comments only when they add clarity.
- Deterministic, offline, order-independent. Never a fixed `sleep` to wait
  for asynchronous state.
- Keep the success, boundary, failure and lifetime paths of a public API in
  adjacent tests so a reviewer can read the contract in one place.
- Test helpers follow production style. Do not hide test intent behind
  large duplicated blocks.

## Markdown

- One H1 per document. ATX headings. Unique, complete heading names.
- Fenced code blocks with a language tag. Command blocks use `text`,
  `shell` or the specific shell.
- Link text describes the destination. Never "click here".
- Standard Markdown, not HTML, for layout.
- Prose wraps at 80 columns. URLs, tables, headings and code blocks are
  exempt.
- README examples must be copy-pasteable and compiled by CI. A comment is
  not a substitute for missing error handling.

## Exceptions

Any formatter or linter exception must be minimal in scope, adjacent to the
code it covers, explained, linked to an issue or decision record, and
covered by a test. Disabling a rule repository-wide to accommodate a single
raw symbol is not allowed.
