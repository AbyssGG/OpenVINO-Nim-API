# SPDX-License-Identifier: Apache-2.0

## End-to-end GenAI checks using locally installed C APIs and models.
##
## Set OPENVINO_GENAI_TEST_MODEL to an OpenVINO LLM model directory,
## OPENVINO_GENAI_TEST_WHISPER_MODEL to an OpenVINO Whisper model directory,
## OPENVINO_GENAI_TEST_AUDIO_F32 to mono 16 kHz float32 PCM samples, and make
## the OpenVINO Runtime, GenAI and Tokenizers libraries discoverable.

import std/[os, strutils, unittest]

import openvino
import openvino/raw/genai as rawGenAi

const expectedSymbols = rawGenAi.GenAiApiSymbols

proc loadFloatSamples(path: string): seq[float32] =
  let byteCount = getFileSize(path)
  if byteCount <= 0 or byteCount mod int64(sizeof(float32)) != 0:
    raise newException(ValueError,
      "audio sample file must contain raw float32 PCM samples")
  var file: File
  if not file.open(path, fmRead):
    raise newException(IOError, "cannot open audio samples: " & path)
  defer: file.close()
  result = newSeq[float32](int(byteCount div int64(sizeof(float32))))
  let readCount = file.readBuffer(addr result[0], int(byteCount))
  if readCount != int(byteCount):
    raise newException(IOError, "audio sample file was truncated while reading")

suite "OpenVINO GenAI C API":
  test "all pinned C header symbols are exported by the installed library":
    let missing = rawGenAi.missingGenAiSymbols(expectedSymbols)
    checkpoint("missing symbols: " & $missing)
    check missing.len == 0

  test "JSON and chat history manage owned C handles":
    let message = jsonFromString("""{"role":"user","content":"hello"}""")
    check "hello" in message.toJson()
    check newJsonObject().toJson() == "{}"
    check newJsonArray().toJson() == "[]"
    check message.copy().toJson() == message.toJson()
    let history = newChatHistory()
    history.pushBack(message)
    check history.len() == 1
    check not history.isEmpty()
    check "hello" in history.firstMessage().toJson()
    check "hello" in history.messageAt(0).toJson()
    check "hello" in history.messages().toJson()
    check "hello" in history.lastMessage().toJson()
    let tools = jsonFromString("""[{"type":"function"}]""")
    history.setTools(tools)
    check history.tools().toJson() == tools.toJson()
    let context = jsonFromString("""{"trace":"test"}""")
    history.setExtraContext(context)
    check history.extraContext().toJson() == context.toJson()
    let fromJson = chatHistoryFromJson(jsonFromString(
      """[{"role":"user","content":"from array"}]"""))
    check fromJson.len() == 1
    check "from array" in fromJson.firstMessage().toJson()
    history.popBack()
    check history.isEmpty()
    history.pushBack(message)
    history.clear()
    check history.isEmpty()

  test "generation configuration accepts and validates settings":
    let config = newGenerationConfig()
    config.setMaxNewTokens(8)
    config.setDoSample(false)
    config.setTemperature(0.0)
    config.setStopStrings(["<END>", "###"])
    config.setStopStrings([]) # clearing an array must pass a non-null C pointer
    config.setStopCriteria(scEarly)
    config.validate()
    check config.maxNewTokens() == 8

    let allSettings = newGenerationConfig()
    allSettings.setMaxLength(128)
    allSettings.setMinNewTokens(1)
    allSettings.setIgnoreEos(false)
    allSettings.setEcho(false)
    allSettings.setLogprobs(1)
    allSettings.setIncludeStopString(true)
    allSettings.setStopTokenIds([2'i64])
    allSettings.setNumBeamGroups(1)
    allSettings.setNumBeams(1)
    allSettings.setDiversityPenalty(0.0)
    allSettings.setLengthPenalty(1.0)
    allSettings.setNumReturnSequences(1)
    allSettings.setNoRepeatNgramSize(0)
    allSettings.setTopP(1.0)
    allSettings.setTopK(40)
    allSettings.setMinP(0.0)
    allSettings.setRepetitionPenalty(1.0)
    allSettings.setPresencePenalty(0.0)
    allSettings.setFrequencyPenalty(0.0)
    allSettings.setRngSeed(42)
    allSettings.setAssistantConfidenceThreshold(0.5)
    allSettings.setNumAssistantTokens(3)
    allSettings.setMaxNgramSize(3)
    allSettings.setEosTokenId(2)

  test "LLM text, history, streaming, properties and metrics work on CPU":
    let modelPath = getEnv("OPENVINO_GENAI_TEST_MODEL")
    check modelPath.len > 0
    let jsonConfig = generationConfigFromJson(modelPath / "generation_config.json")
    jsonConfig.setMaxNewTokens(8)
    check jsonConfig.maxNewTokens() == 8
    let config = newGenerationConfig()
    config.setMaxNewTokens(8)
    config.setDoSample(false)
    let pipeline = newLlmPipeline(modelPath, "CPU", @[
      ("PERFORMANCE_HINT", "LATENCY")])
    pipeline.setGenerationConfig(config)
    check pipeline.generationConfig().maxNewTokens() == 8
    pipeline.startChat()
    pipeline.finishChat()

    let response = pipeline.generate("Say hello in one word.", config)
    check response.text().len > 0
    let metrics = response.generationMetrics()
    check metrics.generatedTokenCount() > 0
    discard metrics.loadTime()
    discard metrics.inputTokenCount()
    discard metrics.timeToFirstToken()
    discard metrics.timePerOutputToken()
    discard metrics.throughput()
    discard metrics.inputTimePerToken()
    discard metrics.inferenceDuration()
    discard metrics.generationDuration()
    discard metrics.tokenizationDuration()
    discard metrics.detokenizationDuration()
    discard metrics.chatTemplateDuration()

    var streamed = ""
    let complete = pipeline.streamGenerate("Say hi.", proc (piece: string):
        StreamAction =
      streamed.add(piece)
      streamContinue, config)
    check complete.len > 0
    check complete == streamed

    var pieceCount = 0
    let stopped = pipeline.streamGenerate("Say hello.", proc (_: string):
        StreamAction =
      inc pieceCount
      streamStop, config)
    check pieceCount > 0
    check pieceCount < 8
    check stopped.len > 0

    var cancelledPieces = 0
    let cancelled = pipeline.streamGenerate("Say hello.", proc (_: string):
        StreamAction =
      inc cancelledPieces
      streamCancel, config)
    check cancelledPieces > 0
    check cancelled.len > 0

    var callbackErrorWasRethrown = false
    try:
      discard pipeline.streamGenerate("Say hello.", proc (_: string):
          StreamAction =
        raise newException(ValueError, "stream callback failed"), config)
    except GenAiCallbackError as error:
      callbackErrorWasRethrown =
        error.callbackMessage == "stream callback failed"
    check callbackErrorWasRethrown

    let history = newChatHistory()
    history.pushBack(jsonFromString(
      """{"role":"user","content":"Answer with one word: yes"}"""))
    let historyResult = pipeline.generate(history, config)
    check historyResult.text().len > 0
    metrics.addInPlace(historyResult.generationMetrics())
    check pipeline.streamGenerate(history, proc (piece: string): StreamAction =
      streamContinue, config).len > 0

  test "Whisper configuration, timestamps, scores and metrics work on CPU":
    let modelPath = getEnv("OPENVINO_GENAI_TEST_WHISPER_MODEL")
    let audioPath = getEnv("OPENVINO_GENAI_TEST_AUDIO_F32")
    check modelPath.len > 0
    check audioPath.len > 0
    let modelConfigPath = modelPath / "generation_config.json"
    if fileExists(modelConfigPath):
      let loadedConfig = whisperGenerationConfigFromJson(modelConfigPath)
      check loadedConfig.decoderStartTokenId() == 50258
      check loadedConfig.maxInitialTimestampIndex() == 50
    let samples = loadFloatSamples(audioPath)
    let config = newWhisperGenerationConfig()
    config.setLanguage("en")
    config.setTask("transcribe")
    config.setReturnTimestamps(true)
    check config.language() == "en"
    check config.task() == "transcribe"
    check config.returnTimestamps()

    let pipeline = newWhisperPipeline(modelPath)
    let result = pipeline.transcribe(samples, config)
    config.setInitialPrompt("Use clear punctuation.")
    config.setHotwords("OpenVINO")
    check config.initialPrompt() == "Use clear punctuation."
    check config.hotwords() == "OpenVINO"
    check result.transcriptionCount() == 1
    check "How are you doing today?" in result.transcription()
    check result.hasChunks()
    check result.chunkCount() > 0
    let chunk = result.chunkAt(0)
    check "How are you doing today?" in chunk.chunkText()
    check chunk.chunkTimestamps().endTime > chunk.chunkTimestamps().startTime
    let metrics = result.generationMetrics()
    check metrics.generatedTokenCount() > 0
    discard result.text()
    discard result.score(0)
    discard metrics.loadTime()
    discard metrics.inputTokenCount()
    discard metrics.timeToFirstToken()
    discard metrics.timePerOutputToken()
    discard metrics.throughput()
    discard metrics.inputTimePerToken()
    discard metrics.inferenceDuration()
    discard metrics.generationDuration()
    discard metrics.tokenizationDuration()
    discard metrics.detokenizationDuration()
    discard metrics.chatTemplateDuration()

    config.setIsMultilingual(true)
    config.setPreviousStartTokenId(50361)
    config.setNoTimestampsTokenId(50363)
    config.setDecoderStartTokenId(50258)
    config.setPadTokenId(50257)
    config.setTranslateTokenId(50358)
    config.setTranscribeTokenId(50359)
    config.setMaxInitialTimestampIndex(50)
    config.setBeginSuppressTokens([220'i64, 50257'i64])
    config.setSuppressTokens([1'i64, 2'i64, 7'i64])
    check config.multilingual()
    check config.previousStartTokenId() == 50361
    check config.noTimestampsTokenId() == 50363
    check config.decoderStartTokenId() == 50258
    check config.padTokenId() == 50257
    check config.translateTokenId() == 50358
    check config.transcribeTokenId() == 50359
    check config.maxInitialTimestampIndex() == 50
    check config.beginSuppressTokens() == @[220'i64, 50257'i64]
    check config.suppressTokens() == @[1'i64, 2'i64, 7'i64]
    pipeline.setGenerationConfig(pipeline.generationConfig())
