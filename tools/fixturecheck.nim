# SPDX-License-Identifier: Apache-2.0

## Verifies that `tests/fixtures/README.md` describes the fixtures that are
## actually on disk, and that each recorded SHA-256 is the file's real digest.
##
## Why this exists: the fixture documentation carried a checksum that had been
## written down without ever being computed, and it was wrong. A documented
## digest that nothing verifies is worse than no digest, because a reader will
## trust it. This tool closes that loop, and `nimble lint` runs it.
##
## It checks in both directions. An undocumented fixture fails, so a file
## cannot be added to the directory without saying what it is; a documented
## fixture that is missing fails too, so a deleted file cannot leave stale
## documentation behind.
##
## The SHA-256 implementation it depends on is verified against the published
## FIPS 180-4 test vectors before any fixture is hashed, so a broken
## implementation reports itself rather than agreeing with an equally broken
## expectation.
##
## Exits with status 1 on any failure, after reporting all of them.

import std/[algorithm, os, strutils]

import sha256

const
  fixtureDir = "tests/fixtures"
  fixtureDoc = fixtureDir & "/README.md"
  digestLabel = "SHA-256"
  hashDigits = 64

  documentationOnly = ["README.md"]
    ## Files in the fixture directory that are documentation rather than
    ## fixtures, and so are not themselves expected to be documented.

  testVectors = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    ("abc",
     "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")]
    ## Published SHA-256 vectors. The third spans more than one block after
    ## padding, which is where a mistake in the block loop or the length
    ## encoding shows up; a single-block vector alone would not catch it.

type Fixture = object
  ## One fixture as the documentation describes it.
  name: string
  digest: string
  docLine: int

proc parseHashCell(cell: string): string =
  ## Extracts a hexadecimal digest from a Markdown table cell, which spells it
  ## inside backticks. Returns an empty string when the cell holds no digest.
  let backtick = cell.find('`')
  if backtick < 0:
    return ""
  let closing = cell.find('`', backtick + 1)
  if closing < 0:
    return ""
  cell[backtick + 1 ..< closing].strip().toLowerAscii()

proc parseFixtureDoc(problems: var seq[string]): seq[Fixture] =
  ## Reads the fixture documentation and returns every fixture it describes.
  ##
  ## A fixture is an `## `-level heading naming a file, followed by a table row
  ## whose first cell is `SHA-256`. Parsing the document this way means the
  ## documentation stays the thing a human reads, rather than being generated
  ## from a machine-readable file that nobody reviews.
  result = @[]
  if not fileExists(fixtureDoc):
    problems.add(fixtureDoc & " is missing")
    return

  var
    inFence = false
    lineNumber = 0
  for line in readFile(fixtureDoc).splitLines():
    inc lineNumber
    if line.startsWith("```"):
      inFence = not inFence
      continue
    if inFence:
      continue

    if line.startsWith("## "):
      let heading = line[3 .. ^1].strip().strip(chars = {'`'})
      if fileExists(fixtureDir & "/" & heading) or heading.contains('.'):
        result.add(Fixture(name: heading, digest: "", docLine: lineNumber))
      continue

    if not line.startsWith("|"):
      continue
    let cells = line.strip(chars = {'|', ' '}).split('|')
    if cells.len < 2 or cells[0].strip() != digestLabel:
      continue
    if result.len == 0:
      problems.add(fixtureDoc & ":" & $lineNumber & ": a " & digestLabel &
        " row appears before any fixture heading")
      continue
    let digest = parseHashCell(cells[1])
    if digest.len == 0:
      problems.add(fixtureDoc & ":" & $lineNumber & ": the " & digestLabel &
        " cell holds no digest in backticks")
      continue
    if result[^1].digest.len > 0:
      problems.add(fixtureDoc & ":" & $lineNumber & ": a second " &
        digestLabel & " row for '" & result[^1].name & "'")
      continue
    result[^1].digest = digest

proc actualFixtures(problems: var seq[string]): seq[string] =
  ## Returns the names of the files in the fixture directory, documentation
  ## excluded.
  result = @[]
  if not dirExists(fixtureDir):
    problems.add(fixtureDir & " does not exist")
    return
  for kind, path in walkDir(fixtureDir):
    if kind != pcFile:
      continue
    let name = lastPathPart(path)
    if name notin documentationOnly:
      result.add(name)
  sort(result)

proc verifyImplementation() =
  ## Hashes the published test vectors and aborts on any mismatch.
  for vector in testVectors:
    let (message, expected) = vector
    let produced = sha256Hex(message)
    if produced != expected:
      echo "FAIL tools/sha256.nim does not match a published test vector."
      echo "    input length : ", message.len, " bytes"
      echo "    expected     : ", expected
      echo "    produced     : ", produced
      quit(1)
  echo "SHA-256 implementation matches ", testVectors.len,
    " published test vectors."

proc main() =
  verifyImplementation()

  var problems: seq[string] = @[]
  let
    documented = parseFixtureDoc(problems)
    present = actualFixtures(problems)

  var documentedNames: seq[string] = @[]
  for fixture in documented:
    documentedNames.add(fixture.name)

  for fixture in documented:
    let path = fixtureDir & "/" & fixture.name
    if not fileExists(path):
      problems.add(fixtureDoc & ":" & $fixture.docLine & ": documents '" &
        fixture.name & "', which does not exist")
      continue
    if fixture.digest.len == 0:
      problems.add(fixtureDoc & ":" & $fixture.docLine & ": '" &
        fixture.name & "' has no " & digestLabel & " row")
      continue
    if fixture.digest.len != hashDigits:
      problems.add(fixtureDoc & ":" & $fixture.docLine & ": '" &
        fixture.name & "' records a digest of " & $fixture.digest.len &
        " characters, expected " & $hashDigits)
      continue
    let actual = sha256Hex(readFile(path))
    if actual != fixture.digest:
      problems.add(path & ": recorded digest does not match the file\n" &
        "      recorded: " & fixture.digest & "\n" &
        "      actual  : " & actual)
      continue
    echo "  ", fixture.name, "  ", actual

  for name in present:
    if name notin documentedNames:
      problems.add(fixtureDir & "/" & name &
        " is not documented in " & fixtureDoc &
        "; every fixture needs its format, shapes, digest and origin recorded")

  if problems.len > 0:
    echo "Fixture check failures:"
    for problem in problems:
      echo "    ", problem
    quit(1)

  echo "Verified ", documented.len, " fixture(s) against ", fixtureDoc, "."

main()
