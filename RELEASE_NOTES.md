# OpenVINO Nim API 0.2.2

This release adds optional GenAI support and fixes correctness issues in the
community-maintained Nim bindings for the OpenVINO Runtime and GenAI C APIs.

## Added

- Raw declarations for all 150 fixed-signature functions in OpenVINO GenAI
  `2026.4.1.0` C headers, tracking of all 153 C symbols, and a C adapter for
  the three variadic pipeline constructors.
- Managed LLM text/chat generation, synchronous streaming, VLM generation,
  Whisper transcription, generation settings, JSON/chat history, results and
  performance metrics.
- Lazy GenAI library loading and a C adapter for its variadic pipeline
  constructors. Core `import openvino` continues to work without GenAI installed.
- Real-model integration tests for LLM and Whisper under ORC and ARC.
- Correct handling of an empty stop-string list and embedded NUL strings.

## Fixes

- Report request-returned tensor storage ownership as unknown unless the
  runtime contract guarantees ownership.
- Reject embedded NUL characters across GenAI inputs instead of silently
  truncating strings at the C boundary.
- Carry forward the 0.2.1 fixes: reject tensor byte copies containing Nim
  references, validate negative shape dimensions even with zero dimensions,
  reject embedded NUL in existing C-bound strings, and guard long timeout
  deadline arithmetic.

## Compatibility

The package targets OpenVINO Runtime `2026.4.1` and GenAI `2026.4.1.0`, and
requires Nim `2.0.0` or newer. Real GenAI execution was tested on Linux x86_64
CPU for LLM and Whisper. VLM, Windows/macOS, GPU and NPU GenAI remain unverified.
This release covers the upstream GenAI **C API**; C++-only image/video
generation, speech generation, embeddings and reranking are outside its scope.
See [the compatibility matrix](docs/compatibility.md) and [GenAI guide](docs/genai.md).

For the complete change list, see [CHANGELOG.md](CHANGELOG.md).
