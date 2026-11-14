# SPDX-License-Identifier: Apache-2.0

## Managed, optional OpenVINO GenAI support.
##
## GenAI loads independently from the core OpenVINO Runtime. This module can be
## imported without either shared library installed; the matching GenAI C
## library is opened only when the first GenAI call is made. The underlying
## header-faithful API is available separately through `openvino/raw/genai`.

import errors
import private/conversions
import private/genai_bridge
import private/handles
import raw/genai as rawGenAi
import tensor

type
  GenAiError* = object of CatchableError
    ## A GenAI C API call returned an error status.
    operation*: string
    status*: cint

  GenAiLibraryError* = rawGenAi.GenAiLibraryError
    ## The optional GenAI C shared library or a required symbol is unavailable.

  GenAiCallbackError* = object of CatchableError
    ## A managed streaming callback raised while GenAI was generating.
    callbackMessage*: string

  StopCriteria* = enum
    ## Beam search stopping behaviour.
    scEarly
    scHeuristic
    scNever

  StreamAction* = enum
    ## What a managed generation streamer asks the pipeline to do next.
    streamContinue
    streamStop
    streamCancel

  StreamHandler* = proc (piece: string): StreamAction
    {.closure, raises: [CatchableError].}
    ## Receives decoded text pieces synchronously during generation.

  StreamContext = object
    handler: StreamHandler
    callbackFailed: bool
    failureMessage: string
    accumulated: string

  GenerationConfig* = object
    ## Owned, reusable GenAI token generation settings.
    handle: Handle[ov_genai_generation_config]

  JsonContainer* = object
    ## Owned JSON object/array/value used by chat histories and tool metadata.
    handle: Handle[ov_genai_json_container]

  ChatHistory* = object
    ## Owned sequence of OpenAI-style message objects plus tools/context.
    handle: Handle[ov_genai_chat_history]

  DecodedResults* = object
    ## Owned LLM generation output.
    handle: Handle[ov_genai_decoded_results]

  VlmDecodedResults* = object
    ## Owned visual-language generation output.
    handle: Handle[ov_genai_vlm_decoded_results]

  WhisperDecodedResults* = object
    ## Owned speech transcription output, including optional chunks and scores.
    handle: Handle[ov_genai_whisper_decoded_results]

  WhisperChunk* = object
    ## One owned timestamped Whisper transcription chunk.
    handle: Handle[ov_genai_whisper_decoded_result_chunk]

  PerfMetrics* = object
    ## Owned performance statistics returned by a generated result.
    handle: Handle[ov_genai_perf_metrics]

  WhisperGenerationConfig* = object
    ## Owned speech recognition/translation configuration.
    handle: Handle[ov_genai_whisper_generation_config]

  LlmPipeline* = object
    ## Owned text generation pipeline. Calls block until generation completes.
    handle: Handle[ov_genai_llm_pipeline]

  VlmPipeline* = object
    ## Owned visual-language pipeline. Image inputs are OpenVINO tensors.
    handle: Handle[ov_genai_vlm_pipeline]

  WhisperPipeline* = object
    ## Owned Whisper speech recognition pipeline. Audio is 16 kHz mono float32.
    handle: Handle[ov_genai_whisper_pipeline]

proc releaseGenerationConfig(native: ptr ov_genai_generation_config) {.nimcall.} =
  ov_genai_generation_config_free(native)

proc releaseJsonContainer(native: ptr ov_genai_json_container) {.nimcall.} =
  ov_genai_json_container_free(native)

proc releaseChatHistory(native: ptr ov_genai_chat_history) {.nimcall.} =
  ov_genai_chat_history_free(native)

proc releaseDecodedResults(native: ptr ov_genai_decoded_results) {.nimcall.} =
  ov_genai_decoded_results_free(native)

proc releaseVlmResults(native: ptr ov_genai_vlm_decoded_results) {.nimcall.} =
  ov_genai_vlm_decoded_results_free(native)

proc releaseWhisperResults(native: ptr ov_genai_whisper_decoded_results) {.nimcall.} =
  ov_genai_whisper_decoded_results_free(native)

proc releaseWhisperChunk(native: ptr ov_genai_whisper_decoded_result_chunk) {.nimcall.} =
  ov_genai_whisper_decoded_result_chunk_free(native)

proc releasePerfMetrics(native: ptr ov_genai_perf_metrics) {.nimcall.} =
  ov_genai_decoded_results_perf_metrics_free(native)

proc releaseWhisperConfig(native: ptr ov_genai_whisper_generation_config) {.nimcall.} =
  ov_genai_whisper_generation_config_free(native)

proc releaseLlmPipeline(native: ptr ov_genai_llm_pipeline) {.nimcall.} =
  ov_genai_llm_pipeline_free(native)

proc releaseVlmPipeline(native: ptr ov_genai_vlm_pipeline) {.nimcall.} =
  ov_genai_vlm_pipeline_free(native)

proc releaseWhisperPipeline(native: ptr ov_genai_whisper_pipeline) {.nimcall.} =
  ov_genai_whisper_pipeline_free(native)

proc native(config: GenerationConfig): ptr ov_genai_generation_config =
  config.handle.native()

proc native(json: JsonContainer): ptr ov_genai_json_container =
  json.handle.native()

proc native(history: ChatHistory): ptr ov_genai_chat_history =
  history.handle.native()

proc native(results: DecodedResults): ptr ov_genai_decoded_results =
  results.handle.native()

proc native(results: VlmDecodedResults): ptr ov_genai_vlm_decoded_results =
  results.handle.native()

proc native(results: WhisperDecodedResults): ptr ov_genai_whisper_decoded_results =
  results.handle.native()

proc native(chunk: WhisperChunk): ptr ov_genai_whisper_decoded_result_chunk =
  chunk.handle.native()

proc native(metrics: PerfMetrics): ptr ov_genai_perf_metrics =
  metrics.handle.native()

proc native(config: WhisperGenerationConfig): ptr ov_genai_whisper_generation_config =
  config.handle.native()

proc native(pipeline: LlmPipeline): ptr ov_genai_llm_pipeline =
  pipeline.handle.native()

proc native(pipeline: VlmPipeline): ptr ov_genai_vlm_pipeline =
  pipeline.handle.native()

proc native(pipeline: WhisperPipeline): ptr ov_genai_whisper_pipeline =
  pipeline.handle.native()

proc raiseGenAiError(operation: string; status: ov_status_e) {.noreturn.} =
  var err = newException(GenAiError,
    operation & " failed with GenAI/OpenVINO status " & $status)
  err.operation = operation
  err.status = cint(status)
  raise err

proc checkGenAiStatus(status: ov_status_e; operation: string) =
  if status != 0:
    raiseGenAiError(operation, status)

proc checkJsonStatus(status: ov_genai_json_container_status_e;
                     operation: string) =
  if status != OV_GENAI_JSON_CONTAINER_OK:
    raiseGenAiError(operation, ov_status_e(status))

proc checkHistoryStatus(status: ov_genai_chat_history_status_e;
                        operation: string) =
  if status != OV_GENAI_CHAT_HISTORY_OK:
    raiseGenAiError(operation, ov_status_e(status))

proc newGenerationConfig*(): GenerationConfig =
  ## Creates default text generation settings.
  var nativeConfig: ptr ov_genai_generation_config = nil
  checkGenAiStatus(ov_genai_generation_config_create(addr nativeConfig),
                   "create generation config")
  result.handle = newHandle(nativeConfig, releaseGenerationConfig,
                            "GenAI generation config")

proc generationConfigFromJson*(path: string): GenerationConfig =
  ## Loads generation settings from a model-compatible JSON file.
  checkCString(path, "generation config path")
  var nativeConfig: ptr ov_genai_generation_config = nil
  checkGenAiStatus(ov_genai_generation_config_create_from_json(path.cstring,
    addr nativeConfig), "load generation config")
  result.handle = newHandle(nativeConfig, releaseGenerationConfig,
                            "GenAI generation config")

proc close*(config: GenerationConfig) = config.handle.close()
proc isClosed*(config: GenerationConfig): bool = config.handle.isClosed()

proc setMaxNewTokens*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("maxNewTokens cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_max_new_tokens(
    config.native(), csize_t(value)), "set maximum new tokens")

proc maxNewTokens*(config: GenerationConfig): int =
  var value: csize_t = 0
  checkGenAiStatus(ov_genai_generation_config_get_max_new_tokens(
    config.native(), addr value), "get maximum new tokens")
  result = int(value)

proc setMaxLength*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("maxLength cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_max_length(
    config.native(), csize_t(value)), "set maximum length")

proc setMinNewTokens*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("minNewTokens cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_min_new_tokens(
    config.native(), csize_t(value)), "set minimum new tokens")

proc setIgnoreEos*(config: GenerationConfig; value: bool) =
  checkGenAiStatus(ov_genai_generation_config_set_ignore_eos(
    config.native(), value), "set ignore EOS")

proc setEcho*(config: GenerationConfig; value: bool) =
  checkGenAiStatus(ov_genai_generation_config_set_echo(
    config.native(), value), "set echo")

proc setLogprobs*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("logprobs cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_logprobs(
    config.native(), csize_t(value)), "set logprobs")

proc setStopStrings*(config: GenerationConfig; values: openArray[string]) =
  var strings = newSeq[cstring](values.len)
  for i, value in values:
    checkCString(value, "GenAI stop string")
    strings[i] = value.cstring
  # invariant: the upstream implementation rejects a null `strings` pointer
  # even when `count == 0`; this local sentinel is non-null and is not read.
  var emptyString: cstring = nil
  let data = if strings.len == 0: addr emptyString else: addr strings[0]
  checkGenAiStatus(ov_genai_generation_config_set_stop_strings(
    config.native(), data, csize_t(strings.len)), "set stop strings")

proc setIncludeStopString*(config: GenerationConfig; value: bool) =
  checkGenAiStatus(ov_genai_generation_config_set_include_stop_str_in_output(
    config.native(), value), "set include stop string")

proc setStopTokenIds*(config: GenerationConfig; values: openArray[int64]) =
  let data = if values.len == 0: nil else: unsafeAddr values[0]
  checkGenAiStatus(ov_genai_generation_config_set_stop_token_ids(
    config.native(), data, csize_t(values.len)), "set stop token IDs")

proc setNumBeamGroups*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("numBeamGroups cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_num_beam_groups(
    config.native(), csize_t(value)), "set beam groups")

proc setNumBeams*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("numBeams cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_num_beams(
    config.native(), csize_t(value)), "set beams")

proc setDiversityPenalty*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_diversity_penalty(
    config.native(), cfloat(value)), "set diversity penalty")

proc setLengthPenalty*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_length_penalty(
    config.native(), cfloat(value)), "set length penalty")

proc setNumReturnSequences*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("numReturnSequences cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_num_return_sequences(
    config.native(), csize_t(value)), "set return sequences")

proc setNoRepeatNgramSize*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("noRepeatNgramSize cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_no_repeat_ngram_size(
    config.native(), csize_t(value)), "set no-repeat n-gram size")

proc setStopCriteria*(config: GenerationConfig; value: StopCriteria) =
  let rawValue = case value
    of scEarly: rawGenAi.EARLY
    of scHeuristic: rawGenAi.HEURISTIC
    of scNever: rawGenAi.NEVER
  checkGenAiStatus(ov_genai_generation_config_set_stop_criteria(
    config.native(), rawValue), "set stop criteria")

proc setTemperature*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_temperature(
    config.native(), cfloat(value)), "set temperature")

proc setTopP*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_top_p(
    config.native(), cfloat(value)), "set top-p")

proc setTopK*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("topK cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_top_k(
    config.native(), csize_t(value)), "set top-k")

proc setMinP*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_min_p(
    config.native(), cfloat(value)), "set min-p")

proc setDoSample*(config: GenerationConfig; value: bool) =
  checkGenAiStatus(ov_genai_generation_config_set_do_sample(
    config.native(), value), "set sampling")

proc setRepetitionPenalty*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_repetition_penalty(
    config.native(), cfloat(value)), "set repetition penalty")

proc setPresencePenalty*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_presence_penalty(
    config.native(), cfloat(value)), "set presence penalty")

proc setFrequencyPenalty*(config: GenerationConfig; value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_frequency_penalty(
    config.native(), cfloat(value)), "set frequency penalty")

proc setRngSeed*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("rngSeed cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_rng_seed(
    config.native(), csize_t(value)), "set RNG seed")

proc setAssistantConfidenceThreshold*(config: GenerationConfig;
                                       value: float32) =
  checkGenAiStatus(ov_genai_generation_config_set_assistant_confidence_threshold(
    config.native(), cfloat(value)), "set assistant confidence threshold")

proc setNumAssistantTokens*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("numAssistantTokens cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_num_assistant_tokens(
    config.native(), csize_t(value)), "set assistant tokens")

proc setMaxNgramSize*(config: GenerationConfig; value: int) =
  if value < 0: raiseArgumentError("maxNgramSize cannot be negative")
  checkGenAiStatus(ov_genai_generation_config_set_max_ngram_size(
    config.native(), csize_t(value)), "set maximum n-gram size")

proc setEosTokenId*(config: GenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_generation_config_set_eos_token_id(
    config.native(), value), "set EOS token ID")

proc validate*(config: GenerationConfig) =
  checkGenAiStatus(ov_genai_generation_config_validate(config.native()),
                   "validate generation config")

proc newJsonContainer*(): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkJsonStatus(ov_genai_json_container_create(addr nativeJson),
                  "create JSON container")
  result.handle = newHandle(nativeJson, releaseJsonContainer,
                            "GenAI JSON container")

proc newJsonObject*(): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkJsonStatus(ov_genai_json_container_create_object(addr nativeJson),
                  "create JSON object")
  result.handle = newHandle(nativeJson, releaseJsonContainer,
                            "GenAI JSON container")

proc newJsonArray*(): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkJsonStatus(ov_genai_json_container_create_array(addr nativeJson),
                  "create JSON array")
  result.handle = newHandle(nativeJson, releaseJsonContainer,
                            "GenAI JSON container")

proc jsonFromString*(value: string): JsonContainer =
  checkCString(value, "GenAI JSON string")
  var nativeJson: ptr ov_genai_json_container = nil
  checkJsonStatus(ov_genai_json_container_create_from_json_string(
    addr nativeJson, value.cstring), "parse JSON")
  result.handle = newHandle(nativeJson, releaseJsonContainer,
                            "GenAI JSON container")

proc close*(json: JsonContainer) = json.handle.close()
proc isClosed*(json: JsonContainer): bool = json.handle.isClosed()

proc toJson*(json: JsonContainer): string =
  var size: csize_t = 0
  checkJsonStatus(ov_genai_json_container_to_json_string(
    json.native(), nil, addr size), "measure JSON string")
  if size == 0: return ""
  result = newString(int(size))
  checkJsonStatus(ov_genai_json_container_to_json_string(
    json.native(), result.cstring, addr size), "copy JSON string")
  result.setLen(int(size) - 1)

proc copy*(json: JsonContainer): JsonContainer =
  var copied: ptr ov_genai_json_container = nil
  checkJsonStatus(ov_genai_json_container_copy(json.native(), addr copied),
                  "copy JSON container")
  result.handle = newHandle(copied, releaseJsonContainer,
                            "GenAI JSON container")

proc newChatHistory*(): ChatHistory =
  var nativeHistory: ptr ov_genai_chat_history = nil
  checkHistoryStatus(ov_genai_chat_history_create(addr nativeHistory),
                     "create chat history")
  result.handle = newHandle(nativeHistory, releaseChatHistory,
                            "GenAI chat history")

proc chatHistoryFromJson*(messages: JsonContainer): ChatHistory =
  var nativeHistory: ptr ov_genai_chat_history = nil
  checkHistoryStatus(ov_genai_chat_history_create_from_json_container(
    addr nativeHistory, messages.native()), "create chat history from JSON")
  result.handle = newHandle(nativeHistory, releaseChatHistory,
                            "GenAI chat history")

proc close*(history: ChatHistory) = history.handle.close()
proc isClosed*(history: ChatHistory): bool = history.handle.isClosed()

proc len*(history: ChatHistory): int =
  var size: csize_t = 0
  checkHistoryStatus(ov_genai_chat_history_size(history.native(), addr size),
                     "get chat history size")
  result = int(size)

proc isEmpty*(history: ChatHistory): bool =
  var empty: cint = 0
  checkHistoryStatus(ov_genai_chat_history_empty(history.native(), addr empty),
                     "check chat history")
  result = empty != 0

proc clear*(history: ChatHistory) =
  checkHistoryStatus(ov_genai_chat_history_clear(history.native()),
                     "clear chat history")

proc pushBack*(history: ChatHistory; message: JsonContainer) =
  checkHistoryStatus(ov_genai_chat_history_push_back(history.native(),
    message.native()), "append chat message")

proc popBack*(history: ChatHistory) =
  checkHistoryStatus(ov_genai_chat_history_pop_back(history.native()),
                     "remove last chat message")

proc wrapJson(nativeJson: ptr ov_genai_json_container): JsonContainer =
  result.handle = newHandle(nativeJson, releaseJsonContainer,
                            "GenAI JSON container")

proc messages*(history: ChatHistory): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkHistoryStatus(ov_genai_chat_history_get_messages(history.native(),
    addr nativeJson), "get chat messages")
  result = wrapJson(nativeJson)

proc messageAt*(history: ChatHistory; index: int): JsonContainer =
  if index < 0: raiseArgumentError("chat history index cannot be negative")
  var nativeJson: ptr ov_genai_json_container = nil
  checkHistoryStatus(ov_genai_chat_history_get_message(history.native(),
    csize_t(index), addr nativeJson), "get chat message")
  result = wrapJson(nativeJson)

proc firstMessage*(history: ChatHistory): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkHistoryStatus(ov_genai_chat_history_get_first(history.native(),
    addr nativeJson), "get first chat message")
  result = wrapJson(nativeJson)

proc lastMessage*(history: ChatHistory): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkHistoryStatus(ov_genai_chat_history_get_last(history.native(),
    addr nativeJson), "get last chat message")
  result = wrapJson(nativeJson)

proc setTools*(history: ChatHistory; tools: JsonContainer) =
  checkHistoryStatus(ov_genai_chat_history_set_tools(history.native(),
    tools.native()), "set chat tools")

proc tools*(history: ChatHistory): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkHistoryStatus(ov_genai_chat_history_get_tools(history.native(),
    addr nativeJson), "get chat tools")
  result = wrapJson(nativeJson)

proc setExtraContext*(history: ChatHistory; context: JsonContainer) =
  checkHistoryStatus(ov_genai_chat_history_set_extra_context(history.native(),
    context.native()), "set chat extra context")

proc extraContext*(history: ChatHistory): JsonContainer =
  var nativeJson: ptr ov_genai_json_container = nil
  checkHistoryStatus(ov_genai_chat_history_get_extra_context(history.native(),
    addr nativeJson), "get chat extra context")
  result = wrapJson(nativeJson)

proc readSizedString(sizeCall, fillCall: proc (buffer: cstring;
    size: ptr csize_t): ov_status_e {.closure.}; operation: string): string =
  var size: csize_t = 0
  checkGenAiStatus(sizeCall(nil, addr size), "measure " & operation)
  if size == 0: return ""
  result = newString(int(size))
  checkGenAiStatus(fillCall(result.cstring, addr size), "read " & operation)
  result.setLen(int(size) - 1)

proc text*(results: DecodedResults): string =
  readSizedString(
    proc (buffer: cstring; size: ptr csize_t): ov_status_e =
    ov_genai_decoded_results_get_string(results.native(), buffer, size),
    proc (buffer: cstring; size: ptr csize_t): ov_status_e =
    ov_genai_decoded_results_get_string(results.native(), buffer, size),
    "generated text")

proc close*(results: DecodedResults) = results.handle.close()
proc isClosed*(results: DecodedResults): bool = results.handle.isClosed()

proc generationMetrics*(results: DecodedResults): PerfMetrics =
  var nativeMetrics: ptr ov_genai_perf_metrics = nil
  checkGenAiStatus(ov_genai_decoded_results_get_perf_metrics(
    results.native(), addr nativeMetrics), "get generation metrics")
  result.handle = newHandle(nativeMetrics, releasePerfMetrics,
                            "GenAI performance metrics")

proc validatePipelineInputs(modelPath, device: string;
                            properties: openArray[(string, string)]) =
  if properties.len > 16:
    raiseArgumentError("GenAI pipeline constructors accept at most 16 " &
      "property pairs through this adapter")
  checkCString(modelPath, "GenAI model path")
  checkCString(device, "GenAI device")
  for property in properties:
    checkCString(property[0], "GenAI property key")
    checkCString(property[1], "GenAI property value")

proc newLlmPipeline*(modelPath: string; device = "CPU";
                     properties: seq[(string, string)] = @[]): LlmPipeline =
  ## Creates a text generation pipeline. Property values are passed as strings.
  validatePipelineInputs(modelPath, device, properties)
  var nativePipeline: ptr ov_genai_llm_pipeline = nil
  let status = createGenAiPipeline(
    rawGenAi.genAiFunctionSymbol("ov_genai_llm_pipeline_create"), modelPath,
    device, properties, addr nativePipeline)
  checkGenAiStatus(status, "create LLM pipeline")
  result.handle = newHandle(nativePipeline, releaseLlmPipeline,
                            "GenAI LLM pipeline")

proc close*(pipeline: LlmPipeline) = pipeline.handle.close()
proc isClosed*(pipeline: LlmPipeline): bool = pipeline.handle.isClosed()

proc optionalConfig(config: GenerationConfig): ptr ov_genai_generation_config =
  if config.handle == nil: nil else: config.native()

proc generate*(pipeline: LlmPipeline; prompt: string;
               config = GenerationConfig()): DecodedResults =
  ## Generates one response, blocking the calling thread until it completes.
  checkCString(prompt, "GenAI prompt")
  var nativeResults: ptr ov_genai_decoded_results = nil
  checkGenAiStatus(ov_genai_llm_pipeline_generate(pipeline.native(),
    prompt.cstring, optionalConfig(config), nil, addr nativeResults),
    "generate text")
  result.handle = newHandle(nativeResults, releaseDecodedResults,
                            "GenAI decoded results")

proc generate*(pipeline: LlmPipeline; history: ChatHistory;
               config = GenerationConfig()): DecodedResults =
  ## Generates from a structured chat history.
  var nativeResults: ptr ov_genai_decoded_results = nil
  checkGenAiStatus(ov_genai_llm_pipeline_generate_with_history(
    pipeline.native(), history.native(), optionalConfig(config), nil,
    addr nativeResults), "generate from chat history")
  result.handle = newHandle(nativeResults, releaseDecodedResults,
                            "GenAI decoded results")

proc invokeStream(text: cstring; args: pointer): ov_genai_streaming_status_e
    {.cdecl, raises: [].}
proc raiseStreamCallbackError(context: StreamContext) {.noreturn.}

proc streamGenerate*(pipeline: LlmPipeline; history: ChatHistory;
                     handler: StreamHandler;
                     config = GenerationConfig()): string =
  ## Streams a response generated from structured chat history.
  if handler == nil:
    raiseArgumentError("stream handler cannot be nil")
  var context = StreamContext(handler: handler)
  var callback = ov_genai_streamer_callback(callbackFunc: invokeStream,
                                            args: addr context)
  let status = ov_genai_llm_pipeline_generate_with_history(
    pipeline.native(), history.native(), optionalConfig(config), addr callback,
    nil)
  if context.callbackFailed:
    raiseStreamCallbackError(context)
  checkGenAiStatus(status, "stream generation from chat history")
  result = context.accumulated

proc startChat*(pipeline: LlmPipeline) =
  checkGenAiStatus(ov_genai_llm_pipeline_start_chat(pipeline.native()),
                   "start LLM chat")

proc finishChat*(pipeline: LlmPipeline) =
  checkGenAiStatus(ov_genai_llm_pipeline_finish_chat(pipeline.native()),
                   "finish LLM chat")

proc generationConfig*(pipeline: LlmPipeline): GenerationConfig =
  var nativeConfig: ptr ov_genai_generation_config = nil
  checkGenAiStatus(ov_genai_llm_pipeline_get_generation_config(
    pipeline.native(), addr nativeConfig), "get LLM generation config")
  result.handle = newHandle(nativeConfig, releaseGenerationConfig,
                            "GenAI generation config")

proc setGenerationConfig*(pipeline: LlmPipeline; config: GenerationConfig) =
  checkGenAiStatus(ov_genai_llm_pipeline_set_generation_config(
    pipeline.native(), config.native()), "set LLM generation config")

proc invokeStream(text: cstring; args: pointer): ov_genai_streaming_status_e
    {.cdecl, raises: [].} =
  # invariant: `args` points to StreamContext on the still-active generate call
  # stack; GenAI invokes this callback synchronously before that call returns.
  let context = cast[ptr StreamContext](args)
  if context.callbackFailed:
    return OV_GENAI_STREAMING_STATUS_STOP
  try:
    case context.handler($text)
    of streamContinue:
      context.accumulated.add($text)
      result = OV_GENAI_STREAMING_STATUS_RUNNING
    of streamStop:
      context.accumulated.add($text)
      result = OV_GENAI_STREAMING_STATUS_STOP
    of streamCancel:
      context.accumulated.add($text)
      result = OV_GENAI_STREAMING_STATUS_CANCEL
  except CatchableError as error:
    context.callbackFailed = true
    context.failureMessage = error.msg
    result = OV_GENAI_STREAMING_STATUS_STOP

proc raiseStreamCallbackError(context: StreamContext) {.noreturn.} =
  var err = newException(GenAiCallbackError,
    "GenAI streaming callback raised: " & context.failureMessage)
  err.callbackMessage = context.failureMessage
  raise err

proc streamGenerate*(pipeline: LlmPipeline; prompt: string;
                     handler: StreamHandler;
                     config = GenerationConfig()): string =
  ## Streams decoded pieces synchronously and also returns their concatenation.
  ## A callback exception is re-raised only after the native call has returned.
  if handler == nil:
    raiseArgumentError("stream handler cannot be nil")
  checkCString(prompt, "GenAI prompt")
  var context = StreamContext(handler: handler)
  var callback = ov_genai_streamer_callback(callbackFunc: invokeStream,
                                            args: addr context)
  let status = ov_genai_llm_pipeline_generate(pipeline.native(),
    prompt.cstring, optionalConfig(config), addr callback, nil)
  if context.callbackFailed:
    raiseStreamCallbackError(context)
  checkGenAiStatus(status, "stream text generation")
  result = context.accumulated

proc newVlmPipeline*(modelPath: string; device = "CPU";
                     properties: seq[(string, string)] = @[]): VlmPipeline =
  ## Creates a visual-language pipeline. Supply image tensors to `generate`.
  validatePipelineInputs(modelPath, device, properties)
  var nativePipeline: ptr ov_genai_vlm_pipeline = nil
  let status = createGenAiPipeline(
    rawGenAi.genAiFunctionSymbol("ov_genai_vlm_pipeline_create"), modelPath,
    device, properties, addr nativePipeline)
  checkGenAiStatus(status, "create VLM pipeline")
  result.handle = newHandle(nativePipeline, releaseVlmPipeline,
                            "GenAI VLM pipeline")

proc close*(pipeline: VlmPipeline) = pipeline.handle.close()
proc isClosed*(pipeline: VlmPipeline): bool = pipeline.handle.isClosed()

proc generate*(pipeline: VlmPipeline; prompt: string;
               images: openArray[Tensor];
               config = GenerationConfig()): VlmDecodedResults =
  ## Generates from text and zero or more OpenVINO image tensors.
  checkCString(prompt, "GenAI prompt")
  var rawImages = newSeq[ptr ov_tensor_t](images.len)
  for i, image in images:
    rawImages[i] = image.unsafeNativeHandle()
  let imagePointer = if rawImages.len == 0: nil else: addr rawImages[0]
  var nativeResults: ptr ov_genai_vlm_decoded_results = nil
  checkGenAiStatus(ov_genai_vlm_pipeline_generate(pipeline.native(),
    prompt.cstring, imagePointer, csize_t(rawImages.len),
    optionalConfig(config), nil, addr nativeResults), "generate visual text")
  result.handle = newHandle(nativeResults, releaseVlmResults,
                            "GenAI VLM decoded results")

proc generate*(pipeline: VlmPipeline; history: ChatHistory;
               images: openArray[Tensor];
               config = GenerationConfig()): VlmDecodedResults =
  ## Generates from structured chat messages and images for the latest message.
  var rawImages = newSeq[ptr ov_tensor_t](images.len)
  for i, image in images:
    rawImages[i] = image.unsafeNativeHandle()
  let imagePointer = if rawImages.len == 0: nil else: addr rawImages[0]
  var nativeResults: ptr ov_genai_vlm_decoded_results = nil
  checkGenAiStatus(ov_genai_vlm_pipeline_generate_with_history(
    pipeline.native(), history.native(), imagePointer, csize_t(rawImages.len),
    optionalConfig(config), nil, addr nativeResults),
    "generate visual response from chat history")
  result.handle = newHandle(nativeResults, releaseVlmResults,
                            "GenAI VLM decoded results")

proc streamGenerate*(pipeline: VlmPipeline; prompt: string;
                     images: openArray[Tensor]; handler: StreamHandler;
                     config = GenerationConfig()): string =
  ## Streams a VLM response synchronously and returns all emitted pieces.
  if handler == nil:
    raiseArgumentError("stream handler cannot be nil")
  checkCString(prompt, "GenAI prompt")
  var rawImages = newSeq[ptr ov_tensor_t](images.len)
  for i, image in images:
    rawImages[i] = image.unsafeNativeHandle()
  let imagePointer = if rawImages.len == 0: nil else: addr rawImages[0]
  var context = StreamContext(handler: handler)
  var callback = ov_genai_streamer_callback(callbackFunc: invokeStream,
                                            args: addr context)
  let status = ov_genai_vlm_pipeline_generate(pipeline.native(),
    prompt.cstring, imagePointer, csize_t(rawImages.len),
    optionalConfig(config), addr callback, nil)
  if context.callbackFailed:
    raiseStreamCallbackError(context)
  checkGenAiStatus(status, "stream VLM generation")
  result = context.accumulated

proc streamGenerate*(pipeline: VlmPipeline; history: ChatHistory;
                     images: openArray[Tensor]; handler: StreamHandler;
                     config = GenerationConfig()): string =
  ## Streams a VLM response from structured history and image tensors.
  if handler == nil:
    raiseArgumentError("stream handler cannot be nil")
  var rawImages = newSeq[ptr ov_tensor_t](images.len)
  for i, image in images:
    rawImages[i] = image.unsafeNativeHandle()
  let imagePointer = if rawImages.len == 0: nil else: addr rawImages[0]
  var context = StreamContext(handler: handler)
  var callback = ov_genai_streamer_callback(callbackFunc: invokeStream,
                                            args: addr context)
  let status = ov_genai_vlm_pipeline_generate_with_history(
    pipeline.native(), history.native(), imagePointer, csize_t(rawImages.len),
    optionalConfig(config), addr callback, nil)
  if context.callbackFailed:
    raiseStreamCallbackError(context)
  checkGenAiStatus(status, "stream VLM generation from chat history")
  result = context.accumulated

proc startChat*(pipeline: VlmPipeline) =
  checkGenAiStatus(ov_genai_vlm_pipeline_start_chat(pipeline.native()),
                   "start VLM chat")

proc finishChat*(pipeline: VlmPipeline) =
  checkGenAiStatus(ov_genai_vlm_pipeline_finish_chat(pipeline.native()),
                   "finish VLM chat")

proc generationConfig*(pipeline: VlmPipeline): GenerationConfig =
  var nativeConfig: ptr ov_genai_generation_config = nil
  checkGenAiStatus(ov_genai_vlm_pipeline_get_generation_config(
    pipeline.native(), addr nativeConfig), "get VLM generation config")
  result.handle = newHandle(nativeConfig, releaseGenerationConfig,
                            "GenAI generation config")

proc setGenerationConfig*(pipeline: VlmPipeline; config: GenerationConfig) =
  checkGenAiStatus(ov_genai_vlm_pipeline_set_generation_config(
    pipeline.native(), config.native()), "set VLM generation config")

proc text*(results: VlmDecodedResults): string =
  var size: csize_t = 0
  checkGenAiStatus(ov_genai_vlm_decoded_results_get_string(
    results.handle.native(), nil, addr size), "measure VLM result")
  if size == 0: return ""
  result = newString(int(size))
  checkGenAiStatus(ov_genai_vlm_decoded_results_get_string(
    results.handle.native(), result.cstring, addr size), "read VLM result")
  result.setLen(int(size) - 1)

proc close*(results: VlmDecodedResults) = results.handle.close()

proc generationMetrics*(results: VlmDecodedResults): PerfMetrics =
  var nativeMetrics: ptr ov_genai_perf_metrics = nil
  checkGenAiStatus(ov_genai_vlm_decoded_results_get_perf_metrics(
    results.handle.native(), addr nativeMetrics), "get VLM performance metrics")
  result.handle = newHandle(nativeMetrics, releasePerfMetrics,
                            "GenAI performance metrics")

proc newWhisperPipeline*(modelPath: string; device = "CPU";
                         properties: seq[(string, string)] = @[]): WhisperPipeline =
  ## Creates a Whisper pipeline. Audio input is expected as mono 16 kHz float32.
  validatePipelineInputs(modelPath, device, properties)
  var nativePipeline: ptr ov_genai_whisper_pipeline = nil
  let status = createGenAiPipeline(
    rawGenAi.genAiFunctionSymbol("ov_genai_whisper_pipeline_create"), modelPath,
    device, properties, addr nativePipeline)
  checkGenAiStatus(status, "create Whisper pipeline")
  result.handle = newHandle(nativePipeline, releaseWhisperPipeline,
                            "GenAI Whisper pipeline")

proc close*(pipeline: WhisperPipeline) = pipeline.handle.close()
proc isClosed*(pipeline: WhisperPipeline): bool = pipeline.handle.isClosed()

proc generationConfig*(pipeline: WhisperPipeline): WhisperGenerationConfig =
  var nativeConfig: ptr ov_genai_whisper_generation_config = nil
  checkGenAiStatus(ov_genai_whisper_pipeline_get_generation_config(
    pipeline.native(), addr nativeConfig), "get Whisper generation config")
  result.handle = newHandle(nativeConfig, releaseWhisperConfig,
                            "GenAI Whisper config")

proc setGenerationConfig*(pipeline: WhisperPipeline;
                          config: WhisperGenerationConfig) =
  checkGenAiStatus(ov_genai_whisper_pipeline_set_generation_config(
    pipeline.native(), config.native()), "set Whisper generation config")

proc newWhisperGenerationConfig*(): WhisperGenerationConfig =
  var nativeConfig: ptr ov_genai_whisper_generation_config = nil
  checkGenAiStatus(ov_genai_whisper_generation_config_create(addr nativeConfig),
                   "create Whisper config")
  result.handle = newHandle(nativeConfig, releaseWhisperConfig,
                            "GenAI Whisper config")

proc whisperGenerationConfigFromJson*(path: string): WhisperGenerationConfig =
  checkCString(path, "Whisper config path")
  var nativeConfig: ptr ov_genai_whisper_generation_config = nil
  checkGenAiStatus(ov_genai_whisper_generation_config_create_from_json(
    path.cstring, addr nativeConfig), "load Whisper generation config")
  result.handle = newHandle(nativeConfig, releaseWhisperConfig,
                            "GenAI Whisper config")

proc close*(config: WhisperGenerationConfig) = config.handle.close()
proc validate*(config: WhisperGenerationConfig) =
  checkGenAiStatus(ov_genai_whisper_generation_config_validate(config.native()),
                   "validate Whisper config")

proc setLanguage*(config: WhisperGenerationConfig; language: string) =
  checkCString(language, "Whisper language")
  checkGenAiStatus(ov_genai_whisper_generation_config_set_language(
    config.native(), language.cstring), "set Whisper language")

proc setTask*(config: WhisperGenerationConfig; task: string) =
  checkCString(task, "Whisper task")
  checkGenAiStatus(ov_genai_whisper_generation_config_set_task(
    config.native(), task.cstring), "set Whisper task")

proc setReturnTimestamps*(config: WhisperGenerationConfig; value: bool) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_return_timestamps(
    config.native(), value), "set Whisper timestamps")

proc setInitialPrompt*(config: WhisperGenerationConfig; prompt: string) =
  checkCString(prompt, "Whisper initial prompt")
  checkGenAiStatus(ov_genai_whisper_generation_config_set_initial_prompt(
    config.native(), prompt.cstring), "set Whisper initial prompt")

proc setHotwords*(config: WhisperGenerationConfig; words: string) =
  checkCString(words, "Whisper hotwords")
  checkGenAiStatus(ov_genai_whisper_generation_config_set_hotwords(
    config.native(), words.cstring), "set Whisper hotwords")

proc setIsMultilingual*(config: WhisperGenerationConfig; value: bool) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_is_multilingual(
    config.native(), value), "set Whisper multilingual flag")

proc setPreviousStartTokenId*(config: WhisperGenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_prev_sot_token_id(
    config.native(), value), "set Whisper previous start token")

proc setNoTimestampsTokenId*(config: WhisperGenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_no_timestamps_token_id(
    config.native(), value), "set Whisper no-timestamps token")

proc setMaxInitialTimestampIndex*(config: WhisperGenerationConfig; value: int) =
  if value < 0:
    raiseArgumentError("maxInitialTimestampIndex cannot be negative")
  checkGenAiStatus(ov_genai_whisper_generation_config_set_max_initial_timestamp_index(
    config.native(), csize_t(value)), "set Whisper maximum initial timestamp")

proc setBeginSuppressTokens*(config: WhisperGenerationConfig;
                             values: openArray[int64]) =
  let data = if values.len == 0: nil else: unsafeAddr values[0]
  checkGenAiStatus(ov_genai_whisper_generation_config_set_begin_suppress_tokens(
    config.native(), data, csize_t(values.len)),
    "set Whisper begin-suppress tokens")

proc setSuppressTokens*(config: WhisperGenerationConfig;
                        values: openArray[int64]) =
  let data = if values.len == 0: nil else: unsafeAddr values[0]
  checkGenAiStatus(ov_genai_whisper_generation_config_set_suppress_tokens(
    config.native(), data, csize_t(values.len)), "set Whisper suppress tokens")

proc whisperTokenIds(config: WhisperGenerationConfig;
    countGetter: proc (native: ptr ov_genai_whisper_generation_config;
                       count: ptr csize_t): ov_status_e {.closure.};
    valueGetter: proc (native: ptr ov_genai_whisper_generation_config;
                       values: ptr int64; count: csize_t): ov_status_e
                       {.closure.};
    operation: string): seq[int64] =
  var count: csize_t = 0
  checkGenAiStatus(countGetter(config.native(), addr count),
                   "get " & operation & " count")
  result = newSeq[int64](int(count))
  if count > 0:
    checkGenAiStatus(valueGetter(config.native(), addr result[0], count),
                     "get " & operation)

proc beginSuppressTokens*(config: WhisperGenerationConfig): seq[int64] =
  whisperTokenIds(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          count: ptr csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_begin_suppress_tokens_count(
      native, count),
    proc (native: ptr ov_genai_whisper_generation_config; values: ptr int64;
          count: csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_begin_suppress_tokens(
      native, values, count),
    "Whisper begin-suppress tokens")

proc suppressTokens*(config: WhisperGenerationConfig): seq[int64] =
  whisperTokenIds(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          count: ptr csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_suppress_tokens_count(native,
                                                                  count),
    proc (native: ptr ov_genai_whisper_generation_config; values: ptr int64;
          count: csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_suppress_tokens(native, values,
                                                            count),
    "Whisper suppress tokens")

proc whisperConfigString(config: WhisperGenerationConfig;
    getter: proc (native: ptr ov_genai_whisper_generation_config;
                  buffer: cstring; size: ptr csize_t): ov_status_e {.closure.};
    operation: string): string =
  var size: csize_t = 0
  checkGenAiStatus(getter(config.native(), nil, addr size),
                   "measure " & operation)
  if size == 0: return ""
  result = newString(int(size))
  checkGenAiStatus(getter(config.native(), result.cstring, addr size),
                   "read " & operation)
  result.setLen(int(size) - 1)

proc language*(config: WhisperGenerationConfig): string =
  whisperConfigString(config,
    proc (native: ptr ov_genai_whisper_generation_config; buffer: cstring;
          size: ptr csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_language(native, buffer, size),
    "Whisper language")

proc task*(config: WhisperGenerationConfig): string =
  whisperConfigString(config,
    proc (native: ptr ov_genai_whisper_generation_config; buffer: cstring;
          size: ptr csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_task(native, buffer, size),
    "Whisper task")

proc initialPrompt*(config: WhisperGenerationConfig): string =
  whisperConfigString(config,
    proc (native: ptr ov_genai_whisper_generation_config; buffer: cstring;
          size: ptr csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_initial_prompt(native, buffer,
                                                           size),
    "Whisper initial prompt")

proc hotwords*(config: WhisperGenerationConfig): string =
  whisperConfigString(config,
    proc (native: ptr ov_genai_whisper_generation_config; buffer: cstring;
          size: ptr csize_t): ov_status_e =
    ov_genai_whisper_generation_config_get_hotwords(native, buffer, size),
    "Whisper hotwords")

proc multilingual*(config: WhisperGenerationConfig): bool =
  var value = false
  checkGenAiStatus(ov_genai_whisper_generation_config_get_is_multilingual(
    config.native(), addr value), "get Whisper multilingual flag")
  result = value

proc returnTimestamps*(config: WhisperGenerationConfig): bool =
  var value = false
  checkGenAiStatus(ov_genai_whisper_generation_config_get_return_timestamps(
    config.native(), addr value), "get Whisper timestamp setting")
  result = value

proc tokenId(config: WhisperGenerationConfig;
    getter: proc (native: ptr ov_genai_whisper_generation_config;
                  value: ptr int64): ov_status_e {.closure.};
    operation: string): int64 =
  checkGenAiStatus(getter(config.native(), addr result), operation)

proc decoderStartTokenId*(config: WhisperGenerationConfig): int64 =
  tokenId(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          value: ptr int64): ov_status_e =
    ov_genai_whisper_generation_config_get_decoder_start_token_id(native,
                                                                    value),
    "get Whisper decoder start token")

proc padTokenId*(config: WhisperGenerationConfig): int64 =
  tokenId(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          value: ptr int64): ov_status_e =
    ov_genai_whisper_generation_config_get_pad_token_id(native, value),
    "get Whisper pad token")

proc translateTokenId*(config: WhisperGenerationConfig): int64 =
  tokenId(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          value: ptr int64): ov_status_e =
    ov_genai_whisper_generation_config_get_translate_token_id(native, value),
    "get Whisper translate token")

proc transcribeTokenId*(config: WhisperGenerationConfig): int64 =
  tokenId(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          value: ptr int64): ov_status_e =
    ov_genai_whisper_generation_config_get_transcribe_token_id(native, value),
    "get Whisper transcribe token")

proc previousStartTokenId*(config: WhisperGenerationConfig): int64 =
  tokenId(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          value: ptr int64): ov_status_e =
    ov_genai_whisper_generation_config_get_prev_sot_token_id(native, value),
    "get Whisper previous start token")

proc noTimestampsTokenId*(config: WhisperGenerationConfig): int64 =
  tokenId(config,
    proc (native: ptr ov_genai_whisper_generation_config;
          value: ptr int64): ov_status_e =
    ov_genai_whisper_generation_config_get_no_timestamps_token_id(native,
                                                                   value),
    "get Whisper no-timestamps token")

proc maxInitialTimestampIndex*(config: WhisperGenerationConfig): int =
  var value: csize_t = 0
  checkGenAiStatus(ov_genai_whisper_generation_config_get_max_initial_timestamp_index(
    config.native(), addr value), "get Whisper maximum initial timestamp")
  result = int(value)

proc generationConfig*(config: WhisperGenerationConfig): GenerationConfig =
  var nativeConfig: ptr ov_genai_generation_config = nil
  checkGenAiStatus(ov_genai_whisper_generation_config_get_generation_config(
    config.native(), addr nativeConfig), "get Whisper token generation config")
  result.handle = newHandle(nativeConfig, releaseGenerationConfig,
                            "GenAI generation config")


proc setDecoderStartTokenId*(config: WhisperGenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_decoder_start_token_id(
    config.native(), value), "set Whisper decoder start token")

proc setPadTokenId*(config: WhisperGenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_pad_token_id(
    config.native(), value), "set Whisper pad token")

proc setTranslateTokenId*(config: WhisperGenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_translate_token_id(
    config.native(), value), "set Whisper translate token")

proc setTranscribeTokenId*(config: WhisperGenerationConfig; value: int64) =
  checkGenAiStatus(ov_genai_whisper_generation_config_set_transcribe_token_id(
    config.native(), value), "set Whisper transcribe token")

proc optionalWhisperConfig(config: WhisperGenerationConfig):
    ptr ov_genai_whisper_generation_config =
  if config.handle == nil: nil else: config.native()

proc transcribe*(pipeline: WhisperPipeline; audio: openArray[float32];
                 config = WhisperGenerationConfig()): WhisperDecodedResults =
  ## Recognizes audio supplied as mono 16 kHz float32 samples.
  if audio.len == 0:
    raiseArgumentError("audio input must contain at least one sample")
  let rawAudio = if audio.len == 0: nil else: unsafeAddr audio[0]
  var nativeResults: ptr ov_genai_whisper_decoded_results = nil
  checkGenAiStatus(ov_genai_whisper_pipeline_generate(pipeline.native(),
    rawAudio, csize_t(audio.len), optionalWhisperConfig(config),
    addr nativeResults), "transcribe audio")
  result.handle = newHandle(nativeResults, releaseWhisperResults,
                            "GenAI Whisper decoded results")

proc close*(results: WhisperDecodedResults) = results.handle.close()

proc text*(results: WhisperDecodedResults): string =
  readSizedString(
    proc (buffer: cstring; size: ptr csize_t): ov_status_e =
    ov_genai_whisper_decoded_results_get_string(results.handle.native(),
                                                 buffer, size),
    proc (buffer: cstring; size: ptr csize_t): ov_status_e =
    ov_genai_whisper_decoded_results_get_string(results.handle.native(),
                                                 buffer, size),
    "Whisper result")

proc transcriptionCount*(results: WhisperDecodedResults): int =
  var count: csize_t = 0
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_texts_count(
    results.handle.native(), addr count), "get transcription count")
  result = int(count)

proc transcription*(results: WhisperDecodedResults; index = 0): string =
  if index < 0: raiseArgumentError("transcription index cannot be negative")
  var size: csize_t = 0
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_text_at(
    results.handle.native(), csize_t(index), nil, addr size),
    "measure transcription")
  if size == 0: return ""
  result = newString(int(size))
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_text_at(
    results.handle.native(), csize_t(index), result.cstring, addr size),
    "read transcription")
  result.setLen(int(size) - 1)

proc score*(results: WhisperDecodedResults; index = 0): float32 =
  if index < 0: raiseArgumentError("transcription index cannot be negative")
  var value: cfloat = 0
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_score_at(
    results.handle.native(), csize_t(index), addr value), "get transcription score")
  result = float32(value)

proc hasChunks*(results: WhisperDecodedResults): bool =
  var value = false
  checkGenAiStatus(ov_genai_whisper_decoded_results_has_chunks(
    results.handle.native(), addr value), "check transcription chunks")
  result = value

proc chunkCount*(results: WhisperDecodedResults): int =
  var count: csize_t = 0
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_chunks_count(
    results.handle.native(), addr count), "get transcription chunk count")
  result = int(count)

proc chunkAt*(results: WhisperDecodedResults; index: int): WhisperChunk =
  if index < 0: raiseArgumentError("transcription chunk index cannot be negative")
  var nativeChunk: ptr ov_genai_whisper_decoded_result_chunk = nil
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_chunk_at(
    results.handle.native(), csize_t(index), addr nativeChunk),
    "get transcription chunk")
  result.handle = newHandle(nativeChunk, releaseWhisperChunk,
                            "GenAI Whisper chunk")

proc close*(chunk: WhisperChunk) = chunk.handle.close()

proc chunkText*(chunk: WhisperChunk): string =
  var size: csize_t = 0
  checkGenAiStatus(ov_genai_whisper_decoded_result_chunk_get_text(
    chunk.native(), nil, addr size), "measure transcription chunk")
  if size == 0: return ""
  result = newString(int(size))
  checkGenAiStatus(ov_genai_whisper_decoded_result_chunk_get_text(
    chunk.native(), result.cstring, addr size), "read transcription chunk")
  result.setLen(int(size) - 1)

proc chunkTimestamps*(chunk: WhisperChunk): tuple[startTime, endTime: float32] =
  var startTime, endTime: cfloat = 0
  checkGenAiStatus(ov_genai_whisper_decoded_result_chunk_get_start_ts(
    chunk.native(), addr startTime), "get chunk start time")
  checkGenAiStatus(ov_genai_whisper_decoded_result_chunk_get_end_ts(
    chunk.native(), addr endTime), "get chunk end time")
  result = (float32(startTime), float32(endTime))

proc generationMetrics*(results: WhisperDecodedResults): PerfMetrics =
  var nativeMetrics: ptr ov_genai_perf_metrics = nil
  checkGenAiStatus(ov_genai_whisper_decoded_results_get_perf_metrics(
    results.handle.native(), addr nativeMetrics), "get Whisper metrics")
  result.handle = newHandle(nativeMetrics, releasePerfMetrics,
                            "GenAI performance metrics")

proc close*(metrics: PerfMetrics) = metrics.handle.close()

proc loadTime*(metrics: PerfMetrics): float32 =
  var value: cfloat = 0
  checkGenAiStatus(ov_genai_perf_metrics_get_load_time(
    metrics.native(), addr value), "get model load time")
  result = float32(value)

proc inputTokenCount*(metrics: PerfMetrics): int =
  var value: csize_t = 0
  checkGenAiStatus(ov_genai_perf_metrics_get_num_input_tokens(
    metrics.native(), addr value), "get input token count")
  result = int(value)

proc generatedTokenCount*(metrics: PerfMetrics): int =
  var value: csize_t = 0
  checkGenAiStatus(ov_genai_perf_metrics_get_num_generation_tokens(
    metrics.native(), addr value), "get generated token count")
  result = int(value)

proc timeToFirstToken*(metrics: PerfMetrics): tuple[mean, std: float32] =
  var mean, deviation: cfloat = 0
  checkGenAiStatus(ov_genai_perf_metrics_get_ttft(metrics.native(),
    addr mean, addr deviation), "get time to first token")
  result = (float32(mean), float32(deviation))

proc timePerOutputToken*(metrics: PerfMetrics): tuple[mean, std: float32] =
  var mean, deviation: cfloat = 0
  checkGenAiStatus(ov_genai_perf_metrics_get_tpot(metrics.native(),
    addr mean, addr deviation), "get time per output token")
  result = (float32(mean), float32(deviation))

proc throughput*(metrics: PerfMetrics): tuple[mean, std: float32] =
  var mean, deviation: cfloat = 0
  checkGenAiStatus(ov_genai_perf_metrics_get_throughput(metrics.native(),
    addr mean, addr deviation), "get generation throughput")
  result = (float32(mean), float32(deviation))

type MetricPairGetter = proc (native: ptr ov_genai_perf_metrics;
    mean, deviation: ptr cfloat): ov_status_e {.closure.}

proc metricPair(metrics: PerfMetrics; getter: MetricPairGetter;
                operation: string): tuple[mean, std: float32] =
  var mean, deviation: cfloat = 0
  checkGenAiStatus(getter(metrics.native(), addr mean, addr deviation),
                   "get " & operation)
  result = (float32(mean), float32(deviation))

proc inputTimePerToken*(metrics: PerfMetrics): tuple[mean, std: float32] =
  metricPair(metrics,
    proc (native: ptr ov_genai_perf_metrics; mean, deviation: ptr cfloat):
        ov_status_e =
    ov_genai_perf_metrics_get_ipot(native, mean, deviation),
    "input time per token")

proc inferenceDuration*(metrics: PerfMetrics): tuple[mean, std: float32] =
  metricPair(metrics,
    proc (native: ptr ov_genai_perf_metrics; mean, deviation: ptr cfloat):
        ov_status_e =
    ov_genai_perf_metrics_get_inference_duration(native, mean, deviation),
    "inference duration")

proc generationDuration*(metrics: PerfMetrics): tuple[mean, std: float32] =
  metricPair(metrics,
    proc (native: ptr ov_genai_perf_metrics; mean, deviation: ptr cfloat):
        ov_status_e =
    ov_genai_perf_metrics_get_generate_duration(native, mean, deviation),
    "generation duration")

proc tokenizationDuration*(metrics: PerfMetrics): tuple[mean, std: float32] =
  metricPair(metrics,
    proc (native: ptr ov_genai_perf_metrics; mean, deviation: ptr cfloat):
        ov_status_e =
    ov_genai_perf_metrics_get_tokenization_duration(native, mean, deviation),
    "tokenization duration")

proc detokenizationDuration*(metrics: PerfMetrics): tuple[mean, std: float32] =
  metricPair(metrics,
    proc (native: ptr ov_genai_perf_metrics; mean, deviation: ptr cfloat):
        ov_status_e =
    ov_genai_perf_metrics_get_detokenization_duration(native, mean, deviation),
    "detokenization duration")

proc chatTemplateDuration*(metrics: PerfMetrics): tuple[mean, std: float32] =
  metricPair(metrics,
    proc (native: ptr ov_genai_perf_metrics; mean, deviation: ptr cfloat):
        ov_status_e =
    ov_genai_perf_metrics_get_chat_template_duration(native, mean, deviation),
    "chat template duration")

proc addInPlace*(metrics: PerfMetrics; other: PerfMetrics) =
  checkGenAiStatus(ov_genai_perf_metrics_add_in_place(metrics.native(),
    other.native()), "add performance metrics")
