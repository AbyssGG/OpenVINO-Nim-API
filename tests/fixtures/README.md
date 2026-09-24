# Test fixtures

Small, deterministic, offline models used by the integration tests. Nothing here
is downloaded at test time, and nothing here is a real-world model.

## Why these are hand-written

Every fixture in this directory is written by hand as OpenVINO IR XML rather
than exported from a training framework. Three reasons:

- **Licensing is unambiguous.** A hand-written fixture is original work under
  this project's Apache-2.0 licence, so the package can be distributed without
  tracing a model's provenance.
- **The expected output is obvious.** A reviewer can compute it mentally, so a
  wrong answer is recognisable rather than merely different from last time.
- **Reproducibility needs no tooling.** The file *is* the definition. There is
  no generation script to keep working, and no framework version to pin.

## `relu_1x4_f32.xml`

| Property | Value |
|---|---|
| Format | OpenVINO IR, `version="11"` |
| Weights file | None. ReLU has no parameters, so no `.bin` accompanies it |
| Input | `input`, `f32`, shape `[1, 4]` |
| Output | `output`, `f32`, shape `[1, 4]` |
| Computation | `output[i] = max(0, input[i])` |
| SHA-256 | `6c6964e587043bd9d019d04b5add518cab38818cafd07af50c7f206e9b3afda9` |
| Size | 961 bytes, LF line endings |
| Origin | Written for this project. Original work, Apache-2.0 |

The digest is of the file with LF endings, which is what `.gitattributes`
normalises every checkout to. A checkout that converted this file to CRLF would
produce a different digest, and `nimble checkFixtures` would say so.

Nodes: `Parameter` → `ReLU` → `Result`.

ReLU was chosen over an identity model because an identity model cannot
distinguish "inference ran" from "the output tensor happens to hold the input".
It was chosen over a multiply-by-constant because a `Const` node needs a binary
weights file, and a fixture that is one self-contained text file is easier to
review and impossible to desynchronise.

The value used by `tests/integration/tcpu_inference.nim`:

```text
input    [-1.5,  2.0, -0.25,  4.0]
expected [ 0.0,  2.0,  0.0,   4.0]
```

Both negative values must become exactly zero and both positive values must pass
through bit-identically. An implementation that transposed, scaled or reordered
anything would fail on this input, which is why the values include two signs and
a fraction rather than four positive integers.

## Adding a fixture

A new fixture needs, in this file: a `## ` heading naming the file, its format,
every input and output with shape and element type, the computation in one line,
a `| SHA-256 | ...backticked digest... |` table row, its origin and licence, and
the exact expected output for the input the test uses.

`nimble checkFixtures` enforces the mechanical half of that: it recomputes every
recorded digest, fails on a file in this directory that no heading describes, and
fails on a heading that describes a file which is not here. It does not read
English, so the format, computation and licence lines are still a reviewer's job.

Do not add a real-world model, a set of trained weights, a compiled blob or
anything whose licence would restrict redistribution. A compiled blob in
particular is tied to one device, one runtime version and one set of hardware
capabilities, so it would not be deterministic across the machines that run
these tests.
