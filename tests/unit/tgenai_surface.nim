# SPDX-License-Identifier: Apache-2.0

## Compile-only contract tests for the optional GenAI surface.
##
## Importing either public entry point must not attempt to load optional native
## libraries. Native behaviour is covered by `nimble testGenAi`.

import std/unittest

import openvino
import openvino/raw/genai as rawGenAi

suite "optional GenAI public surface":
  test "the managed import remains available without GenAI loading":
    check PackageVersion.len > 0

  test "the streaming statuses match the C ABI values":
    check int(rawGenAi.OV_GENAI_STREAMING_STATUS_RUNNING) == 0
    check int(rawGenAi.OV_GENAI_STREAMING_STATUS_STOP) == 1
    check int(rawGenAi.OV_GENAI_STREAMING_STATUS_CANCEL) == 2

  test "the complete upstream C symbol list includes constructors":
    check rawGenAi.GenAiApiSymbols.len == 153
    check "ov_genai_llm_pipeline_create" in rawGenAi.GenAiApiSymbols
    check "ov_genai_vlm_pipeline_create" in rawGenAi.GenAiApiSymbols
    check "ov_genai_whisper_pipeline_create" in rawGenAi.GenAiApiSymbols

  test "the optional loader has platform candidates without loading them":
    check rawGenAi.candidateGenAiLibraries().len > 0

  test "managed GenAI rejects embedded NUL before loading native libraries":
    expect OpenVinoArgumentError:
      discard newLlmPipeline("model\0truncated")
    expect OpenVinoArgumentError:
      discard newLlmPipeline("model", "CPU", @[("bad\0key", "value")])
    expect OpenVinoArgumentError:
      discard newLlmPipeline("model", "CPU",
        newSeq[(string, string)](17))
    expect OpenVinoArgumentError:
      discard default(LlmPipeline).generate("prompt\0truncated")
    expect OpenVinoArgumentError:
      discard jsonFromString("{}\0truncated")
    expect OpenVinoArgumentError:
      default(WhisperGenerationConfig).setLanguage("en\0truncated")
    expect OpenVinoArgumentError:
      default(GenerationConfig).setStopStrings(["bad\0stop"])
