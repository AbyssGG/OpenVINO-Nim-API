# SPDX-License-Identifier: Apache-2.0

## Markdown structure checker for this repository.
##
## Enforces the mechanically checkable rules from `STYLE_GUIDE.md`: exactly
## one ATX H1 per document, balanced fenced code blocks, a language tag on
## every fence, LF line endings, a final newline and no placeholder link
## text. Content inside fenced blocks is skipped, so a document that shows
## sample Markdown cannot trip the heading rule.
##
## This tool is deliberately written in Nim rather than a scripting language
## so that `nimble lint` needs no toolchain beyond the one the package
## already requires. It is a development tool and is not part of the
## published package surface.
##
## Exits with status 1 when any document fails, printing every problem it
## found rather than stopping at the first one.

import std/[algorithm, os, strutils]

const
  fence = "```"
    ## Opening and closing marker of a fenced code block.

  vagueLinkTexts = ["[click here](", "[here](", "[this]("]
    ## Link texts that describe the act of clicking instead of the
    ## destination.

  skippedDirs = [".git", ".nim_runtime", "build", "nimcache", "htmldocs"]
    ## Directories that never contain repository documentation. Pruning them
    ## keeps the walk fast and avoids reporting vendored or generated text.
    ## setup-nim-action installs its toolchain under `.nim_runtime` in CI; its
    ## bundled Markdown belongs to Nim, not to this repository.

  devlogPath = "DEVLOG.md"
    ## Bilingual development log, checked for entry parity between its two
    ## language halves.

  readmePath = "README.md"
  readmeExample = "examples/minimal.nim"
    ## The README's Nim example must be the same code as this file, which
    ## `nimble examples` compiles and runs. A README snippet that nothing
    ## compiles is the first thing a reader tries and the last thing anyone
    ## updates.

  devlogEnglishHeading = "## English"
  devlogChineseHeading = "## 中文"
  devlogEntryPrefix = "### "

type Problem = tuple[line: int, message: string]
  ## A single finding. `line` is 0 for whole-file problems.

proc collectMarkdown(dir: string, acc: var seq[string]) =
  ## Appends every Markdown file below `dir` to `acc`, pruning
  ## `skippedDirs`.
  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      if path.endsWith(".md"):
        acc.add(path)
    of pcDir:
      if lastPathPart(path) notin skippedDirs:
        collectMarkdown(path, acc)
    else:
      discard

proc checkFileShape(raw: string, problems: var seq[Problem]) =
  ## Records whole-file problems: line endings and the trailing newline.
  if raw.contains("\r\n"):
    problems.add((0, "uses CRLF line endings, expected LF"))
  if raw.len == 0:
    problems.add((0, "is empty"))
  elif raw[^1] != '\n':
    problems.add((0, "missing final newline"))

proc checkMarkdown(path: string): seq[Problem] =
  ## Returns every problem found in the document at `path`.
  result = @[]
  let raw = readFile(path)
  checkFileShape(raw, result)

  var
    inFence = false
    fenceOpenLine = 0
    headingCount = 0
    lineNumber = 0
  for line in raw.splitLines():
    inc lineNumber
    if line.startsWith(fence):
      if inFence:
        inFence = false
      else:
        inFence = true
        fenceOpenLine = lineNumber
        if line.strip() == fence:
          result.add((lineNumber, "fenced code block has no language tag"))
      continue
    if inFence:
      continue
    if line.startsWith("# "):
      inc headingCount
    let lowered = line.toLowerAscii()
    for vague in vagueLinkTexts:
      if lowered.contains(vague):
        result.add((lineNumber, "non-descriptive link text " & vague))

  if inFence:
    result.add((fenceOpenLine, "unclosed fenced code block"))
  if headingCount != 1:
    result.add((0, "has " & $headingCount & " H1 headings, expected exactly 1"))

proc checkDevlogParity(raw: string): seq[Problem] =
  ## Verifies that the bilingual development log carries the same number of
  ## entries in its English and Chinese halves.
  ##
  ## The log is split by language rather than interleaved, which keeps heading
  ## names unique but invites the two halves to drift. Counting entries is a
  ## cheap guard: it cannot prove the entries say the same thing, but it does
  ## catch an entry added to one half and forgotten in the other.
  result = @[]
  var
    inFence = false
    english = -1
    chinese = -1
  for line in raw.splitLines():
    if line.startsWith(fence):
      inFence = not inFence
      continue
    if inFence:
      continue
    if line.startsWith(devlogEnglishHeading):
      english = 0
      continue
    if line.startsWith(devlogChineseHeading):
      chinese = 0
      continue
    if not line.startsWith(devlogEntryPrefix):
      continue
    if chinese >= 0:
      inc chinese
    elif english >= 0:
      inc english

  if english < 0:
    result.add((0, "missing the '" & devlogEnglishHeading & "' half"))
  if chinese < 0:
    result.add((0, "missing the '" & devlogChineseHeading & "' half"))
  if english <= 0 and chinese <= 0:
    return
  if english != chinese:
    result.add((0, "has " & $english & " English entries but " & $chinese &
      " Chinese entries; both halves must be updated together"))

proc checkLocalLinks(path, raw: string): seq[Problem] =
  ## Verifies that every relative Markdown link points at a file that exists.
  ##
  ## Relative links resolve against the directory of the document that contains
  ## them, which is the mistake this catches: writing `docs/ownership.md` inside
  ## a file that already lives in `docs/` looks right and resolves to
  ## `docs/docs/ownership.md`.
  ##
  ## External links are not fetched. A link checker that reaches the network
  ## fails for reasons that have nothing to do with the change under review.
  result = @[]
  let directory = parentDir(path)
  var
    inFence = false
    lineNumber = 0
  for line in raw.splitLines():
    inc lineNumber
    if line.startsWith(fence):
      inFence = not inFence
      continue
    if inFence:
      continue

    # Inline code spans are removed first. A Nim signature such as
    # `newTensor[T](shape)` contains the `](` that starts a link target, and
    # reading it as a link would report a missing file named `shape`. That was
    # not hypothetical: it is what the first version of this check did.
    var scanned = ""
    var inCode = false
    for character in line:
      if character == '`':
        inCode = not inCode
        continue
      if not inCode:
        scanned.add(character)

    var searchFrom = 0
    while true:
      let open = scanned.find("](", searchFrom)
      if open < 0:
        break
      let close = scanned.find(')', open + 2)
      if close < 0:
        break
      searchFrom = close + 1
      var target = scanned[open + 2 ..< close].strip()
      if target.len == 0:
        result.add((lineNumber, "link with an empty target"))
        continue
      # Anchors, protocols and mail links are out of scope.
      if target.startsWith('#') or target.contains("://") or
          target.startsWith("mailto:"):
        continue
      let hash = target.find('#')
      if hash >= 0:
        target = target[0 ..< hash]
      if target.len == 0:
        continue
      let resolved = directory / target
      if not fileExists(resolved) and not dirExists(resolved):
        result.add((lineNumber, "link target does not exist: " & target &
          " (resolved to " & resolved & ")"))

proc codeLines(source: string): seq[string] =
  ## Returns `source` reduced to its code: blank lines and whole-line comments
  ## dropped, and the rest stripped of trailing space.
  ##
  ## Comments are ignored on purpose. The example file carries a licence header
  ## and documentation comments that would be noise in a README, so requiring
  ## byte equality would force one of the two to carry text that does not belong
  ## there. The code itself must match exactly.
  result = @[]
  for line in source.splitLines():
    let trimmed = line.strip(leading = false)
    if trimmed.len == 0 or trimmed.strip().startsWith("#"):
      continue
    result.add(trimmed)

proc extractNimBlocks(raw: string): seq[string] =
  ## Returns the contents of every fenced block tagged `nim`.
  result = @[]
  var
    inBlock = false
    current = ""
  for line in raw.splitLines():
    if line.startsWith(fence):
      if inBlock:
        result.add(current)
        current = ""
        inBlock = false
      elif line.strip() == fence & "nim":
        inBlock = true
      continue
    if inBlock:
      current.add(line)
      current.add('\n')

proc checkReadmeExample(): seq[Problem] =
  ## Verifies that the README's Nim example is the code in
  ## `examples/minimal.nim`.
  result = @[]
  if not fileExists(readmeExample):
    result.add((0, readmeExample & " is missing, so the README example in it " &
      "cannot be compiled by anything"))
    return
  let blocks = extractNimBlocks(readFile(readmePath))
  if blocks.len == 0:
    result.add((0, "has no fenced `nim` block; the minimal example is required"))
    return

  let expected = codeLines(readFile(readmeExample))
  for candidate in blocks:
    if codeLines(candidate) == expected:
      return
  result.add((0, "its Nim example does not match the code in " & readmeExample &
    "; run `nimble examples` and copy the working file into the README"))

proc main() =
  var paths: seq[string] = @[]
  collectMarkdown(".", paths)
  sort(paths)

  var
    failed = false
    sawDevlog = false
  for path in paths:
    var problems = checkMarkdown(path)
    problems.add(checkLocalLinks(path, readFile(path)))
    if lastPathPart(path) == devlogPath:
      sawDevlog = true
      problems.add(checkDevlogParity(readFile(path)))
    if path == "." & DirSep & readmePath:
      problems.add(checkReadmeExample())
    if problems.len == 0:
      continue
    failed = true
    echo "FAIL ", path
    for problem in problems:
      if problem.line == 0:
        echo "    ", problem.message
      else:
        echo "    line ", problem.line, ": ", problem.message

  if not sawDevlog:
    echo "FAIL ", devlogPath
    echo "    is required but was not found"
    failed = true

  echo "Checked ", paths.len, " Markdown files."
  if failed:
    quit(1)

main()
