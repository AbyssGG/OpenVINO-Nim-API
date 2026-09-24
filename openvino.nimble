# SPDX-License-Identifier: Apache-2.0
#
# Package manifest for the community-maintained OpenVINO Nim API.
#
# Public distribution name  : openvino-nim
# Nimble package identifier : openvino   (Nimble identifiers forbid hyphens)
# Nim import root           : import openvino
#
# The metadata below is written as literals on purpose. See the comment above
# the assignments; `nimble releaseCheck` asserts every literal against
# src/openvino/version.nim, which remains the single source of truth.

import std/strutils

const
  versionModule = "src/openvino/version.nim"
  formatArgs = "--indent:2 --maxLineLen:80"
  styleOffPragma = "styleChecks: off"
  rawLayerPrefix = "src/openvino/raw"

  legacyPrototypePaths: array[0, string] = []
    ## Resonance prototype paths still awaiting migration.
    ##
    ## Now empty: the prototype has been deleted, so nothing is excluded from
    ## formatting or style checking any more. Kept as a declaration rather
    ## than removed so that `lint` keeps reporting an empty exclusion set
    ## instead of silently having no concept of one.

proc stringMetadata(name: string): string =
  ## Reads the exported string constant `name` from the version module.
  ##
  ## Only safe to call from a task body, which runs in a development
  ## checkout. The manifest body must never read the version module: Nimble
  ## also evaluates this manifest from the *installed* package, where
  ## `srcDir` has been flattened into the package root and
  ## `src/openvino/version.nim` does not exist.
  ##
  ## Raises `ValueError` when the constant is missing, so a renamed or
  ## deleted constant fails loudly instead of yielding an empty string.
  let versionSource = readFile(versionModule)
  for rawLine in versionSource.splitLines():
    let parts = rawLine.split('=', 1)
    if parts.len != 2:
      continue
    if parts[0].strip() != name & "*":
      continue
    let
      openQuote = parts[1].find('"')
      closeQuote = parts[1].rfind('"')
    if openQuote < 0 or closeQuote <= openQuote:
      continue
    return parts[1][openQuote + 1 ..< closeQuote]
  raise newException(ValueError,
    "cannot read string constant '" & name & "' from " & versionModule)

# These assignments must stay literals, for two independent reasons.
#
# First, Nimble parses this manifest twice, declaratively and in the VM, and
# rejects the package when the two disagree; a computed `requires` is
# invisible to the declarative parser.
#
# Second, Nimble copies the manifest into the installed package and re-reads
# it there. Installation flattens `srcDir`, so a manifest that reads
# `src/openvino/version.nim` at evaluation time fails with "cannot open
# file" for every consumer of the installed package.
#
# `nimble releaseCheck` closes the loop by asserting each literal against
# src/openvino/version.nim, so the single source of truth still wins.
version = "0.1.0"
author = "WANG"
description = "Community-maintained Nim bindings for the OpenVINO Runtime " &
  "C API. Not an official Intel or OpenVINO project."
license = "Apache-2.0"
srcDir = "src"

# No skipDirs or skipFiles are needed. They previously excluded the Resonance
# prototype from installation; the prototype is now deleted, so everything
# under srcDir belongs in the package. Should an exclusion be needed again,
# note that those paths are relative to the package root and keep the `src/`
# prefix even though installation flattens srcDir away; spelling them relative
# to srcDir silently skips nothing.

requires "nim >= 2.0.0"

# --------------------------------------------------------------------------
# Helpers shared by the development tasks below.
# --------------------------------------------------------------------------

proc toRepoPath(path: string): string =
  ## Normalises a path to forward slashes so that prefix comparisons behave
  ## identically on Windows and Linux. `listFiles` yields native separators.
  path.replace('\\', '/')

proc isLegacyPrototype(path: string): bool =
  ## Reports whether `path` belongs to the Resonance prototype.
  for legacy in legacyPrototypePaths:
    if path == legacy or path.startsWith(legacy & "/"):
      return true
  false

proc collectNimSources(dir: string, acc: var seq[string]) =
  ## Appends every Nim source below `dir` to `acc`, recursing into
  ## subdirectories. A missing directory is ignored so that the tasks work
  ## in every development phase.
  if not dirExists(dir):
    return
  for path in listFiles(dir):
    let repoPath = toRepoPath(path)
    if repoPath.endsWith(".nim") or repoPath.endsWith(".nims"):
      acc.add(repoPath)
  for sub in listDirs(dir):
    collectNimSources(sub, acc)

proc allNimSources(): seq[string] =
  ## Returns every Nim source in the repository, prototype included.
  result = @[]
  for dir in ["src", "tests", "examples", "tools"]:
    collectNimSources(dir, result)

proc legacySources(): seq[string] =
  ## Returns the prototype sources that are excluded from style enforcement.
  result = @[]
  for path in allNimSources():
    if isLegacyPrototype(path):
      result.add(path)

proc handwrittenSources(): seq[string] =
  ## Returns every handwritten Nim source this project owns, plus this
  ## manifest. Prototype files are excluded; generated raw bindings are
  ## excluded once they exist.
  result = @[]
  for path in allNimSources():
    if not isLegacyPrototype(path):
      result.add(path)
  result.add("openvino.nimble")

proc rawSources(): seq[string] =
  ## Returns the raw ABI modules.
  ##
  ## They are checked separately from managed code because they must preserve
  ## upstream `ov_*` spellings, which `--styleCheck:error` rejects. They still
  ## have to compile and still have to pass `--styleCheck:usages`, so that a
  ## name used inconsistently with its own declaration is caught.
  result = @[]
  for path in allNimSources():
    if path.startsWith(rawLayerPrefix):
      result.add(path)

proc managedSources(): seq[string] =
  ## Returns the sources that must satisfy `--styleCheck:error`.
  ##
  ## The raw layer is excluded because it must preserve upstream `ov_*`
  ## spellings; it is covered by a separate, narrower check. The manifest is
  ## excluded because it is NimScript, not a compilable module.
  result = @[]
  for path in handwrittenSources():
    if path.startsWith(rawLayerPrefix) or path.endsWith(".nimble"):
      continue
    result.add(path)

proc reportFailures(title: string, failures: seq[string]) =
  ## Prints `failures` and aborts when the sequence is not empty.
  if failures.len == 0:
    return
  echo title
  for failure in failures:
    echo "  " & failure
  quit(1)

proc announceLegacyExclusions() =
  ## Makes the prototype exclusion visible on every lint run.
  let legacy = legacySources()
  if legacy.len == 0:
    return
  echo "Excluded Resonance prototype sources (migration pending):"
  for path in legacy:
    echo "  " & path

# --------------------------------------------------------------------------
# Tasks. Tasks whose subject matter does not exist yet are introduced by the
# development phase that owns them; see CONTRIBUTING.md.
# --------------------------------------------------------------------------

task format, "Format every handwritten Nim source with nimpretty":
  for path in handwrittenSources():
    exec "nimpretty " & formatArgs & " " & path

task formatCheck, "Fail when any handwritten Nim source is not formatted":
  var unformatted: seq[string] = @[]
  let sources = handwrittenSources()
  for path in sources:
    let scratch = path & ".nimpretty-check"
    exec "nimpretty " & formatArgs & " --out:" & scratch & " " & path
    let
      formatted = readFile(scratch)
      current = readFile(path)
    rmFile scratch
    if formatted != current:
      unformatted.add(path)
  reportFailures("Unformatted sources (run `nimble format`):", unformatted)
  echo "Formatted: ", sources.len, " files."

task lint, "Run style, whitespace and layering checks":
  var failures: seq[string] = @[]
  announceLegacyExclusions()

  for path in managedSources():
    exec "nim check --hints:off --styleCheck:error --path:src " & path

  for path in rawSources():
    exec "nim check --hints:off --styleCheck:usages --path:src " & path

  let sources = handwrittenSources()
  for path in sources:
    let content = readFile(path)
    if content.contains('\t'):
      failures.add(path & ": contains a tab character")
    if content.contains("\r"):
      failures.add(path & ": contains a CR character, expected LF endings")
    if content.len == 0 or content[^1] != '\n':
      failures.add(path & ": missing final newline")
    for rawLine in content.splitLines():
      if rawLine.len > 0 and rawLine[^1] in {' ', '\t'}:
        failures.add(path & ": has trailing whitespace")
        break
    # The manifest is skipped because it stores the pragma text as the search
    # needle itself; NimScript cannot relax style checks for compiled modules.
    if not path.endsWith(".nimble") and
        content.contains(styleOffPragma) and
        not path.startsWith(rawLayerPrefix):
      failures.add(path & ": '" & styleOffPragma &
        "' is only allowed under " & rawLayerPrefix)

  let entry = readFile("src/openvino.nim")
  if entry.contains("export raw") or entry.contains("export openvino/raw"):
    failures.add("src/openvino.nim: must not re-export the raw layer")

  # Every `cast` must state the invariant that makes it sound, within the three
  # lines above it. The rule is mechanical so that "it was obvious at the time"
  # cannot be the justification: a cast is where the compiler stops helping, so
  # the reasoning has to be written down next to it.
  #
  # Scope: the shipped code, meaning `src` and `examples`. `src` because it is
  # what a user runs, and `examples` because it is what a user copies, which
  # makes a cast there teaching material. Tests are excluded: a cast inside a
  # test is scaffolding that never reaches a consumer, and several of them exist
  # precisely to inspect raw memory that the library keeps private. Excluding
  # them is a scope decision, not an exemption from review.
  #
  # This manifest is excluded because it stores the search needle itself, which
  # is the self-reference trap that has already produced three false positives
  # in this file's history.
  # The window is ten lines rather than one or two. The first version looked
  # three lines back and reported every site that was in fact documented: a
  # real invariant takes several sentences, so the marker word ends up at the
  # top of a comment block and the cast sits at the bottom. Ten lines is enough
  # for a four-line comment plus the statement it introduces, and still close
  # enough that the reader finds the reasoning without scrolling.
  const
    invariantMarker = "invariant:"
    invariantWindow = 10
  for path in handwrittenSources():
    if path.endsWith(".nimble"):
      continue
    if not (path.startsWith("src/") or path.startsWith("examples/")):
      continue
    let lines = readFile(path).splitLines()
    for index, line in lines:
      if not line.contains("cast["):
        continue
      var explained = false
      for back in 1 .. invariantWindow:
        if index - back < 0:
          break
        if lines[index - back].contains(invariantMarker):
          explained = true
          break
      if not explained:
        failures.add(path & ":" & $(index + 1) & ": a cast needs a comment " &
          "containing '" & invariantMarker & "' within the " &
          $invariantWindow & " lines above it")

  reportFailures("Lint failures:", failures)

  # Markdown rules are checked by a Nim tool so that lint needs no toolchain
  # beyond the pinned Nim. It exits non-zero on any violation.
  exec "nim r --hints:off tools/mdcheck.nim"

  # Fixture documentation is checked here rather than only in the test tasks
  # because it needs no OpenVINO runtime, and because a wrong checksum is a
  # documentation defect. It was a real one: the first recorded digest had been
  # written down without being computed.
  exec "nim r --hints:off tools/fixturecheck.nim"

  echo "Lint passed for ", sources.len, " Nim files."

task checkFixtures, "Recompute every fixture checksum recorded in the docs":
  # Also reachable through `nimble lint`; available on its own so that a
  # fixture change can be checked without waiting for the whole lint pass.
  exec "nim r --hints:off tools/fixturecheck.nim"

task test, "Run unit tests that do not require an OpenVINO runtime":
  var sources: seq[string] = @[]
  collectNimSources("tests/unit", sources)
  if sources.len == 0:
    echo "No unit tests found under tests/unit."
    quit(1)
  for path in sources:
    exec "nim c --hints:off --path:src -r " & path

proc openvinoIncludeDir(): string =
  ## Locates the pinned OpenVINO C headers.
  ##
  ## Checks `OPENVINO_INCLUDE_DIR` first, then derives the path from
  ## `INTEL_OPENVINO_DIR`, which the official setup scripts export. Aborts with
  ## an explicit message naming both variables when neither resolves, because a
  ## task that quietly skips and reports success is worse than one that fails.
  # Paths are joined with a forward slash rather than with os.`/`, which
  # NimScript does not provide. Windows accepts forward slashes here.
  const marker = "openvino/c/ov_common.h"
  var
    candidates: seq[string] = @[]
    attempted: seq[string] = @[]

  let direct = getEnv("OPENVINO_INCLUDE_DIR")
  if direct.len > 0:
    candidates.add(direct)
  let root = getEnv("INTEL_OPENVINO_DIR")
  if root.len > 0:
    candidates.add(root & "/runtime/include")

  for candidate in candidates:
    attempted.add(candidate)
    if fileExists(candidate & "/" & marker):
      return candidate

  echo "Cannot find the OpenVINO C headers."
  echo "  Needed: <include dir>/" & marker
  if attempted.len == 0:
    echo "  Neither OPENVINO_INCLUDE_DIR nor INTEL_OPENVINO_DIR is set."
  else:
    echo "  Tried:"
    for path in attempted:
      echo "    " & path
  echo "  Set OPENVINO_INCLUDE_DIR to the include directory of an OpenVINO " &
    stringMetadata("TargetOpenVinoVersion") & " installation, or run the"
  echo "  official setupvars script so that INTEL_OPENVINO_DIR is exported."
  quit(1)

proc addIncludePath(variable, path: string) =
  ## Prepends `path` to the compiler include-search environment variable
  ## `variable`, preserving any existing entries.
  let separator = (when defined(windows): ";" else: ":")
  let existing = getEnv(variable)
  if existing.len == 0:
    putEnv(variable, path)
  else:
    putEnv(variable, path & separator & existing)

task testAbi, "Compare the raw bindings against the pinned OpenVINO headers":
  let includeDir = openvinoIncludeDir().replace('\\', '/')
  echo "OpenVINO headers: ", includeDir

  # The include directory is handed to the C compiler through its own search
  # variables rather than through --passC. Nim forwards a --passC value to the
  # compiler verbatim, so a real Windows installation path such as
  # "C:/Program Files (x86)/Intel/..." is split on its spaces and gcc reports
  # "Files: No such file or directory". CPATH covers gcc and clang; INCLUDE
  # covers MSVC. Neither needs quoting.
  addIncludePath("CPATH", includeDir)
  addIncludePath("INCLUDE", includeDir)

  exec "nim c --hints:off --path:src -r tests/abi/tabi_layout.nim"

task testLifecycle, "Run lifetime and error-path tests under ORC and ARC":
  # The handle model has to hold under both memory managers, because a
  # destructor that fires at a different time is exactly the kind of difference
  # that turns into a double free. The unit tests need no runtime; the tests
  # under tests/lifecycle do.
  var unitSources: seq[string] = @[]
  collectNimSources("tests/unit", unitSources)
  var runtimeSources: seq[string] = @[]
  collectNimSources("tests/lifecycle", runtimeSources)
  if runtimeSources.len == 0:
    echo "No lifecycle tests found under tests/lifecycle."
    quit(1)

  for memoryManager in ["orc", "arc"]:
    echo "--- memory manager: ", memoryManager, " ---"
    for path in unitSources & runtimeSources:
      exec "nim c --hints:off --path:src --mm:" & memoryManager &
        " -r " & path

task examples, "Build and run every example against the test fixture":
  # Examples are compiled and run, not merely compiled. An example that builds
  # but fails at run time is worse than none, because it looks like a working
  # reference.
  var sources: seq[string] = @[]
  collectNimSources("examples", sources)
  if sources.len == 0:
    echo "No examples found under examples/."
    quit(1)
  for path in sources:
    echo "--- ", path, " ---"
    let arguments =
      if path.endsWith("sync_infer.nim"):
        " tests/fixtures/relu_1x4_f32.xml CPU"
      else:
        ""
    exec "nim c --hints:off --path:src -r " & path & arguments

task testIntegration, "Run the CPU inference loop through the public API":
  # Needs a working runtime with the CPU plugin. Run in both debug and release,
  # because a release build changes bounds checking and object layout, which is
  # where an ownership mistake can start behaving differently.
  var sources: seq[string] = @[]
  collectNimSources("tests/integration", sources)
  if sources.len == 0:
    echo "No integration tests found under tests/integration."
    quit(1)
  for buildMode in ["", "-d:release"]:
    echo "--- build: ", (if buildMode.len == 0: "debug" else: "release"), " ---"
    for path in sources:
      exec "nim c --hints:off --path:src " & buildMode & " -r " & path

task testSmoke, "Load a real OpenVINO runtime and exercise the raw layer":
  # Needs an installed runtime on the loader path, not just the headers. The
  # test itself reports a missing or incomplete runtime as a failure with the
  # full diagnostic, so there is nothing to detect here.
  exec "nim c --hints:off --path:src -r tests/abi/tsmoke_runtime.nim"

task docs, "Generate API documentation for every public module":
  rmDir "build/docs"
  mkDir "build/docs"
  let publicModules = [
    "src/openvino.nim",
    "src/openvino/version.nim",
    "src/openvino/errors.nim",
    "src/openvino/shape.nim",
    "src/openvino/tensor.nim",
    "src/openvino/node.nim",
    "src/openvino/properties.nim",
    "src/openvino/model.nim",
    "src/openvino/compiled_model.nim",
    "src/openvino/infer_request.nim",
    "src/openvino/core.nim",
    "src/openvino/raw.nim"
  ]
  for modulePath in publicModules:
    exec "nim doc --hints:off --index:on --path:src " &
      "--outdir:build/docs " & modulePath
  # Each module writes its own .idx file. Merge those indexes after all pages
  # exist so the generated search page covers the managed and explicit raw
  # surfaces together. `--out` is required by Nim's buildIndex command.
  exec "nim buildIndex --out:build/docs/theindex build/docs"
  cpFile "docs/api-index.html", "build/docs/index.html"

task packagingCheck, "Install into a clean directory and consume it from there":
  # The package is exercised the way a user gets it. Two properties are checked
  # that a test inside the checkout cannot check at all: that the manifest
  # installs the right files, and that `import openvino` resolves for someone
  # who has only the installed package.
  let
    scratch = "build/packaging"
    nimbleDir = scratch & "/nimble"
    consumerDir = scratch & "/consumer"
    fixture = thisDir() & "/tests/fixtures/relu_1x4_f32.xml"
  rmDir scratch
  mkDir nimbleDir
  mkDir consumerDir

  exec "nimble install -y --nimbleDir:" & nimbleDir

  # Copied out of the repository on purpose. Compiling it in place would let
  # the checkout's own paths satisfy the import.
  cpFile "tests/packaging/consumer.nim", consumerDir & "/consumer.nim"

  # No --path:src. The only way `import openvino` can resolve is the install.
  # NimScript has no `ExeExt`, so the suffix is spelled out per platform.
  let exeSuffix = (when defined(windows): ".exe" else: "")
  let binary = consumerDir & "/consumer" & exeSuffix
  exec "nim c --hints:off --nimblePath:" & nimbleDir & "/pkgs2" &
    " --out:" & binary & " " & consumerDir & "/consumer.nim"
  exec binary & " " & fixture

  # What landed in the package. Anything here that is not a Nim source or the
  # manifest metadata means the manifest is shipping something it should not.
  var
    installed: seq[string] = @[]
    unexpected: seq[string] = @[]
  proc collect(dir: string) =
    for path in listFiles(dir):
      installed.add(toRepoPath(path))
    for sub in listDirs(dir):
      collect(sub)
  collect(nimbleDir & "/pkgs2")
  for path in installed:
    if path.endsWith(".nim") or path.endsWith(".nimble") or
        path.endsWith("nimblemeta.json"):
      continue
    unexpected.add(path)
  reportFailures("Unexpected files in the installed package:", unexpected)
  echo "Installed package holds ", installed.len, " files, all sources or " &
    "manifest metadata."

task releaseArchive, "Build and verify the release archives (dry run)":
  # Wraps ci/release-archive.py so the archive naming rule has one
  # implementation shared by this task and the release workflow. The date is
  # read from the environment rather than from a `-d:` flag, because Nimble does
  # not forward those into a task body, and never from the clock, because a name
  # derived from today would differ on every rebuild of the same commit.
  let releaseDate = getEnv("OPENVINO_NIM_RELEASE_DATE")
  if releaseDate.len == 0:
    echo "nimble releaseArchive needs an explicit release date. Set it:"
    echo "  OPENVINO_NIM_RELEASE_DATE=2026-9-24 nimble releaseArchive"
    echo "or on Windows PowerShell:"
    echo "  $env:OPENVINO_NIM_RELEASE_DATE='2026-9-24'; nimble releaseArchive"
    echo "The date is never taken from the clock, so that rebuilding a release"
    echo "from the same commit produces the same file names."
    quit(1)
  exec "python ci/release-archive.py --self-test"
  exec "python ci/release-archive.py --date " & releaseDate &
    " --out-dir build/release --dry-run"

task memcheck, "Run the Linux memory and invalid-access check under valgrind":
  # valgrind is the tool the development plan names. AddressSanitizer was tried
  # first and cannot be used over the OpenVINO call path: it aborts inside its
  # own __cxa_throw interceptor, because the C++ ABI arrives with the dlopened
  # runtime after ASan has installed its interceptors, and OpenVINO throws
  # internally while probing plugins.
  when not defined(linux):
    echo "nimble memcheck runs on Linux only. This is not a skip: the task " &
      "fails so that a run on another platform cannot be mistaken for a pass."
    quit(1)

  let outDir = "build/memcheck"
  rmDir outDir
  mkDir outDir

  # -d:useMalloc matters. Without it Nim serves allocations from its own arena
  # and valgrind sees one large block, so a wrapper that forgets to release
  # would be invisible.
  let common = "--hints:off --path:src --mm:orc -d:useMalloc"
  let valgrind = "valgrind --tool=memcheck --leak-check=full " &
    "--show-leak-kinds=definite --errors-for-leak-kinds=definite " &
    "--error-exitcode=42 --num-callers=25"

  # Two targets, because a leak means something different in each. The first
  # touches only this package's own code, so leak checking is meaningful. The
  # second is one real inference: it covers Core, Model, CompiledModel,
  # InferRequest and Tensor once each without paying for valgrind over a
  # thousand iterations.
  # Names are written out rather than derived from the paths, because
  # NimScript's os subset does not provide splitFile.
  for entry in [("tests/unit/thandle_lifetime.nim", "handles"),
                ("examples/minimal.nim", "inference")]:
    let
      target = entry[0]
      name = entry[1]
      binary = outDir & "/" & name
    exec "nim c " & common & " --out:" & binary & " " & target
    exec valgrind & " --log-file=" & outDir & "/" & name & ".valgrind.txt " &
      binary
  echo "valgrind reported no definite leak and no invalid access. Logs are " &
    "in ", outDir, "."

task releaseCheck, "Verify version metadata is consistent across the repo":
  var failures: seq[string] = @[]
  let
    packageName = stringMetadata("PackageName")
    repositoryName = stringMetadata("RepositoryName")
    packageVersion = stringMetadata("PackageVersion")
    minimumNim = stringMetadata("MinimumNimVersion")
    openVinoVersion = stringMetadata("TargetOpenVinoVersion")
    openVinoTag = stringMetadata("TargetOpenVinoTag")
    expectedPrefix = "2026.4."

  if version != packageVersion:
    failures.add("manifest version '" & version &
      "' does not match PackageVersion '" & packageVersion & "'")

  let
    manifest = readFile("openvino.nimble")
    expectedRequires = "requires \"nim >= " & minimumNim & "\""
    expectedVersion = "version = \"" & packageVersion & "\""
  if not manifest.contains(expectedRequires):
    failures.add("openvino.nimble does not contain the literal '" &
      expectedRequires & "' required by MinimumNimVersion '" &
      minimumNim & "'")
  if not manifest.contains(expectedVersion):
    failures.add("openvino.nimble does not contain the literal '" &
      expectedVersion & "' required by PackageVersion '" &
      packageVersion & "'")

  # Regression guard for a defect found by the packaging test: Nimble copies
  # this manifest into the installed package and re-reads it there, and
  # installation flattens srcDir. A manifest that reads a file under src/ at
  # evaluation time therefore breaks every consumer of the installed package
  # with "cannot open file: src/openvino/version.nim".
  # The needle is assembled at run time so that this guard cannot match its
  # own source line. Writing the call spelling as a literal here would make
  # the check fail against a manifest that is in fact correct.
  let forbiddenCall = "static" & "Read" & "("
  if manifest.contains(forbiddenCall):
    failures.add("openvino.nimble must not read files at evaluation time: " &
      "the installed package has no src/ directory, so evaluating the " &
      "manifest there fails with 'cannot open file'")

  if not openVinoVersion.startsWith(expectedPrefix):
    failures.add("TargetOpenVinoVersion '" & openVinoVersion &
      "' does not match the declared major/minor prefix '" &
      expectedPrefix & "'")

  # The three numeric components must decompose the version string. They are
  # not only bookkeeping: private/library.nim builds the versioned shared
  # library name from them, so a wrong patch number means the package cannot
  # find a pip-installed runtime on Linux.
  let
    versionSource = readFile(versionModule)
    components = openVinoVersion.split('.')
  if components.len != 3:
    failures.add("TargetOpenVinoVersion '" & openVinoVersion &
      "' is not three dot-separated components")
  else:
    for index, name in ["TargetOpenVinoMajor", "TargetOpenVinoMinor",
                        "TargetOpenVinoPatch"]:
      let expected = name & "* = " & components[index]
      if not versionSource.contains(expected):
        failures.add(versionModule & " does not contain '" & expected &
          "' required by TargetOpenVinoVersion '" & openVinoVersion & "'")

  if openVinoTag != openVinoVersion:
    failures.add("TargetOpenVinoTag '" & openVinoTag &
      "' does not match TargetOpenVinoVersion '" & openVinoVersion & "'")

  # Both legal files must exist. LICENSE carries the terms; NOTICE records how
  # this package relates to the upstream C headers and what it does not bundle.
  # A release without either is not one anyone should consume.
  for required in ["LICENSE", "NOTICE", "RELEASE_NOTES.md"]:
    if not fileExists(required):
      failures.add(required & " is missing")

  let changelog = readFile("CHANGELOG.md")
  if not changelog.contains("## " & packageVersion):
    failures.add("CHANGELOG.md has no '## " & packageVersion & "' section")

  let
    readme = readFile("README.md")
    displayName = stringMetadata("ProjectDisplayName")
  for needle in [displayName, repositoryName, packageName, packageVersion,
                 openVinoVersion]:
    if not readme.contains(needle):
      failures.add("README.md does not mention '" & needle & "'")

  # The repository's public identity matches the display name exactly. Release
  # archives remain lowercase because they are consumed by package and file
  # system tooling with different case rules.
  if repositoryName != displayName:
    failures.add("RepositoryName '" & repositoryName &
      "' must exactly match ProjectDisplayName '" & displayName & "'")
  if displayName == packageName:
    failures.add("ProjectDisplayName and PackageName must differ; the first " &
      "is for reading and the second is what tools consume")
  if packageName != packageName.toLowerAscii():
    failures.add("PackageName '" & packageName & "' must be lowercase, " &
      "because file systems, URLs and package indexes disagree about case")

  reportFailures("Release metadata inconsistencies:", failures)
  echo "Release metadata consistent: ", packageName, " ", packageVersion,
    " against OpenVINO ", openVinoVersion, "."
