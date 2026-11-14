# OpenVINO GenAI implementation audit

This audit records the implementation boundary and evidence for GenAI support
in package version 0.2.2. The pinned upstream release is OpenVINO GenAI
`2026.4.1.0`, tag `2026.4.1.0`, commit
`ab01d1771e4adaa0e1e08e9d630def170572506c`, paired with the OpenVINO Runtime
`2026.4.1` baseline.

## Scope

The eight functional GenAI C headers expose text generation and chat,
generation settings, visual-language generation, Whisper transcription,
JSON/chat containers and performance metrics. All 153 declared function
symbols are listed in `GenAiApiSymbols`; 150 fixed-signature functions use
lazy dynamic bindings, and the three variadic pipeline constructors are
invoked through a private C adapter. The managed API is documented in
[the GenAI guide](genai.md), with raw declarations under
`openvino/raw/genai`.

The C++ GenAI API has additional families without matching functions in these
C headers, including image/video generation, speech generation, embeddings and
reranking. They are outside this release's binding scope. “Complete” in the
release notes refers to the pinned C API surface, not all C++ GenAI features.

## Deployment and ABI

The official Linux `openvino-genai` 2026.4.1.0 Python wheel used during
implementation contains `libopenvino_genai.so.2641` but not a separate
`openvino_genai_c` library. The binding therefore requires a GenAI distribution
that includes `openvino_genai_c`, or a local build of that target from the
matching upstream source. It also requires matching GenAI, Runtime and
OpenVINO Tokenizers libraries. The C runtime loads lazily and independently;
importing `openvino` remains usable without the optional library.

The three upstream pipeline constructors take C varargs. Nim does not declare
these as C varargs: `private/genai_bridge.nim` supplies a small C adapter with
a documented maximum of 16 string property pairs. Managed C strings reject
embedded NUL characters before they reach the native boundary.

The upstream C wrapper often translates caught C++ exceptions to
`UNKNOW_EXCEPTION` (`-17`). The original C++ diagnostic is unavailable in that
case. The new standalone Whisper config's `validate()` also returned `-17`
during local validation even though the same configuration worked in real
transcription; validation behaviour is left to the upstream library and is not
claimed as a tested success.

## Verification

On Linux x86_64, `nimble testGenAi` passed under ORC and ARC using matching
2026.4.1 runtime, GenAI and Tokenizers libraries, a TinyLlama 1.1B INT4 model,
and an OpenVINO Whisper Tiny model. It resolved all 153 symbols, exercised
settings, JSON/chat history, LLM text and streaming generation, callback stop
and error handling, property forwarding, transcription, chunks, scores and
metrics. Whisper returned the expected phrase from the bundled test audio.

VLM symbols and wrappers compile and resolve, but VLM generation has not yet
been run against a real model. Windows, macOS, GPU and NPU GenAI execution have
not been verified. See [C API coverage](c-api-coverage.md) for test detail and
the [GenAI guide](genai.md) for runtime setup.
