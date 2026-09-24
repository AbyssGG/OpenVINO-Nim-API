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

  skippedDirs = [".git", ".kiro", "build", "nimcache", "htmldocs"]
    ## Directories that never contain repository documentation. Pruning them
    ## keeps the walk fast and avoids reporting vendored or generated text.

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

proc main() =
  var paths: seq[string] = @[]
  collectMarkdown(".", paths)
  sort(paths)

  var failed = false
  for path in paths:
    let problems = checkMarkdown(path)
    if problems.len == 0:
      continue
    failed = true
    echo "FAIL ", path
    for problem in problems:
      if problem.line == 0:
        echo "    ", problem.message
      else:
        echo "    line ", problem.line, ": ", problem.message

  echo "Checked ", paths.len, " Markdown files."
  if failed:
    quit(1)

main()
