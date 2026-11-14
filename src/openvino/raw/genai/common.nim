# SPDX-License-Identifier: Apache-2.0

## Shared opaque types and enums from OpenVINO GenAI C 2026.4.1.0.

import ../common
import ../tensor

export ov_status_e, ov_tensor_t

type
  ov_genai_chat_history* = object
  ov_genai_decoded_results* = object
  ov_genai_generation_config* = object
  ov_genai_json_container* = object
  ov_genai_llm_pipeline* = object
  ov_genai_perf_metrics* = object
  ov_genai_vlm_decoded_results* = object
  ov_genai_vlm_pipeline* = object
  ov_genai_whisper_decoded_result_chunk * = object
  ov_genai_whisper_decoded_results* = object
  ov_genai_whisper_generation_config* = object
  ov_genai_whisper_pipeline* = object

  StopCriteria* = cint
    ## Upstream grouped beam-search termination policy.
  ov_genai_chat_history_status_e* = cint
  ov_genai_json_container_status_e* = cint
  ov_genai_streaming_status_e* = cint

  ov_genai_streamer_callback_fn* = proc (text: cstring; args: pointer):
    ov_genai_streaming_status_e {.cdecl.}
    ## C callback called synchronously from pipeline generation.

  ov_genai_streamer_callback* = object
    callbackFunc*: ov_genai_streamer_callback_fn
    args*: pointer

const
  EARLY* = StopCriteria(0)
  HEURISTIC* = StopCriteria(1)
  NEVER* = StopCriteria(2)

  OV_GENAI_STREAMING_STATUS_RUNNING* = ov_genai_streaming_status_e(0)
  OV_GENAI_STREAMING_STATUS_STOP* = ov_genai_streaming_status_e(1)
  OV_GENAI_STREAMING_STATUS_CANCEL* = ov_genai_streaming_status_e(2)

  OV_GENAI_CHAT_HISTORY_OK* = ov_genai_chat_history_status_e(0)
  OV_GENAI_CHAT_HISTORY_INVALID_PARAM* = ov_genai_chat_history_status_e(-1)
  OV_GENAI_CHAT_HISTORY_OUT_OF_BOUNDS* = ov_genai_chat_history_status_e(-2)
  OV_GENAI_CHAT_HISTORY_EMPTY* = ov_genai_chat_history_status_e(-3)
  OV_GENAI_CHAT_HISTORY_INVALID_JSON* = ov_genai_chat_history_status_e(-4)
  OV_GENAI_CHAT_HISTORY_ERROR* = ov_genai_chat_history_status_e(-5)

  OV_GENAI_JSON_CONTAINER_OK* = ov_genai_json_container_status_e(0)
  OV_GENAI_JSON_CONTAINER_INVALID_PARAM * = ov_genai_json_container_status_e(-1)
  OV_GENAI_JSON_CONTAINER_INVALID_JSON * = ov_genai_json_container_status_e(-2)
  OV_GENAI_JSON_CONTAINER_OUT_OF_BOUNDS * = ov_genai_json_container_status_e(-3)
  OV_GENAI_JSON_CONTAINER_ERROR* = ov_genai_json_container_status_e(-4)
