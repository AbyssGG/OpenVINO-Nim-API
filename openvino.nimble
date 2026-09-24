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

  legacyPrototypePaths = [
    "src/resonance.nim",
    "src/resonance",
    "examples/basic_infer.nim",
    "resonance.nimble"
  ]
    ## Resonance prototype files that the migration replaces rather than
    ## adapts. They are excluded from formatting and style checking on
    ## purpose: reformatting code that is scheduled for deletion would
    ## create an unrelated bulk diff and hide the real migration. `lint`
    ## names them explicitly so the exclusion is never silent.

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

# The Resonance prototype still lives under srcDir until Phase 2 replaces it.
# Without these exclusions `nimble install` ships it inside the installed
# package, where `import resonance` would hand a consumer the binding whose
# ABI defects are catalogued in docs/resonance-audit.md, and which does not
# compile on Linux at all.
#
# These paths are relative to the package root and therefore keep the `src/`
# prefix, even though installation flattens srcDir away. Spelling them
# relative to srcDir silently skips nothing.
#
# Remove both lines when src/resonance is deleted.
skipDirs = @["src/resonance"]
skipFiles = @["src/resonance.nim"]

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

  reportFailures("Lint failures:", failures)

  # Markdown rules are checked by a Nim tool so that lint needs no toolchain
  # beyond the pinned Nim. It exits non-zero on any violation.
  exec "nim r --hints:off tools/mdcheck.nim"

  echo "Lint passed for ", sources.len, " Nim files."

task test, "Run unit tests that do not require an OpenVINO runtime":
  var sources: seq[string] = @[]
  collectNimSources("tests/unit", sources)
  if sources.len == 0:
    echo "No unit tests found under tests/unit."
    quit(1)
  for path in sources:
    exec "nim c --hints:off --path:src -r " & path

task docs, "Generate API documentation for the public entry point":
  mkDir "build/docs"
  exec "nim doc --hints:off --project --index:on --path:src " &
    "--outdir:build/docs src/openvino.nim"

task releaseCheck, "Verify version metadata is consistent across the repo":
  var failures: seq[string] = @[]
  let
    packageName = stringMetadata("PackageName")
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

  if openVinoTag != openVinoVersion:
    failures.add("TargetOpenVinoTag '" & openVinoTag &
      "' does not match TargetOpenVinoVersion '" & openVinoVersion & "'")

  let changelog = readFile("CHANGELOG.md")
  if not changelog.contains("## " & packageVersion):
    failures.add("CHANGELOG.md has no '## " & packageVersion & "' section")

  let readme = readFile("README.md")
  for needle in [packageName, packageVersion, openVinoVersion]:
    if not readme.contains(needle):
      failures.add("README.md does not mention '" & needle & "'")

  reportFailures("Release metadata inconsistencies:", failures)
  echo "Release metadata consistent: ", packageName, " ", packageVersion,
    " against OpenVINO ", openVinoVersion, "."
