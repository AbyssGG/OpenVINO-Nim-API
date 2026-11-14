# OpenVINO GenAI

`openvino/genai` is an optional managed API for the OpenVINO GenAI C API. It
loads independently from the core OpenVINO Runtime, so importing `openvino`
does not require the GenAI library to be installed. The first GenAI operation
loads `openvino_genai_c` and reports a `GenAiLibraryError` if it is missing or
incompatible.

The binding tracks OpenVINO GenAI `2026.4.1.0`, upstream tag
[`2026.4.1.0`](https://github.com/openvinotoolkit/openvino.genai/tree/2026.4.1.0),
commit `ab01d1771e4adaa0e1e08e9d630def170572506c`. All 153 functions in its
C headers are represented: 150 fixed-signature functions are dynamically
bound, and the three variadic pipeline constructors use a small C ABI bridge
that accepts up to 16 string property pairs. The corresponding raw bindings are
under `openvino/raw/genai`; they are explicitly imported and do not get
re-exported from `openvino`.

## Runtime requirements

Install matching OpenVINO Runtime, GenAI, and OpenVINO Tokenizers components.
The GenAI C API is a separate shared library, `openvino_genai_c`; check that
your GenAI distribution includes it. The upstream Python wheel used during
implementation did not include this C library, so on Linux you may need a
GenAI distribution that packages it or build the `openvino_genai_c` target
from the matching upstream source. Keep the GenAI C++, Runtime, and Tokenizers
libraries on the platform loader path as well.
The upstream [2026.4.1.0 build guide](https://github.com/openvinotoolkit/openvino.genai/blob/2026.4.1.0/src/docs/BUILD.md)
documents source builds; the C library is installed as the `core_c_genai`
component.

The loader checks `OPENVINO_GENAI_C_LIBRARY` first, then platform defaults. A
compile-time path can be set with `-d:openvinoGenAiLib=/full/path/to/library`.
The Tokenizers plugin is selected by the OpenVINO GenAI runtime through
`OPENVINO_TOKENIZERS_PATH_GENAI`; this package does not download or select a
plugin for you.

| Platform | Default GenAI C library name |
|---|---|
| Windows | `openvino_genai_c.dll` |
| Linux | `libopenvino_genai_c.so`, then `libopenvino_genai_c.so.2641` and earlier `2026.4` patch SONAMEs |
| macOS | `libopenvino_genai_c.dylib` |

The library candidates are implemented, but this project has only run the
GenAI runtime tests on Linux x86_64. Windows and macOS GenAI loading and
execution have not been verified.

## Text generation and chat

```nim
import openvino

let pipeline = newLlmPipeline("models/TinyLlama", "CPU")
let settings = newGenerationConfig()
settings.setMaxNewTokens(64)
settings.setDoSample(false)
settings.validate()

let response = pipeline.generate("Explain OpenVINO in one sentence.", settings)
echo response.text()

let streamed = pipeline.streamGenerate(
  "Give one short example.",
  proc (piece: string): StreamAction =
    stdout.write(piece)
    streamContinue,
  settings)

echo "\nComplete streamed result: ", streamed
```

The synchronous generation call blocks the calling thread. A stream handler
runs synchronously from inside that call. It may return `streamContinue`,
`streamStop`, or `streamCancel`. If the handler raises a Nim `CatchableError`,
the callback contains it at the C boundary, stops generation, and raises a
`GenAiCallbackError` after the native call returns; `callbackMessage` carries
the original message.

`ChatHistory` stores messages as `JsonContainer` values. Each message should be
a JSON object with the keys expected by the model's chat template, commonly
`role` and `content`. The history also accepts tool definitions and extra JSON
context. Pass a history to `generate` or `streamGenerate` for structured chat.

`GenerationConfig` exposes every setting from the C API, including token
limits, stop strings and IDs, beam search, sampling, penalties, and assistant
draft controls. Generation results can return their `PerfMetrics` for token
counts, latency, throughput, tokenization and detokenization timings.

## Vision and speech

`VlmPipeline` accepts text and OpenVINO image tensors. The upstream C example
creates RGB images as U8 tensors shaped `[1, height, width, 3]`; keep each
`Tensor` open for the full generation call. `Tensor.unsafeNativeHandle()` is a
borrowed C pointer and does not transfer ownership. VLM generation accepts
multiple images, structured history, generation settings and streaming.

```nim
import openvino

let image = tensorFrom(etU8, initShape(1, height, width, 3), rgbBytes)
let pipeline = newVlmPipeline("models/vision-language", "CPU")
let response = pipeline.generate("Describe this picture.", [image])
echo response.text()
```

See the upstream [C image-loading sample](https://github.com/openvinotoolkit/openvino.genai/blob/2026.4.1.0/samples/c/visual_language_chat/load_image.c)
for its input tensor layout.

`WhisperPipeline.transcribe` accepts audio as `openArray[float32]`. Supply
normalized mono samples at 16 kHz. `WhisperGenerationConfig` supports language,
transcription/translation task, timestamps, prompts, hotwords, token IDs and
suppress-token lists. Results provide text candidates, scores, timestamped
chunks and performance metrics.

```nim
import openvino

let speech = newWhisperPipeline("models/whisper-tiny", "CPU")
let settings = newWhisperGenerationConfig()
settings.setLanguage("en")
settings.setTask("transcribe")
settings.setReturnTimestamps(true)
let result = speech.transcribe(samples, settings)
echo result.transcription()
for index in 0 ..< result.chunkCount():
  let chunk = result.chunkAt(index)
  echo chunk.chunkTimestamps(), " ", chunk.chunkText()
```

The C API accepts already prepared image tensors and audio samples. It does not
provide image-file loading, audio-file decoding, resampling, or normalization;
applications supply those steps.

## C API boundary

This is complete coverage of the pinned upstream **C** API, not of every C++
class in OpenVINO GenAI. The upstream C headers audited here provide text and
chat generation, VLM, Whisper, generation configs, JSON/chat containers and
metrics. Image/video generation, speech generation, embeddings/reranking, and
other C++-only pipeline families have no equivalent in those headers and are
not exposed by this release. The raw layer is available for the C functions
that do not yet have a managed convenience wrapper:

```nim
import openvino/raw/genai
```

C status codes from `GenAiError` retain their numeric value. The upstream C
wrapper catches C++ exceptions and often maps them to `UNKNOW_EXCEPTION`
(`-17`); in those cases the original C++ diagnostic is not available to Nim.

## Tests

The runtime-free import and ABI-surface checks run with `nimble test`. To run
real LLM and Whisper tests on CPU, set these variables before `nimble
testGenAi`:

```shell
export OPENVINO_GENAI_TEST_MODEL=/path/to/openvino-llm-model
export OPENVINO_GENAI_TEST_WHISPER_MODEL=/path/to/openvino-whisper-model
export OPENVINO_GENAI_TEST_AUDIO_F32=/path/to/mono-16khz-float32-pcm
export OPENVINO_TOKENIZERS_PATH_GENAI=/path/to/libopenvino_tokenizers.so
# Optional when the library is not on the dynamic loader path:
export OPENVINO_GENAI_C_LIBRARY=/path/to/libopenvino_genai_c.so
nimble testGenAi
```

The integration task checks every exported C symbol, JSON/chat ownership,
LLM text/history/streaming/property forwarding, Whisper transcription/chunks,
and runs under both ORC and ARC. It requires a local OpenVINO IR model and a
raw little-endian float32 audio sample file; tests do not download models.

The current real-model integration suite has been run on Linux x86_64 with
OpenVINO/GenAI/Tokenizers `2026.4.1` on CPU. It covers LLM and Whisper. The VLM
API is compiled and its C symbols are checked, but has not yet been exercised
against a real VLM model in this project.
