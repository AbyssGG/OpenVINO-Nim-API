# Development log / 开发日志

A dated record of what actually happened while building `openvino-nim`:
decisions, measurements, and the assumptions that turned out to be wrong.

`openvino-nim` 构建过程的按日记录：做了哪些决定、测了哪些事实，以及哪些
原有假设被推翻。

## How to read this log / 阅读说明

This log is written in both English and Chinese. The two halves below carry
the same entries in the same order. Any change must update both halves in the
same commit; `nimble lint` fails when the two halves hold a different number
of entries.

本文分英文与中文两部分，条目内容与顺序一致。任何改动必须在同一个提交里同时
更新两部分；两部分条目数不一致时 `nimble lint` 会失败。

This log is not a changelog. `CHANGELOG.md` records what changed for a user
of the package. This log records why, what was measured, and what is still
open. Where the two overlap, the changelog is the shorter statement.

本文不是 changelog。`CHANGELOG.md` 记录对使用者可见的变化；本文记录原因、
实测结果和尚未关闭的问题。两者重叠处以 changelog 的简短陈述为准。

Phase numbers refer to
[OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md).

阶段编号对应
[OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md](OPENVINO_NIM_0.1_DEVELOPMENT_PLAN.md)。

## English

### 2026-09-24 Phase 0: audit the prototype and freeze the scope

Audited the Resonance prototype that this package replaces, and verified the
plan's ABI claims against the pinned OpenVINO `2026.4.0` headers instead of
trusting them. Recorded the result in `docs/resonance-audit.md`, including
the SHA-256 of all 18 C headers.

Three defects in the prototype were confirmed by reading the headers.

`ov_common.h` shows status `-10` is `NOT_ALLOCATED`, not `ALLOCATED`, and
that four C-wrapper codes `-14` to `-17` were missing entirely.

The element-type problem is worse than the plan described. `ov_element_type_e`
rises implicitly from `DYNAMIC = 0U` to `F8E8M0`, 26 values in total, so
`U2`, `U3` and `U6` being absent shifts everything from `U8` upward by three.
The prototype bound `U8 = 13` where the real value is `16`. Any `u8` input
tensor was therefore handed to the runtime as a `U3` low-precision type. This
is a data-corruption defect, not a naming slip.

`ov_tensor.h` declares `ov_tensor_set_shape(ov_tensor_t*, const ov_shape_t)`,
taking the shape **by value**. The prototype passed a pointer. The same header
also declares `ov_tensor_create`, which lets OpenVINO own the storage, and
which the prototype never bound at all. That absence is why the prototype
only had an external host-pointer path.

`ov_common.h` states that `ov_get_error_info` returns a process-lifetime
pointer that must never be passed to `ov_free`, while `ov_get_last_err_msg`
returns an allocated string that must be. The prototype leaked the latter on
every failure.

Also found: the prototype's `perf_count_wrapper.c` is compiled
unconditionally, so a Linux build could never have succeeded, and it bridges
MinGW to MSVC varargs using the compiler-private `ms_abi` attribute.

One environment drift: the plan records Nim 2.2.10 on this machine; the
measured version is 2.2.12.

Open at the end of the phase: the baseline commit needed an authorisation
that cannot be derived from the plan.

### 2026-09-24 Phase 1: package skeleton, licence and minimal build

Added the `openvino` Nimble package, the layered source tree, the Apache-2.0
`LICENSE`, `README.md`, `CONTRIBUTING.md`, `STYLE_GUIDE.md`, `.editorconfig`,
a Google-based `.clang-format`, `.gitignore`, a first unit test, a Markdown
checker and a blocking CI workflow.

`src/openvino/version.nim` is the single source of truth for the package
version, the minimum Nim version and the pinned OpenVINO baseline.

Nimble imposed two constraints that only surfaced by running it.

`requires` must be a string literal. Nimble parses the manifest twice, once
declaratively and once in the VM, and rejects the package when the two
disagree; a computed dependency is invisible to the declarative parser.

Later, the packaging test showed that no manifest value may be computed by
reading a file. Nimble copies the manifest into the installed package and
flattens `srcDir`, so `staticRead("src/openvino/version.nim")` failed with
"cannot open file" for every consumer resolving the dependency. Both values
are now literals, and `nimble releaseCheck` asserts each one against the
version module, plus rejects any manifest that reads files while being
evaluated.

The same packaging test showed the installed package shipped the whole
prototype, letting a consumer `import resonance` and get the defective
binding. Fixed with `skipDirs` and `skipFiles`. Their paths are relative to
the package root and must keep the `src/` prefix even though installation
flattens `srcDir`; spelling them relative to `srcDir` excludes nothing and
fails silently.

Three self-reference bugs appeared in checks that scan repository text. The
`styleChecks: off` allowlist flagged the manifest, which stores that pragma
text as its search needle. The guard against reading files at manifest
evaluation time then matched its own error message, and after that its own
search literal. The lesson is recorded in the plan: any check that scans
repository text must be shown not to match its own implementation.

This machine has `core.autocrlf=true`, which would give every fresh checkout
CRLF and fail `nimble lint` through no fault of the contributor. Fixed with
`.gitattributes` declaring `* text=auto eol=lf`, so the rule travels with the
repository instead of depending on each developer's configuration.

Queried the official Nimble index: 2945 packages, none named `openvino`, and
no near-match containing `openvino` or `vino`.

Confirmed that `AbyssGG/Resonance` is already published under Apache-2.0 and
that all 11 local prototype files are byte-identical to its `main` branch.
That closes the provenance question and means the prototype could always have
been recovered from its published history. `AbyssGG/Isvik` and
`AbyssGG/NimVoice` are downstream consumers, which confirms the dependency
direction the plan assumes.

With authorisation, created a baseline commit tagged
`archive/resonance-before-openvino-nim`, then removed `resonance.nimble` so
Nimble would accept the package.

Open at the end of the phase: Linux compilation, which only CI's first run
can confirm.

### 2026-09-24 Phase 2: pin the C API surface and decide symbol loading

Extracted the full ABI surface from the six remaining headers and wrote
`docs/c-api-coverage.md`, classifying every C entry point as bound, planned
or out of scope, with its header, ownership rules and by-value facts.

Facts worth stating from that extraction. `ov_property_t.value` is
`const void*`, so a string value is a reinterpreted `const char*`. The first
field of `ov_profiling_info_t` is an anonymous nested enum, which the
prototype declared as `int32`; it happens to match but must be probed.
`ov_port_get_any_name` and `ov_port_get_element_type` accept only the
**const** port, which is a distinct type from the mutable port with its own
release function. Property keys are exported `const char*` data symbols, so
resolving one is a different operation from resolving a function.

Two experiments were run before writing any binding, and both overturned an
assumption.

An enum whose explicit values descend, the way the prototype declared
`ov_status_e`, compiles without complaint. The status-code defect was
therefore semantic, and no compiler would ever have caught it. The raw layer
still avoids Nim enums for `ov_status_e` and `ov_element_type_e`, using a
`cint` alias with constants, because casting an unexpected value from the
runtime into a Nim enum leaves it holding an illegal value.

Nim's `dynlib` pragma loads during module initialisation and cannot report
failure to Nim code. A program declaring a procedure against a missing
library printed `could not load: <lib>` and exited 1 before the first
statement of its own body. That makes `OpenVinoLibraryError`, checklist item
C13 and the diagnostics required by plan sections 8.5 and 12.3 unreachable
with the pragma. The raw layer will therefore resolve symbols explicitly with
`loadLib` and `symAddr`, as recorded in
[ADR 0001](docs/decisions/0001-symbol-loading.md).

That decision carries one documented exception to the rule that the raw layer
raises nothing: the loader must raise, because a call that never happened has
no `ov_status_e` to return, and reusing `GENERAL_ERROR` would merge "OpenVINO
is not installed" with "OpenVINO rejected your arguments".

Added `src/openvino/private/library.nim`, the only module that knows a
platform-specific library name, with a `-d:openvinoLib=` compile-time
override. It reports which names to try and never loads, searches the
filesystem or touches environment variables.

Still to do in this phase: the nine raw binding modules, the loader
implementation, the C ABI probe, the required-symbol test, the Core smoke
test and the `nimble testAbi` entry point. No raw bindings exist yet, so
nothing in the package calls OpenVINO.

### 2026-09-24 Phase 2: first verified slice, status codes and element types

Added `src/openvino/raw/common.nim`, a C ABI probe in `tests/abi/`, the
`nimble testAbi` entry point, and a separate `--styleCheck:usages` pass over
the raw layer in `nimble lint`.

The probe is compiled against the pinned headers and linked into the Nim
test, so the C side of every comparison is produced by the compiler rather
than transcribed a second time. Each enumerator appears once, next to its own
name, through a macro that stringifies it; an enumerator renamed upstream
fails to compile in the probe, which is the intended alarm.

21 ABI tests pass. The comparisons are driven from the C side, so a status
code or element type that exists in the header but not in the binding fails
the count check rather than going unnoticed.

Verified the test is not vacuous by setting `U8` to `13`, the value the
prototype bound. Two tests failed and `nimble testAbi` exited 1, so this
check would have caught the data-corruption defect from the audit.

Layout facts now confirmed rather than assumed. The `ov_profiling_info_t`
status field has the same width as a C enum, which the prototype declared as
`int32` without checking. `ov_shape_t` is an `int64` rank followed by a
pointer. `ov_property_t`, `ov_version_t`, `ov_profiling_info_list_t` and
`ov_callback_t` are all two-pointer structs. Nim's `bool` matches C `bool`,
which matters because `ov_model_is_dynamic` returns one.

Two Nimble and toolchain constraints surfaced while wiring the task.
NimScript has no path `/` operator, so paths are joined as strings. More
interesting, Nim forwards a `--passC` value to the C compiler verbatim, so an
include path such as `C:/Program Files (x86)/Intel/...` is split on its
spaces and gcc reports `Files: No such file or directory`. Rather than fight
nested quoting, the task sets `CPATH` and `INCLUDE`, which gcc, clang and
MSVC read and which need no quoting at all.

`nimble testAbi` refuses to run without the headers. It looks at
`OPENVINO_INCLUDE_DIR`, then at `INTEL_OPENVINO_DIR`, and on failure prints
what it needed, what it tried and how to fix it, then exits 1. It never skips
and reports success.

Still to do in this phase: the loader implementation and the remaining raw
modules for property, core, shape, node, model, compiled model, tensor and
infer request, plus the required-symbol test, the Core smoke test and the
`ov_tensor_set_shape` by-value regression. Nothing in the package calls
OpenVINO yet.

### 2026-09-24 Phase 2: the loader, and the first real calls into OpenVINO

Added `openvino/raw/loader`, `error`, `shape`, `core` and `tensor`, plus
`tests/abi/tsmoke_runtime.nim` and `nimble testSmoke`. All 8 smoke tests pass
against the installed runtime, so the package now genuinely calls OpenVINO.

Before writing the loader, one more measurement settled its shape. A `dynlib`
given as a runtime variable rather than a constant still loads during module
initialisation, and the diagnostic is worse: the message reads
`could not load: ` with an empty name, because the variable has not been
assigned yet when the init-time load runs. The variable form is therefore
strictly worse than the constant form, and ADR 0001 stands.

Bindings are declared through an `{.openvinoImport.}` macro pragma, so a
binding is a single declaration that reads like the C prototype it mirrors:

```nim
proc ov_core_create*(core: ptr ptr ov_core_t): ov_status_e {.openvinoImport.}
```

The expansion adds a cached procedure pointer, resolves it through
`functionSymbol` on first call, and forwards the arguments. The imported C
name is the Nim procedure's own name, so the two cannot disagree, and there is
no per-function boilerplate to keep in step.

The by-value regression for `ov_tensor_set_shape` asserts more than a success
status. It creates a tensor, replaces its shape, then reads the shape back and
requires the observed dimensions, element count, byte size and element type to
match what was requested. A pointer-passing declaration, which is what the
prototype had, would hand OpenVINO the wrong bytes; only checking the observed
result distinguishes a correct signature from one that merely fails to crash.

A deployment lesson came out of getting the smoke test to run. The library
would not load even when given its full path, with the file demonstrably
present on disk. The cause was a missing dependency: `openvino_c.dll` needs
`openvino.dll` beside it, and that needs the bundled oneTBB library from the
runtime's `3rdparty` directory, which is a different directory. This is
exactly the case the deployment hint warns about, so the loader now
distinguishes "no such file" from "file exists but could not be loaded" and
says that the second means a dependency is missing, not a wrong path.

Two Nim details worth recording. `return` is not allowed inside a `unittest`
`test` block, because the block is a template body, so early-exit guards are
written as nested conditions. And Nim now warns that an implicit `string` to
`cstring` conversion from a non-const location will become an error, so
`symAddr` calls convert explicitly.

Still to do in this phase: raw modules for property, node, model, compiled
model and infer request, and extending the required-symbol list as they land.

### 2026-09-25 Phase 3: errors and the handle lifetime model

Added `openvino/errors`, `openvino/private/handles`,
`openvino/private/conversions`, [ADR 0002](docs/decisions/0002-handle-model.md),
`docs/ownership.md`, and three test files. `nimble testLifecycle` runs the
lifetime and error-path tests under both ORC and ARC; all eight nimble tasks
exit 0.

Handles are `ref` objects rather than non-copyable value types. The plan allowed
either, and the deciding argument is what each one risks. A value type risks a
copy slipping through and two owners releasing the same pointer. A shared `ref`
makes that impossible by construction, because there is one pointer field and
every alias reads it; what remains is release happening later than expected,
which is a resource-timing question rather than a memory-safety one. Trading a
memory-safety risk for a timing risk is the right direction for a binding whose
failures would otherwise be native crashes, and `close()` exists for callers who
need a known release point.

`handles.nim` takes its release function as a parameter and knows nothing about
OpenVINO. That is what makes the lifetime tests meaningful: a counting stub
stands in for `ov_*_free`, so the tests assert that a release happened *exactly
once*. A test that cannot count releases cannot detect a double free, which is
the bug that matters. Closing three times still counts one release, aliases
share one closed state, and a thousand abandoned handles are all collected.

The last-error ordering is now implemented in exactly one place. The pointer is
fetched, copied, and released in a `finally`, and only then is
`ov_get_error_info` called, because that is itself an OpenVINO call and any call
may replace the global last-error slot. A test reads a nonexistent model 200
times and requires every captured detail to be identical, which is what a freed
or overwritten buffer would break.

`conversions.nim` holds the checked arithmetic. The index helper is the one
worth naming: converting `-1` to `csize_t` yields 18446744073709551615, so
checking before the conversion is the whole point rather than a formality. The
overflow checks test the divisor form before multiplying, because a wrapped
product looks like a plausible small count and would be used to size a buffer.

Two small Nim frictions: `"needle" in haystack` for strings needs `std/strutils`
rather than coming from `system`, and a `nimcall` release procedure cannot
capture, so the test's counter is a global.

### 2026-09-24 Phase 2 complete: full raw surface, prototype deleted

Added the remaining raw modules for property, node, model, compiled model and
infer request, plus `openvino/raw` as the explicit entry point for the layer.
9 smoke tests pass against the installed runtime.

Deleted `src/resonance/`, `src/resonance.nim`, `examples/basic_infer.nim` and
with them `perf_count_wrapper.c`. That wrapper existed to bridge MinGW to MSVC
varargs so that profiling could be switched on; the non-variadic
`ov_compiled_model_set_properties` and the exported
`ov_property_key_enable_profiling` data symbol replace it outright, and both
are now bound and exercised. The prototype is recoverable from the
`archive/resonance-before-openvino-nim` tag and from `AbyssGG/Resonance`.

With the prototype gone, the `skipDirs` and `skipFiles` exclusions in
`openvino.nimble` are removed, and the legacy exclusion list that `lint`
reported on every run is now empty.

Ownership asymmetries that the header forced into the design, each recorded in
the doc comment of the function it applies to. `ov_get_error_info` returns a
process-lifetime pointer that must never be freed, while
`ov_get_last_err_msg` returns an allocated string that must be. Ports come in
const and mutable flavours with separate release functions, and only the const
one accepts the metadata getters. Property keys are exported data symbols, so
each is a nullary procedure rather than a Nim `const`, because a `const`
cannot hold a value resolved at run time.

Windows wide-path model reading is declared as `ptr uint16` rather than a Nim
wide-string type, so that the element width is stated rather than assumed, and
only under `when defined(windows)` because the header guards it.

### 2026-09-25 Phase 4: the managed API, and inference that actually runs

Added the managed layer: `shape`, `properties`, `tensor`, `node`, `model`,
`compiled_model`, `infer_request` and `core`, plus the test fixture, the
integration suite, five examples, and the tasks `testIntegration`, `examples`
and `checkFixtures`. 50 integration tests and 18 new unit tests pass, including
real ReLU inference on CPU in both debug and release.

The fixture is hand-written IR rather than an exported model, and the model is a
ReLU. Both choices were between alternatives. Hand-written means the licence is
unambiguous, the expected output can be computed mentally, and reproducing it
needs no tooling; an exported model needs provenance tracing and a framework
version. ReLU was chosen over an identity model because an identity model cannot
distinguish "inference ran" from "the output tensor happens to hold the input",
and over multiply-by-constant because a `Const` node needs a binary weights
file, which would make the fixture two files that can desynchronise. The test
input is `[-1.5, 2.0, -0.25, 4.0]`: two signs and a fraction, so an
implementation that transposed, scaled or reordered anything fails on it.

One of our own assumptions was disproved during this phase. A test asserted that
`profilingInfo()` returns nothing when the profiling property was never set. The
CPU plugin returned three entries anyway. The test was rewritten to record what
the plugin does rather than to assert what we expected, and the conclusion is
now stated in `examples/profiling.nim`: the presence of entries does not prove
profiling is on, timings above zero do. Running that example gives the numbers:
without the property, three entries, none executed, zero microseconds total;
with it, the same three entries, one executed, two microseconds.

A second assumption was disproved the same way. Non-ASCII model paths on Windows
now go through OpenVINO's wide-character entry points, on the reasoning that a
narrow `const char*` would be decoded in the active code page and mangled. A
direct measurement, calling `ov_core_read_model` with a UTF-8 path containing
both Chinese and Cyrillic on a host with code page 936, returned `OK`. So 2026.4
treats those bytes as UTF-8 and the wide path is not what makes non-ASCII paths
work. It is kept, because "works in the version we measured" is not "is
specified to work" and UTF-16 removes the question entirely, and a test now
records the narrow entry point's answer rather than asserting one.

The fixture documentation carried a SHA-256 that had been written down without
ever being computed, and it was wrong. That is worse than no checksum, because a
reader would trust it. Fixed by computing the real digest and by adding
`tools/sha256.nim` and `tools/fixturecheck.nim`, wired into `nimble lint`. The
checker verifies its own implementation against published FIPS 180-4 vectors
before hashing anything, so a broken implementation reports itself instead of
agreeing with an equally broken expectation; its digest for the fixture also
agrees with an independent implementation. It fails on an undocumented fixture
and on a documented file that is absent, so the documentation cannot drift in
either direction. SHA-256 is written out in full because the Nim standard
library has only SHA-1 and the `checksums` package is not bundled with a Nim
installation.

The README example was in the same category: prose claiming an API that nothing
compiled. It is now `examples/minimal.nim`, which `nimble examples` runs, and
`tools/mdcheck.nim` compares the README block against that file, ignoring
comments and blank lines so each can carry the text that suits it.

`examples/tensor_basics.nim` failed to compile on `initShape([])`, because an
empty array literal has no element type and both the `varargs[int]` and
`openArray[int64]` overloads match it. Written as `initShape()` it is
unambiguous. Worth recording because it is a wart any caller wanting a scalar
shape would hit.

Lifetime behaviour under repetition is now measured rather than reasoned about: a
thousand tensors, a thousand inference requests each used for a real inference,
and a hundred model reads, all created and released in a loop. The request loop
counts mismatches instead of checking inside the loop, so a failure reports how
many iterations went wrong rather than stopping at the first.

The external-buffer split is held in place by tests rather than by documentation
alone. One asserts that `tensorFrom` really copies, by mutating the source
afterwards: if that read back the new value, every caller of the safe
constructor would silently be on the unsafe path. Another writes through the
caller's pointer after closing the unsafe tensor, which is a use-after-free
under a wrong release and simply works under the right one.

Packaging was re-checked from the consumer's side rather than from the
repository's. Installing into a fresh `--nimbleDir` yields one manifest and
thirty `.nim` files with `srcDir` flattened into the package root, and no tests,
examples, tools, docs, fixture or executables. A program in a separate directory
that can see only that installation compiles and runs a real inference.

Still open: the Linux ABI and smoke jobs, which only CI's first run can close;
GPU and NPU, which are discovered on this host but on which no inference has
been run; `--mm:refc`, which is not claimed.

### 2026-09-25 Linux verification, and the defect it found on the first run

Ran the whole suite on a second host: Ubuntu 26.04.1 LTS, kernel 7.0.0-34,
x86_64, Nim 2.2.4, OpenVINO 2026.4.0 installed with pip. Twelve tasks, all
exit 0: check, formatCheck, lint, test, releaseCheck, checkFixtures, testAbi,
testSmoke, testLifecycle, testIntegration, examples, docs. That closes the
Linux side of the compile check, the ABI comparison and the CPU inference
requirement.

The package went over as `git archive HEAD`, so what was tested is what a
consumer clones, not a working tree with build artefacts in it.

Both hosts turned out to have the same upstream build,
`2026.4.0-22959-99c81491cc3-releases/2026/4`. That makes the ABI result
stronger than a version match: it is one ABI checked against two compilers and
two C libraries. The Nim versions differ, 2.2.4 against 2.2.12, which is also
worth having.

**The first Linux run found a real defect, and it was in the part of the
package whose entire job is to be portable.** The Linux candidate library name
was `libopenvino_c.so` and nothing else. A pip installation of OpenVINO ships
`libopenvino_c.so.2640`, with that as its SONAME and no unversioned symlink,
because a wheel has no reason to carry a link that only a linker would use. So
the package raised `OpenVinoLibraryError` against an installation that was
complete and working. Measured before changing anything: with the default
candidate the load failed and the diagnostic named the platform, the expected
OpenVINO version, the one name tried and the search-path hint; with
`-d:openvinoLib` pointed at the versioned file, all nine smoke tests passed.
That isolates the cause to the name and nothing else.

The fix is two candidates, unversioned first because that is the name upstream
documents and the archive and apt layouts provide, then the versioned one. The
suffix is derived from the three version components in `openvino/version.nim`
rather than written out, so bumping the baseline cannot leave a stale name
behind; `TargetOpenVinoPatch` was added for that, and `releaseCheck` now
asserts all three components against the version string. `tests/unit/tlibrary.nim`
pins both the derivation and the literal `2640` that a real installation uses,
because asserting only the derivation would keep passing if the scheme itself
were wrong. After the fix, Linux `testSmoke` passes with no override.

Linux also reported a warning Windows cannot: `imported and not used: 'paths'`
in `core.nim`, because everything that module needs from `paths` sits inside a
`when defined(windows)` branch. The import is now inside the same branch. A
warning that only appears on the platform where the code is correct is noise,
and noise is what stops anyone reading warnings.

Two things this run did not close. The memory check could not be completed:
valgrind is not installed on that host, and AddressSanitizer cannot run over
the OpenVINO call path at all. ASan aborts inside its own `__cxa_throw`
interceptor with `real___cxa_throw == 0`, because the C++ ABI arrives with the
`dlopen`ed runtime after ASan has already set up its interceptors, and OpenVINO
throws internally while probing plugins. `LD_PRELOAD`ing libasan gets six tests
further and hits the same assertion. Every frame in that report is inside ASan
or inside OpenVINO; none is in this package. ASan with leak detection over
`thandle_lifetime.nim`, which touches only our own code, reports nothing.

A counting error of our own also surfaced: the ABI suite was recorded as 22
tests in the plan and the log. It is 21, on both hosts and by counting the
file. Corrected rather than quietly left.

### 2026-09-25 Phase 5: CI, provenance, and the last of the open checklist

Everything in sections A through G is now ticked. The remaining work was less
about code than about making claims checkable, so most of what follows is a
mechanism rather than a feature.

**CI, written to fail rather than to skip.** Nine jobs: static, unit, abi,
smoke, lifecycle, integration-cpu, examples-package, docs, memory. Six run on
both Windows and Linux. Every job's underlying command was run on both real
hosts before the workflow was written, so the workflow describes something that
has been observed to work rather than something that ought to.

The pins were fetched, not guessed. Each third-party action is a commit SHA with
the tag it corresponded to in the comment beside it, obtained by querying each
repository's tags. OpenVINO is pinned to one wheel per platform by immutable URL
and the sha256 PyPI publishes, and `ci/install-openvino.py` verifies the digest,
deletes the file if it does not match, and unpacks with `zipfile`. pip never
resolves a dependency, because nothing here imports OpenVINO from Python. The
script also refuses to run when its pin disagrees with `TargetOpenVinoVersion`,
so CI cannot quietly test a version the library does not claim.

That pin turned out to be cross-checkable in a stronger way than the plan asked
for. All 18 C headers in the pip wheel are byte-identical to the ones recorded
from the Windows archive install months of work ago. The ABI this package is
written against therefore does not depend on how OpenVINO was installed, and the
build number in the wheel file name, 22959, is the one both runtimes report.

**Diagnostics that cannot leak a token.** A failure on a machine you cannot log
into needs to say which OpenVINO was installed, what is on disk and what the
runtime saw. The collector reports exactly that, and reports the environment by
allowlist: eight path and version variables by value, everything else as a name
and a character count, and anything whose name suggests a credential withheld
entirely. A missing variable stays diagnosable without its value becoming
readable by anyone who can download the artefact.

**The release archive derives its name and never reads the clock.** `--date` has
no default. A tag push takes the date from the annotated tag's message and exits
if it is not there, saying plainly that it refuses to fall back to the runner's
clock. The archives are read back after being built: exactly one top-level
directory equal to the base name, no file with a runtime or model extension,
sidecars re-verified, and the whole thing built twice and compared byte for byte.
Two of those checks earned their place immediately. The dirty-tree check failed
the first local run, correctly, because `git archive` ships the commit rather
than what you see. And the naming self-test confirmed the base name against the
example the plan states: `openvino-nim-0-1-0-2026-9-24-ov2026-4-0`.

**valgrind closed the memory check that AddressSanitizer could not.** 3.26.0,
two targets chosen so that a leak means something in each: our own code with
leak detection on, and one real end-to-end inference. Zero definite leaks, zero
indirect leaks, zero errors, and the log carries `@[0.0, 2.0, 0.0, 4.0]` proving
the run really inferred rather than exiting early under the tool. `-d:useMalloc`
matters here: without it Nim serves allocations from its own arena and valgrind
sees one block, so a wrapper-level leak would be invisible.

**A lint rule whose first version was wrong.** Every `cast` in `src` and
`examples` must now have an invariant written above it. The first version looked
three lines back and reported all seven sites as undocumented, including the ones
written minutes earlier: a real invariant takes several sentences, so the marker
word sits at the top of a comment block while the cast sits at the bottom. Ten
lines, and the mistake recorded beside the constant. Tests are out of scope, with
the reason written down rather than left as an unexplained exclusion.

**Two items closed by argument rather than by code.** The generated-binding
zero-diff check has no subject: there is no generated code, because the
`{.openvinoImport.}` macro expands at compile time and leaves no intermediate
artefact to desynchronise or hand-edit. That is stronger than a zero-diff check,
and saying so is more honest than inventing a generator to satisfy a checklist.
The NOTICE question was answered the same way: no upstream text is copied, what
the raw layer reproduces is the names and numbers an ABI consists of, and
Apache-2.0 permits the use on even the most cautious reading. The file states the
relationship instead of copying anything.

**Thread contracts, with their authority marked.** `Core`, `Model`,
`CompiledModel` and `Tensor` now document sharing, and `docs/ownership.md` has a
table whose third column is how far each claim is backed: upstream's word,
stated in our API docs, or not measured. Nothing here takes a lock, and no
concurrency test exists; the table says so rather than implying otherwise by
omission.

**A second false pass from our own harness, caught the same way as the first.**
The zero-diff check reported success on Linux while doing nothing. The extracted
tree had been `git init`ed with no commit, so Nimble refused to read package info
at all, `nimble format` never ran, and `git diff` then reported no change, which
was true and meaningless. Reading the formatter's log rather than only its verdict
is what found it. Redone with a commit first: formatter runs, exit 0, tree
unchanged, on both platforms. The lesson is the same as the `tail` incident
earlier: a harness that reports on a command is a second thing that can be wrong,
and its output deserves the same suspicion as the code under test.

Still open, and only one thing: CI has never run. The repository has no remote,
so nine jobs that have each been exercised by hand are still nine jobs no runner
has executed. That is the whole of the Phase 5 gate's remaining item, and closing
it needs a push, which needs authorisation.

Finally, a methodology mistake worth recording because it nearly produced a
false pass. The first Linux runner piped every task into `tail` and then printed
`$?`, which is `tail`'s status, not the task's. Every exit code it reported was
meaningless. The runner now keeps full output in a file and reports the real
status, and the numbers above come from that second run.

## 中文

### 2026-09-24 Phase 0：审计原型并冻结范围

审计了本包要取代的 Resonance 原型，并且没有采信计划里的 ABI 论断，而是逐项
核对固定的 OpenVINO `2026.4.0` 头文件。结果写入 `docs/resonance-audit.md`，
含全部 18 个 C 头文件的 SHA-256。

读 header 确认了原型的三个缺陷。

`ov_common.h` 显示状态码 `-10` 是 `NOT_ALLOCATED` 而非 `ALLOCATED`，并且
`-14` 到 `-17` 四个 C wrapper 错误码完全缺失。

元素类型问题比计划描述的严重。`ov_element_type_e` 从 `DYNAMIC = 0U` 起隐式
递增到 `F8E8M0`，共 26 个值，因此缺少 `U2`、`U3`、`U6` 会让 `U8` 及其之后
全部偏移 3。原型把 `U8` 绑成 `13`，真实值是 `16`。任何按 `u8` 传入的输入
tensor 都会被 runtime 当作 `U3` 低精度类型解释。这是数据损坏级缺陷，不是
命名疏漏。

`ov_tensor.h` 声明 `ov_tensor_set_shape(ov_tensor_t*, const ov_shape_t)`，
shape **按值**传递，而原型传的是指针。同一 header 还声明了
`ov_tensor_create`，由 OpenVINO 持有存储，原型完全没有绑定——这正是原型只有
外部 host pointer 一条路径的根因。

`ov_common.h` 明确写出 `ov_get_error_info` 返回进程生命周期指针、绝不能传给
`ov_free`，而 `ov_get_last_err_msg` 返回的分配字符串必须释放。原型在每次
失败时泄漏后者。

另外发现：原型的 `perf_count_wrapper.c` 被无条件编译，所以 Linux 构建从来
不可能成功，而且它用编译器专有的 `ms_abi` attribute 做 MinGW 到 MSVC 的
variadic 桥接。

一处环境漂移：计划记载本机 Nim 2.2.10，实测为 2.2.12。

阶段结束时未关闭项：基线提交需要一项不能从计划推导的授权。

### 2026-09-24 Phase 1：项目骨架、许可证与最小构建

加入 `openvino` Nimble 包、分层源码目录、Apache-2.0 `LICENSE`、
`README.md`、`CONTRIBUTING.md`、`STYLE_GUIDE.md`、`.editorconfig`、基于
Google 风格的 `.clang-format`、`.gitignore`、第一个单元测试、Markdown
检查器和阻断式 CI 工作流。

`src/openvino/version.nim` 是包版本、最低 Nim 版本与固定 OpenVINO 基线的
唯一事实来源。

Nimble 有两个只有真正运行才会暴露的约束。

`requires` 必须是字符串字面量。Nimble 对 manifest 做两遍解析，一次声明式、
一次 VM 求值，两者不一致就拒绝整个包；计算出的依赖对声明式解析器不可见。

后来打包测试又表明，任何 manifest 字段都不能靠读文件得到。Nimble 会把
manifest 复制进安装后的包并摊平 `srcDir`，于是
`staticRead("src/openvino/version.nim")` 在依赖解析时对每个使用者都报
"cannot open file"。现在两个值都是字面量，`nimble releaseCheck` 反向断言
它们与版本模块一致，并拒绝任何在求值期读文件的 manifest。

同一个打包测试还显示安装后的包携带了整个原型，使用者能 `import resonance`
拿到有缺陷的绑定。用 `skipDirs` 与 `skipFiles` 修复。它们的路径相对包根
目录，即使安装会摊平 `srcDir` 也必须保留 `src/` 前缀；按 `srcDir` 相对书写
不会报错但什么也不排除，是静默失效。

扫描仓库文本的检查里出现了三次自指 bug。`styleChecks: off` 的 allowlist
命中了 manifest 本身，因为它把该 pragma 文本存作搜索串。随后"禁止 manifest
求值期读文件"的检查先命中自己的错误信息，再命中自己的检查字面量。教训已写
入计划：任何扫描仓库文本的检查都必须证明它不会命中自己的实现。

本机 `core.autocrlf=true`，会让任何新检出得到 CRLF 并使 `nimble lint` 失败，
而贡献者毫无过错。用 `.gitattributes` 声明 `* text=auto eol=lf` 修复，规则
随仓库传播，不依赖每个人的配置。

查询官方 Nimble 索引：2945 个包，无名为 `openvino` 者，也没有任何包含
`openvino` 或 `vino` 的近似名。

确认 `AbyssGG/Resonance` 已以 Apache-2.0 发布，且本地 11 个原型文件与其
`main` 分支字节级一致。这关闭了来源归属问题，也说明原型一直可以从已发布
历史恢复。`AbyssGG/Isvik` 与 `AbyssGG/NimVoice` 是下游消费者，印证了计划
假定的依赖方向。

在取得授权后建立基线提交并打上 `archive/resonance-before-openvino-nim`
标签，随后删除 `resonance.nimble` 以让 Nimble 接受该包。

阶段结束时未关闭项：Linux 编译，只能由 CI 的首次运行确认。

### 2026-09-24 Phase 2：固定 C API 面并决定符号加载方式

从其余六个 header 抽出完整 ABI 面，写成 `docs/c-api-coverage.md`，把每个
C 入口分类为 bound、planned 或 out of scope，并记录所属 header、所有权规则
与按值传参事实。

抽取过程中值得单独记下的事实：`ov_property_t.value` 是 `const void*`，因此
字符串值是重解释的 `const char*`。`ov_profiling_info_t` 的第一个字段是匿名
嵌套 enum，原型声明为 `int32`，碰巧吻合但必须 probe。
`ov_port_get_any_name` 与 `ov_port_get_element_type` 只接受 **const** port，
它与可变 port 是不同类型、有各自的释放函数。property key 是导出的
`const char*` 数据符号，解析它与解析函数是两种不同操作。

在写任何绑定之前跑了两个实验，两者都推翻了原有假设。

按原型那样给出降序显式值的 enum，编译毫无怨言。因此状态码缺陷是语义错误，
任何编译器都不会拦住。raw 层仍然不为 `ov_status_e` 与
`ov_element_type_e` 使用 Nim enum，而采用 `cint` 别名加常量，因为把 runtime
返回的意外值转入 Nim enum 会让它持有非法值。

Nim 的 `dynlib` pragma 在模块初始化阶段加载，无法把失败报告给 Nim 代码。
一个对缺失库声明过程的程序，在自己主体的第一条语句之前就打印
`could not load: <lib>` 并以 1 退出。这使得 `OpenVinoLibraryError`、
Checklist 项 C13 以及计划 §8.5 与 §12.3 要求的诊断在使用该 pragma 时无法
实现。因此 raw 层改用 `loadLib` 与 `symAddr` 显式解析符号，决策记录于
[ADR 0001](docs/decisions/0001-symbol-loading.md)。

该决策带来一条有记录的例外，针对"raw 层不抛异常"这条规则：加载器必须抛出，
因为一个从未发生的调用没有 `ov_status_e` 可返回，而复用 `GENERAL_ERROR`
会把"OpenVINO 没有安装"与"OpenVINO 拒绝了你的参数"混为一谈。

加入 `src/openvino/private/library.nim`，它是唯一知道平台相关库名的模块，
提供 `-d:openvinoLib=` 编译期覆盖。它只报告应尝试哪些名字，不做加载、不扫描
文件系统、不改动环境变量。

本阶段尚未完成：九个 raw 绑定模块、加载器实现、C ABI probe、必需符号测试、
Core smoke test 以及 `nimble testAbi` 入口。目前尚无任何 raw 绑定，因此包内
没有任何代码调用 OpenVINO。

### 2026-09-24 Phase 2：第一个已验证切面，状态码与元素类型

加入 `src/openvino/raw/common.nim`、`tests/abi/` 下的 C ABI probe、
`nimble testAbi` 入口，以及 `nimble lint` 中对 raw 层单独执行的
`--styleCheck:usages` 检查。

probe 针对固定 header 编译并链接进 Nim 测试，因此每次比对的 C 一侧都由编译器
产生，而不是再手抄一遍。每个枚举值只出现一次，紧挨着自己的名字，由一个宏做
字符串化；上游改名会让 probe 编译失败，这正是预期的报警方式。

21 个 ABI 测试通过。比对由 C 一侧驱动，因此 header 里存在而绑定里缺失的状态码
或元素类型会让计数检查失败，不会被悄悄漏过。

通过把 `U8` 改成原型绑定的 `13` 验证了该测试并非空转：两个测试失败，
`nimble testAbi` 以 1 退出。也就是说这个检查确实能抓住审计发现的数据损坏缺陷。

若干布局事实现在是确认的而非假定的。`ov_profiling_info_t` 的 status 字段宽度
与 C enum 相同，而原型未经核对就声明为 `int32`。`ov_shape_t` 是一个 `int64`
rank 后跟一个指针。`ov_property_t`、`ov_version_t`、
`ov_profiling_info_list_t` 与 `ov_callback_t` 均为双指针结构。Nim 的 `bool`
与 C `bool` 一致，这一点重要，因为 `ov_model_is_dynamic` 返回它。

接线过程中暴露了两个 Nimble 与工具链约束。NimScript 没有路径 `/` 操作符，
所以路径改用字符串拼接。更值得记的是，Nim 会把 `--passC` 的值原样转交 C
编译器，于是像 `C:/Program Files (x86)/Intel/...` 这样的 include 路径会在
空格处被切碎，gcc 报 `Files: No such file or directory`。与其和嵌套引号纠缠，
该任务改为设置 `CPATH` 与 `INCLUDE`——gcc、clang 与 MSVC 都读取它们，且完全
不需要引号。

`nimble testAbi` 在缺少 header 时拒绝运行。它先查 `OPENVINO_INCLUDE_DIR`，
再查 `INTEL_OPENVINO_DIR`，失败时打印需要什么、尝试过什么、如何修复，然后以
1 退出。它绝不会跳过并报告成功。

本阶段尚未完成：加载器实现，以及 property、core、shape、node、model、
compiled model、tensor、infer request 各 raw 模块，加上必需符号测试、Core
smoke test 和 `ov_tensor_set_shape` 的按值传参回归测试。包内目前仍无任何代码
调用 OpenVINO。

### 2026-09-24 Phase 2：加载器，以及第一次真正调用 OpenVINO

加入 `openvino/raw/loader`、`error`、`shape`、`core`、`tensor`，以及
`tests/abi/tsmoke_runtime.nim` 与 `nimble testSmoke`。8 个 smoke 测试针对已
安装的 runtime 全部通过，包内现在确实会调用 OpenVINO 了。

写加载器之前又做了一次测量来确定其形态。把 `dynlib` 写成运行期变量而非常量，
仍然在模块初始化阶段加载，而且诊断更差：消息是 `could not load: `，库名为空，
因为初始化期加载时该变量还没被赋值。所以变量形式严格差于常量形式，ADR 0001
的结论成立。

绑定通过 `{.openvinoImport.}` 宏 pragma 声明，因此一个绑定就是一行、读起来
与它镜像的 C 原型一致：

```nim
proc ov_core_create*(core: ptr ptr ov_core_t): ov_status_e {.openvinoImport.}
```

展开后会添加一个缓存的过程指针，首次调用时经 `functionSymbol` 解析，然后转发
参数。导入的 C 名称就是 Nim 过程自己的名字，两者无法不一致，也没有需要同步
维护的逐函数样板。

`ov_tensor_set_shape` 的按值回归测试断言的不只是成功状态。它创建 tensor、
替换 shape，然后把 shape 读回来，要求观测到的维度、元素数、字节数与元素类型
都与请求一致。传指针的声明——也就是原型的写法——会把错误的字节交给 OpenVINO；
只有检查观测结果才能区分"签名正确"与"恰好没崩"。

让 smoke 测试跑起来的过程带来一个部署层面的教训。即使给出完整路径、文件明明
存在于磁盘上，库依然加载失败。原因是依赖缺失：`openvino_c.dll` 需要同目录的
`openvino.dll`，而后者需要 runtime 的 `3rdparty` 目录下自带的 oneTBB 库——那
是另一个目录。这正是 deployment hint 警告的情形，因此加载器现在会区分"文件
不存在"与"文件存在但加载失败"，并说明后者意味着依赖缺失，而不是路径写错。

两个值得记录的 Nim 细节。`unittest` 的 `test` 块内不允许 `return`，因为那是
模板体，所以提前退出改写成嵌套条件。另外 Nim 现在会警告：从非 const 位置发生
的 `string` 到 `cstring` 隐式转换将来会成为错误，因此 `symAddr` 调用改为显式
转换。

本阶段尚未完成：property、node、model、compiled model、infer request 各 raw
模块，以及随其落地扩充必需符号列表。

### 2026-09-25 Phase 3：错误体系与 handle 生命周期模型

加入 `openvino/errors`、`openvino/private/handles`、
`openvino/private/conversions`、[ADR 0002](docs/decisions/0002-handle-model.md)、
`docs/ownership.md` 以及三个测试文件。`nimble testLifecycle` 在 ORC 与 ARC 下
分别运行生命周期与错误路径测试；八个 nimble 任务全部 exit 0。

handle 采用 `ref` 对象而非不可复制的值类型。计划允许二者之一，决定性的理由是
各自的风险性质不同。值类型的风险是某个复制漏过检查，导致两个所有者释放同一个
指针。共享 `ref` 从构造上排除了这一点——只有一个指针字段，所有别名读的都是它；
剩下的风险是释放时机晚于预期，那是资源占用问题而不是内存安全问题。对一个失败
形态本会是原生崩溃的绑定而言，用内存安全风险换时机风险是正确方向，而 `close()`
正是为需要确定释放点的调用者准备的。

`handles.nim` 把释放函数作为参数传入，对 OpenVINO 一无所知。这正是生命周期
测试有意义的前提：用一个计数 stub 顶替 `ov_*_free`，测试就能断言释放**恰好
发生一次**。无法计数释放的测试根本检测不出 double free，而那才是真正要防的
缺陷。连续 close 三次仍只计一次释放，别名共享同一关闭状态，一千个被遗弃的
handle 全部被回收。

last-error 的取用顺序现在只实现在一处。先取指针、复制、在 `finally` 中释放，
然后才调用 `ov_get_error_info`——因为后者本身也是一次 OpenVINO 调用，而任何
调用都可能覆盖全局 last-error 槽位。有一个测试连续 200 次读取不存在的模型，
要求每次捕获的详情完全一致；被释放或被覆盖的缓冲区会在这里暴露。

`conversions.nim` 承载各项受检算术。index 那个尤其值得点出：把 `-1` 转成
`csize_t` 会得到 18446744073709551615，所以"在转换之前检查"是这个 helper 的
全部意义，而不是形式主义。溢出检查采用先做除法比较再相乘的形式，因为溢出后的
乘积看起来像一个合理的小数值，而它会被用来给缓冲区定尺寸。

两个 Nim 小摩擦：字符串的 `"needle" in haystack` 需要 `std/strutils` 而非来自
`system`；`nimcall` 释放过程无法捕获外部变量，所以测试的计数器是全局的。

### 2026-09-24 Phase 2 收尾：raw 面补齐，原型删除

补上 property、node、model、compiled model、infer request 各 raw 模块，以及
`openvino/raw` 作为该层的显式入口。9 个 smoke 测试针对已安装 runtime 通过。

删除 `src/resonance/`、`src/resonance.nim`、`examples/basic_infer.nim`，连带
`perf_count_wrapper.c`。那个 wrapper 的存在只为桥接 MinGW 到 MSVC 的 variadic
调用以便开启 profiling；非 variadic 的 `ov_compiled_model_set_properties` 与
导出的 `ov_property_key_enable_profiling` 数据符号把它完全取代，两者现在都已
绑定并被测试覆盖。原型可从 `archive/resonance-before-openvino-nim` 标签以及
`AbyssGG/Resonance` 恢复。

原型删除后，`openvino.nimble` 里的 `skipDirs` 与 `skipFiles` 排除项一并移除，
`lint` 每次运行都会报告的 legacy 排除列表现在为空。

header 强加给设计的几处所有权不对称，各自记录在对应函数的文档注释里。
`ov_get_error_info` 返回进程生命周期指针、绝不能释放，而
`ov_get_last_err_msg` 返回必须释放的分配字符串。port 分 const 与可变两种、
各有独立释放函数，且只有 const 那种能用于 metadata getter。property key 是
导出的数据符号，因此每个都是无参过程而不是 Nim `const`——`const` 无法持有运行期
解析的值。

Windows 宽路径读模型声明为 `ptr uint16` 而非 Nim 宽字符串类型，以便显式陈述
元素宽度而不是假定，并且只在 `when defined(windows)` 下声明，因为 header 对它
加了守卫。
### 2026-09-25 Phase 4：managed API，以及真正跑起来的推理

加入 managed 层：`shape`、`properties`、`tensor`、`node`、`model`、
`compiled_model`、`infer_request`、`core`，以及测试 fixture、集成测试套件、
五个示例，和 `testIntegration`、`examples`、`checkFixtures` 三个任务。50 个
集成测试与 18 个新增单元测试通过，其中包含 debug 与 release 两种模式下在 CPU 上
真实执行的 ReLU 推理。

fixture 是手写 IR 而不是导出的模型，模型选的是 ReLU。两个选择都是在备选之间
权衡的结果。手写意味着许可证归属无歧义、期望输出可以心算、复现不依赖任何工具
链；导出的模型则需要追溯来源并固定框架版本。选 ReLU 而不是恒等模型，因为恒等
模型无法区分"推理确实执行了"与"输出 tensor 恰好还是输入"；不选乘常数，因为
`Const` 节点需要二进制权重文件，fixture 就会变成两个可能失去同步的文件。测试
输入取 `[-1.5, 2.0, -0.25, 4.0]`：两种符号加一个小数，因此任何做了转置、缩放
或重排的实现都会在它上面失败。

本阶段推翻了我们自己的一个假设。原先有个测试断言：未设置 profiling 属性时
`profilingInfo()` 返回空。CPU plugin 照样返回了三条。该测试改为记录 plugin 的
实际行为，而不是断言我们的预期，结论写进了 `examples/profiling.nim`：条目存在
并不证明 profiling 已开启，时间大于零才证明。跑一遍那个示例就能拿到数据：未设
属性时三条、无一执行、总计 0 微秒；设置后同样三条、一条执行、2 微秒。

第二个假设以同样方式被推翻。Windows 上的非 ASCII 模型路径现在走 OpenVINO 的
宽字符入口，理由是窄 `const char*` 会按当前代码页解码而被破坏。直接测量——在
代码页 936 的机器上，用同时含中文与西里尔字母的 UTF-8 路径调用
`ov_core_read_model`——返回了 `OK`。也就是说 2026.4 把这些字节当作 UTF-8，宽
路径并不是非 ASCII 路径能工作的原因。它仍然保留，因为"在我们测的版本上能用"
不等于"规格保证能用"，而 UTF-16 彻底消除了这个问题；同时新增一个测试记录窄
入口的答案，而不是断言某个答案。

fixture 文档里那个 SHA-256 是写下来但从未计算过的，而且是错的。这比没有校验和
更糟，因为读者会相信它。处理方式是算出真实摘要，并加入 `tools/sha256.nim` 与
`tools/fixturecheck.nim`，接进 `nimble lint`。检查器在哈希任何文件之前先用
公开的 FIPS 180-4 测试向量验证自己的实现，这样一个错误的实现会自己报错，而不是
与一个同样错误的期望互相印证；它给出的 fixture 摘要也与另一个独立实现一致。
它在"目录里有未记录的 fixture"和"文档记录了不存在的文件"两种情况下都失败，
因此文档不会向任一方向漂移。SHA-256 完整写出，因为 Nim 标准库只有 SHA-1，而
带 SHA-256 的 `checksums` 包并不随 Nim 安装分发。

README 的示例属于同一类问题：用散文声称一个没有任何东西去编译的 API。它现在是
`examples/minimal.nim`，由 `nimble examples` 实际运行，`tools/mdcheck.nim`
把 README 代码块与该文件比对，比对时忽略注释与空行，让两边各自携带合适的文字。

`examples/tensor_basics.nim` 曾因 `initShape([])` 编译失败：空数组字面量没有
元素类型，`varargs[int]` 与 `openArray[int64]` 两个重载都能匹配。写成
`initShape()` 即无歧义。值得记录，因为任何想要标量 shape 的调用者都会撞上
这个别扭处。

重复场景下的生命周期行为现在是实测而非推理：一千个 tensor、一千个各自完成一次
真实推理的 infer request、一百次模型读取，全部在循环中创建并释放。request 循环
采用累计不一致次数而不是在循环内断言，这样失败时报告的是有多少次迭代出错，而
不是停在第一次。

外部 buffer 的归属划分由测试而不是仅由文档守住。一个测试在事后修改源数据来断言
`tensorFrom` 确实做了复制——如果那里读回了新值，说明每个"安全"构造器的调用者都
在不知情中走上了 unsafe 路径。另一个测试在关闭 unsafe tensor 之后再通过调用者的
指针写入：在错误的释放实现下这是 use-after-free，在正确的实现下它只是正常工作。

打包这次是从使用者一侧复核的，而不是从仓库一侧。向全新的 `--nimbleDir` 安装后
得到 1 个 manifest 与 30 个 `.nim`，`srcDir` 被摊平为包根，没有 tests、examples、
tools、docs、fixture 或可执行文件。随后在一个只能看到该安装的独立目录里编译并
运行程序，真实完成了一次推理。

仍未关闭：Linux 的 ABI 与 smoke 作业，只能由 CI 的首次运行关闭；GPU 与 NPU，
在本机能被发现但尚未在其上执行过推理；`--mm:refc`，不作声明。
### 2026-09-25 Linux 验证，以及首次运行就暴露的缺陷

在第二台机器上跑了全套：Ubuntu 26.04.1 LTS、内核 7.0.0-34、x86_64、Nim 2.2.4、
用 pip 安装的 OpenVINO 2026.4.0。十二个任务全部 exit 0：check、formatCheck、
lint、test、releaseCheck、checkFixtures、testAbi、testSmoke、testLifecycle、
testIntegration、examples、docs。这关闭了编译检查、ABI 对照与 CPU 推理三项的
Linux 一侧。

包是以 `git archive HEAD` 传过去的，因此被测的正是使用者 clone 到的内容，而不是
一个带着构建产物的工作树。

两台机器装的结果是同一个上游构建 `2026.4.0-22959-99c81491cc3-releases/2026/4`。
这让 ABI 结果比“版本号一致”更有分量：它是同一套 ABI 在两个编译器、两套 C 库上的
对照。而 Nim 版本是不同的，2.2.4 对 2.2.12，这一点也值得有。

**首次 Linux 运行发现了一个真实缺陷，而且正好落在这个包里唯一以“可移植”为职责的
部分。** Linux 的候选库名只有 `libopenvino_c.so` 一个。pip 安装的 OpenVINO 提供的
是 `libopenvino_c.so.2640`，SONAME 也是它，并且没有无版本号的符号链接——wheel 没有
理由携带一个只有链接器才会用的符号链接。于是本包在一个完整可用的安装上抛出了
`OpenVinoLibraryError`。改动之前先测：默认候选下加载失败，诊断报出了目标平台、
期望的 OpenVINO 版本、试过的那一个名字和搜索路径提示；把 `-d:openvinoLib` 指向带
版本号的文件后，9 个 smoke 测试全过。这就把原因锁定在名字上，别无其他。

修复是两个候选，无版本号的在前——那是上游文档里的名字，也是 archive 与 apt 布局
提供的，然后才是带版本号的。后缀由 `openvino/version.nim` 的三个版本数字推导而不是
写死，这样改基线不会留下过期的库名；为此新增了 `TargetOpenVinoPatch`，并让
`releaseCheck` 反向断言三个数字与版本字符串一致。`tests/unit/tlibrary.nim` 同时钉住
推导规则和真实安装上观测到的字面量 `2640`——只断言推导的话，即使方案本身错了它也
照样通过。修复后 Linux 侧 `testSmoke` 无需任何覆盖即通过。

Linux 还报出一个 Windows 上不可能出现的警告：`core.nim` 里
`imported and not used: 'paths'`，因为该模块用到 `paths` 的全部代码都在
`when defined(windows)` 分支内。现在 import 也放进了同一个分支。一个只在“代码本来
就正确”的平台上出现的警告是噪音，而噪音正是让人不再读警告的原因。

这次有两件事没有关闭。内存检查没能完成：那台机器没装 valgrind，而
AddressSanitizer 根本无法覆盖 OpenVINO 的调用路径。ASan 在它自己的 `__cxa_throw`
拦截器里以 `real___cxa_throw == 0` 断言失败——C++ ABI 是随 `dlopen` 进来的 runtime
一起到场的，那时 ASan 早已建立好拦截器，而 OpenVINO 在探测插件时正常地抛异常。用
`LD_PRELOAD` 预载 libasan 能多跑 6 个测试，随后触发同一处断言。那份报告里的每一帧
都在 ASan 内部或 OpenVINO 内部，没有一帧在本包代码里。对只涉及本包自身代码的
`thandle_lifetime.nim` 做带泄漏检测的 ASan 运行，则没有任何发现。

还暴露了一个我们自己的计数错误：ABI 套件在计划和日志里被记成 22 个测试，实际是
21 个——两台机器实测如此，逐一清点文件也如此。已改正，而不是悄悄留着。

最后记一个方法学错误，因为它差点产出一次假通过。第一版 Linux 运行脚本把每个任务
都管道进 `tail`，然后打印 `$?`——那是 `tail` 的退出码，不是任务的。它报告的每一个
退出码都毫无意义。现在脚本把完整输出留在文件里并报告真实状态，上面那些数字来自
重跑的第二次。
### 2026-09-25 Phase 5：CI、来源归属，以及 Checklist 的最后几项

A 到 G 段全部勾选。剩下的工作与写功能关系不大，更多是把"声称"变成"可被机械检查"，
所以下面记的多数是机制而不是特性。

**CI 是按"宁可失败也不跳过"写的。** 九个作业：static、unit、abi、smoke、lifecycle、
integration-cpu、examples-package、docs、memory，其中六个同时跑 Windows 与 Linux。
每个作业底层调用的命令，在写 workflow 之前都已在两台真机上跑过，因此 workflow 描述
的是已被观测到可行的事，而不是理应可行的事。

固定值是查来的，不是猜的。四个第三方 action 各自固定到 commit SHA，旁边注释里写上它
当时对应的 tag，SHA 由查询各仓库 tag 得到。OpenVINO 按平台各固定一个 wheel，用不可变
URL 加 PyPI 公布的 sha256；`ci/install-openvino.py` 校验摘要，不匹配就删文件，然后用
`zipfile` 解包。全程没有 pip 解析依赖——因为本包没有任何地方从 Python 里 import
openvino。脚本还会在自身固定版本与 `TargetOpenVinoVersion` 不一致时拒绝运行，这样 CI
不可能悄悄测一个库并不声称支持的版本。

这个固定值还带来一个比计划要求更强的交叉核对结果：pip wheel 里的 18 个 C header，与
很早之前从 Windows archive 安装记录下来的那 18 个值**逐字节相同**。也就是说本包所针对
的 ABI 不依赖于 OpenVINO 的安装方式；wheel 文件名里的 build 号 22959，正是两台机器
runtime 自报的那个。

**不会泄露 token 的诊断。** 在一台你登不上去的机器上失败，需要知道装的是哪个
OpenVINO、磁盘上有什么、runtime 看见了什么。收集器就报这些，而环境变量按 allowlist
处理：8 个路径与版本类变量打印值，其余只打印名字与字符数，名字里含凭据字样的连长度都
不打印。这样"某个变量没设"仍然可诊断，而值不会变成任何能下载产物的人都能读到的东西。

**发布归档的名字是推导出来的，而且绝不读时钟。** `--date` 没有默认值。tag 触发时日期
取自 annotated tag 的消息，取不到就退出，并明确写出"拒绝回退到 runner 的时钟"。归档
生成后会被读回校验：顶层目录集合必须恰好等于基名、不得含任何 runtime 或模型扩展名的
文件、sidecar 重算比对，并且整体构建两次逐字节比较。其中两项检查立刻证明了自己的价值：
工作树不干净的检查让本机第一次运行正确地失败了，因为 `git archive` 打的是 commit 而不
是你看到的内容；命名自检则把基名与计划里给出的例子对上了——
`openvino-nim-0-1-0-2026-9-24-ov2026-4-0`。

**valgrind 关掉了 AddressSanitizer 做不到的内存检查。** 3.26.0，两个目标是按"泄漏在
各自语境下意味着什么"分开选的：只含本包代码的那个开启泄漏检测，另一个走一次真实端到端
推理。definitely lost 0、indirectly lost 0、错误 0，而且日志里有
`@[0.0, 2.0, 0.0, 4.0]`，证明它在工具下真的完成了推理而不是提前退出。`-d:useMalloc`
在这里是关键：不加它 Nim 从自有 arena 分配，valgrind 只看到一整块，包装层的泄漏将不
可见。

**一条第一版是错的 lint 规则。** 现在 `src` 与 `examples` 里每个 `cast` 都必须在上方
写出不变量。第一版只回看三行，结果把七处全部误报——包括几分钟前才写好的那些：真正的
不变量说明要几句话，标记词落在注释块顶部而 cast 在底部。改成十行，并把这个失误记在
常量旁边。测试不在规则范围内，理由写下来了，而不是留成一个没有解释的排除项。

**两项是用论证而不是用代码关闭的。** "生成绑定重复生成零 diff"这一项没有对象：仓库里
没有生成代码，`{.openvinoImport.}` 宏在编译期展开，不留下任何可能失去同步或被手改的
中间产物。这比零 diff 检查更强，而如实说明这一点比为了满足 checklist 去造一个生成器更
诚实。NOTICE 的问题用同样方式回答：没有复制任何上游文本，raw 层复现的是 ABI 本身由之
构成的名字与数值，而且即便按最保守的读法 Apache-2.0 也允许这种使用。那个文件陈述关系，
不复制内容。

**线程契约，并标出每条说法的依据。** `Core`、`Model`、`CompiledModel`、`Tensor` 现在
都写了共享语义，`docs/ownership.md` 有一张表，第三列专门写"这条说法的依据有多强"：上游
的声明、我们 API 文档里的陈述、还是根本没测过。本包不加任何锁，也没有任何并发测试；表格
直接这么写，而不是靠省略暗示别的。

**又一次来自我们自己测试脚手架的假通过，发现方式与上次相同。** 零 diff 检查在 Linux 上
报了成功，而它什么都没做：那个解压出来的树 `git init` 之后没有提交，Nimble 因此完全拒绝
读取包信息，`nimble format` 根本没运行，随后的 `git diff` 当然没有差异——结论为真而毫无
意义。是去读 formatter 的日志、而不是只看它的判定，才发现这一点。补测时先建了提交：
formatter 运行、exit 0、树未变，两个平台都如此。教训与前面 `tail` 那次一样：报告命令结果
的脚手架本身是第二个可能出错的东西，它的输出值得与被测代码同等的怀疑。

仍然未关闭的只有一件：CI 从未运行过。仓库没有远端，于是九个已被逐一手工验证过的作业，
仍然是九个没有任何 runner 执行过的作业。这就是 Phase 5 Gate 剩下的全部内容，关闭它需要
推送，而推送需要授权。
