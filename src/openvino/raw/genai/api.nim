# SPDX-License-Identifier: Apache-2.0

## Header-faithful dynamic declarations for the OpenVINO GenAI C API.
##
## Generated against upstream OpenVINO GenAI 2026.4.1.0 C headers. The
## optional GenAI shared library is resolved lazily through `genaiImport`;
## importing this module does not require GenAI to be installed.

import ../common
import ../tensor
import common
import loader

{.push styleChecks: off.}

proc ov_genai_chat_history_clear*(history: ptr ov_genai_chat_history): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_clear`.

proc ov_genai_chat_history_create*(history: ptr ptr ov_genai_chat_history): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_create`.

proc ov_genai_chat_history_create_from_json_container*(
  history: ptr ptr ov_genai_chat_history,
    messages: ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_create_from_json_container`.

proc ov_genai_chat_history_empty*(history: ptr ov_genai_chat_history,
    empty: ptr cint): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_empty`.

proc ov_genai_chat_history_free*(history: ptr ov_genai_chat_history) {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_free`.

proc ov_genai_chat_history_get_extra_context*(
  history: ptr ov_genai_chat_history,
    extra_context: ptr ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_get_extra_context`.

proc ov_genai_chat_history_get_first*(history: ptr ov_genai_chat_history,
    message: ptr ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_get_first`.

proc ov_genai_chat_history_get_last*(history: ptr ov_genai_chat_history,
    message: ptr ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_get_last`.

proc ov_genai_chat_history_get_message*(history: ptr ov_genai_chat_history,
    index: csize_t,
    message: ptr ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_get_message`.

proc ov_genai_chat_history_get_messages*(history: ptr ov_genai_chat_history,
    messages: ptr ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_get_messages`.

proc ov_genai_chat_history_get_tools*(history: ptr ov_genai_chat_history,
    tools: ptr ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_get_tools`.

proc ov_genai_chat_history_pop_back*(history: ptr ov_genai_chat_history): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_pop_back`.

proc ov_genai_chat_history_push_back*(history: ptr ov_genai_chat_history,
    message: ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_push_back`.

proc ov_genai_chat_history_set_extra_context*(
  history: ptr ov_genai_chat_history,
    extra_context: ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_set_extra_context`.

proc ov_genai_chat_history_set_tools*(history: ptr ov_genai_chat_history,
    tools: ptr ov_genai_json_container): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_set_tools`.

proc ov_genai_chat_history_size*(history: ptr ov_genai_chat_history,
    size: ptr csize_t): ov_genai_chat_history_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_chat_history_size`.

proc ov_genai_decoded_results_create*(results: ptr ptr ov_genai_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_decoded_results_create`.

proc ov_genai_decoded_results_free*(results: ptr ov_genai_decoded_results) {.genaiImport.}

  ## Upstream C function `ov_genai_decoded_results_free`.

proc ov_genai_decoded_results_get_perf_metrics*(
  results: ptr ov_genai_decoded_results,
    metrics: ptr ptr ov_genai_perf_metrics): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_decoded_results_get_perf_metrics`.

proc ov_genai_decoded_results_get_string*(results: ptr ov_genai_decoded_results,
    output: cstring, output_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_decoded_results_get_string`.

proc ov_genai_decoded_results_perf_metrics_free*(
  metrics: ptr ov_genai_perf_metrics) {.genaiImport.}

  ## Upstream C function `ov_genai_decoded_results_perf_metrics_free`.

proc ov_genai_generation_config_create*(
  config: ptr ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_create`.

proc ov_genai_generation_config_create_from_json*(json_path: cstring,
    config: ptr ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_create_from_json`.

proc ov_genai_generation_config_free*(handle: ptr ov_genai_generation_config) {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_free`.

proc ov_genai_generation_config_get_max_new_tokens*(
  config: ptr ov_genai_generation_config,
    max_new_tokens: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_get_max_new_tokens`.

proc ov_genai_generation_config_set_assistant_confidence_threshold*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_assistant_confidence_threshold`.

proc ov_genai_generation_config_set_diversity_penalty*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_diversity_penalty`.

proc ov_genai_generation_config_set_do_sample*(
  config: ptr ov_genai_generation_config,
    value: bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_do_sample`.

proc ov_genai_generation_config_set_echo*(
  config: ptr ov_genai_generation_config,
    value: bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_echo`.

proc ov_genai_generation_config_set_eos_token_id*(
  config: ptr ov_genai_generation_config,
    id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_eos_token_id`.

proc ov_genai_generation_config_set_frequency_penalty*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_frequency_penalty`.

proc ov_genai_generation_config_set_ignore_eos*(
  config: ptr ov_genai_generation_config,
    value: bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_ignore_eos`.

proc ov_genai_generation_config_set_include_stop_str_in_output*(
  config: ptr ov_genai_generation_config,
    value: bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_include_stop_str_in_output`.

proc ov_genai_generation_config_set_length_penalty*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_length_penalty`.

proc ov_genai_generation_config_set_logprobs*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_logprobs`.

proc ov_genai_generation_config_set_max_length*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_max_length`.

proc ov_genai_generation_config_set_max_new_tokens*(
  handle: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_max_new_tokens`.

proc ov_genai_generation_config_set_max_ngram_size*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_max_ngram_size`.

proc ov_genai_generation_config_set_min_new_tokens*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_min_new_tokens`.

proc ov_genai_generation_config_set_min_p*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_min_p`.

proc ov_genai_generation_config_set_no_repeat_ngram_size*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_no_repeat_ngram_size`.

proc ov_genai_generation_config_set_num_assistant_tokens*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_num_assistant_tokens`.

proc ov_genai_generation_config_set_num_beam_groups*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_num_beam_groups`.

proc ov_genai_generation_config_set_num_beams*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_num_beams`.

proc ov_genai_generation_config_set_num_return_sequences*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_num_return_sequences`.

proc ov_genai_generation_config_set_presence_penalty*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_presence_penalty`.

proc ov_genai_generation_config_set_repetition_penalty*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_repetition_penalty`.

proc ov_genai_generation_config_set_rng_seed*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_rng_seed`.

proc ov_genai_generation_config_set_stop_criteria*(
  config: ptr ov_genai_generation_config,
    value: StopCriteria): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_stop_criteria`.

proc ov_genai_generation_config_set_stop_strings*(
  config: ptr ov_genai_generation_config, strings: ptr cstring,
    count: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_stop_strings`.

proc ov_genai_generation_config_set_stop_token_ids*(
  config: ptr ov_genai_generation_config, token_ids: ptr int64,
    token_ids_num: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_stop_token_ids`.

proc ov_genai_generation_config_set_temperature*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_temperature`.

proc ov_genai_generation_config_set_top_k*(
  config: ptr ov_genai_generation_config,
    value: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_top_k`.

proc ov_genai_generation_config_set_top_p*(
  config: ptr ov_genai_generation_config,
    value: cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_set_top_p`.

proc ov_genai_generation_config_validate*(
  config: ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_generation_config_validate`.

proc ov_genai_json_container_copy*(source: ptr ov_genai_json_container,
    target: ptr ptr ov_genai_json_container): ov_genai_json_container_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_copy`.

proc ov_genai_json_container_create*(container: ptr ptr ov_genai_json_container): ov_genai_json_container_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_create`.

proc ov_genai_json_container_create_array*(
  container: ptr ptr ov_genai_json_container): ov_genai_json_container_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_create_array`.

proc ov_genai_json_container_create_from_json_string*(
  container: ptr ptr ov_genai_json_container,
    json_str: cstring): ov_genai_json_container_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_create_from_json_string`.

proc ov_genai_json_container_create_object*(
  container: ptr ptr ov_genai_json_container): ov_genai_json_container_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_create_object`.

proc ov_genai_json_container_free*(container: ptr ov_genai_json_container) {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_free`.

proc ov_genai_json_container_to_json_string*(
  container: ptr ov_genai_json_container, output: cstring,
    output_size: ptr csize_t): ov_genai_json_container_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_json_container_to_json_string`.

proc ov_genai_llm_pipeline_finish_chat*(
  pipe: ptr ov_genai_llm_pipeline): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_finish_chat`.

proc ov_genai_llm_pipeline_free*(pipe: ptr ov_genai_llm_pipeline) {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_free`.

proc ov_genai_llm_pipeline_generate*(pipe: ptr ov_genai_llm_pipeline,
    inputs: cstring, config: ptr ov_genai_generation_config,
    streamer: ptr ov_genai_streamer_callback,
    results: ptr ptr ov_genai_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_generate`.

proc ov_genai_llm_pipeline_generate_with_history*(
  pipe: ptr ov_genai_llm_pipeline, history: ptr ov_genai_chat_history,
    config: ptr ov_genai_generation_config,
    streamer: ptr ov_genai_streamer_callback,
    results: ptr ptr ov_genai_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_generate_with_history`.

proc ov_genai_llm_pipeline_get_generation_config*(
  pipe: ptr ov_genai_llm_pipeline,
    config: ptr ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_get_generation_config`.

proc ov_genai_llm_pipeline_set_generation_config*(
  pipe: ptr ov_genai_llm_pipeline,
    config: ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_set_generation_config`.

proc ov_genai_llm_pipeline_start_chat*(pipe: ptr ov_genai_llm_pipeline): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_llm_pipeline_start_chat`.

proc ov_genai_perf_metrics_add_in_place*(left: ptr ov_genai_perf_metrics,
    right: ptr ov_genai_perf_metrics): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_add_in_place`.

proc ov_genai_perf_metrics_get_chat_template_duration*(
  metrics: ptr ov_genai_perf_metrics, mean: ptr cfloat,
    std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_chat_template_duration`.

proc ov_genai_perf_metrics_get_detokenization_duration*(
  metrics: ptr ov_genai_perf_metrics, mean: ptr cfloat,
    std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_detokenization_duration`.

proc ov_genai_perf_metrics_get_generate_duration*(
  metrics: ptr ov_genai_perf_metrics, mean: ptr cfloat,
    std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_generate_duration`.

proc ov_genai_perf_metrics_get_inference_duration*(
  metrics: ptr ov_genai_perf_metrics, mean: ptr cfloat,
    std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_inference_duration`.

proc ov_genai_perf_metrics_get_ipot*(metrics: ptr ov_genai_perf_metrics,
    mean: ptr cfloat, std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_ipot`.

proc ov_genai_perf_metrics_get_load_time*(metrics: ptr ov_genai_perf_metrics,
    load_time: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_load_time`.

proc ov_genai_perf_metrics_get_num_generation_tokens*(
  metrics: ptr ov_genai_perf_metrics,
    num_generation_tokens: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_num_generation_tokens`.

proc ov_genai_perf_metrics_get_num_input_tokens*(
  metrics: ptr ov_genai_perf_metrics,
    num_input_tokens: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_num_input_tokens`.

proc ov_genai_perf_metrics_get_throughput*(metrics: ptr ov_genai_perf_metrics,
    mean: ptr cfloat, std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_throughput`.

proc ov_genai_perf_metrics_get_tokenization_duration*(
  metrics: ptr ov_genai_perf_metrics, mean: ptr cfloat,
    std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_tokenization_duration`.

proc ov_genai_perf_metrics_get_tpot*(metrics: ptr ov_genai_perf_metrics,
    mean: ptr cfloat, std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_tpot`.

proc ov_genai_perf_metrics_get_ttft*(metrics: ptr ov_genai_perf_metrics,
    mean: ptr cfloat, std: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_perf_metrics_get_ttft`.

proc ov_genai_vlm_decoded_results_create*(
  results: ptr ptr ov_genai_vlm_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_decoded_results_create`.

proc ov_genai_vlm_decoded_results_free*(
  results: ptr ov_genai_vlm_decoded_results) {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_decoded_results_free`.

proc ov_genai_vlm_decoded_results_get_perf_metrics*(
  results: ptr ov_genai_vlm_decoded_results,
    metrics: ptr ptr ov_genai_perf_metrics): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_decoded_results_get_perf_metrics`.

proc ov_genai_vlm_decoded_results_get_string*(
  results: ptr ov_genai_vlm_decoded_results, output: cstring,
    output_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_decoded_results_get_string`.

proc ov_genai_vlm_decoded_results_perf_metrics_free*(
  metrics: ptr ov_genai_perf_metrics) {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_decoded_results_perf_metrics_free`.

proc ov_genai_vlm_pipeline_finish_chat*(
  pipe: ptr ov_genai_vlm_pipeline): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_finish_chat`.

proc ov_genai_vlm_pipeline_free*(pipe: ptr ov_genai_vlm_pipeline) {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_free`.

proc ov_genai_vlm_pipeline_generate*(pipe: ptr ov_genai_vlm_pipeline,
    text_inputs: cstring, rgbs: ptr ptr ov_tensor_t, num_images: csize_t,
    config: ptr ov_genai_generation_config,
    streamer: ptr ov_genai_streamer_callback,
    results: ptr ptr ov_genai_vlm_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_generate`.

proc ov_genai_vlm_pipeline_generate_with_history*(
  pipe: ptr ov_genai_vlm_pipeline, history: ptr ov_genai_chat_history,
    rgbs: ptr ptr ov_tensor_t, num_images: csize_t,
    config: ptr ov_genai_generation_config,
    streamer: ptr ov_genai_streamer_callback,
    results: ptr ptr ov_genai_vlm_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_generate_with_history`.

proc ov_genai_vlm_pipeline_get_generation_config*(
  pipe: ptr ov_genai_vlm_pipeline,
    config: ptr ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_get_generation_config`.

proc ov_genai_vlm_pipeline_set_generation_config*(
  pipe: ptr ov_genai_vlm_pipeline,
    config: ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_set_generation_config`.

proc ov_genai_vlm_pipeline_start_chat*(pipe: ptr ov_genai_vlm_pipeline): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_vlm_pipeline_start_chat`.

proc ov_genai_whisper_decoded_result_chunk_create*(
  chunk: ptr ptr ov_genai_whisper_decoded_result_chunk): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_result_chunk_create`.

proc ov_genai_whisper_decoded_result_chunk_free*(
  chunk: ptr ov_genai_whisper_decoded_result_chunk) {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_result_chunk_free`.

proc ov_genai_whisper_decoded_result_chunk_get_end_ts*(
  chunk: ptr ov_genai_whisper_decoded_result_chunk,
    end_ts: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_result_chunk_get_end_ts`.

proc ov_genai_whisper_decoded_result_chunk_get_start_ts*(
  chunk: ptr ov_genai_whisper_decoded_result_chunk,
    start_ts: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_result_chunk_get_start_ts`.

proc ov_genai_whisper_decoded_result_chunk_get_text*(
  chunk: ptr ov_genai_whisper_decoded_result_chunk, text: cstring,
    text_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_result_chunk_get_text`.

proc ov_genai_whisper_decoded_results_create*(
  results: ptr ptr ov_genai_whisper_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_create`.

proc ov_genai_whisper_decoded_results_free*(
  results: ptr ov_genai_whisper_decoded_results) {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_free`.

proc ov_genai_whisper_decoded_results_get_chunk_at*(
  results: ptr ov_genai_whisper_decoded_results, index: csize_t,
    chunk: ptr ptr ov_genai_whisper_decoded_result_chunk): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_chunk_at`.

proc ov_genai_whisper_decoded_results_get_chunks_count*(
  results: ptr ov_genai_whisper_decoded_results,
    count: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_chunks_count`.

proc ov_genai_whisper_decoded_results_get_perf_metrics*(
  results: ptr ov_genai_whisper_decoded_results,
    metrics: ptr ptr ov_genai_perf_metrics): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_perf_metrics`.

proc ov_genai_whisper_decoded_results_get_score_at*(
  results: ptr ov_genai_whisper_decoded_results, index: csize_t,
    score: ptr cfloat): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_score_at`.

proc ov_genai_whisper_decoded_results_get_string*(
  results: ptr ov_genai_whisper_decoded_results, output: cstring,
    output_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_string`.

proc ov_genai_whisper_decoded_results_get_text_at*(
  results: ptr ov_genai_whisper_decoded_results, index: csize_t, text: cstring,
    text_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_text_at`.

proc ov_genai_whisper_decoded_results_get_texts_count*(
  results: ptr ov_genai_whisper_decoded_results,
    count: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_get_texts_count`.

proc ov_genai_whisper_decoded_results_has_chunks*(
  results: ptr ov_genai_whisper_decoded_results,
    has_chunks: ptr bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_decoded_results_has_chunks`.

proc ov_genai_whisper_generation_config_create*(
  config: ptr ptr ov_genai_whisper_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_create`.

proc ov_genai_whisper_generation_config_create_from_json*(json_path: cstring,
    config: ptr ptr ov_genai_whisper_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_create_from_json`.

proc ov_genai_whisper_generation_config_free*(
  config: ptr ov_genai_whisper_generation_config) {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_free`.

proc ov_genai_whisper_generation_config_get_begin_suppress_tokens*(
  config: ptr ov_genai_whisper_generation_config, tokens: ptr int64,
    tokens_count: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_begin_suppress_tokens`.

proc ov_genai_whisper_generation_config_get_begin_suppress_tokens_count*(
  config: ptr ov_genai_whisper_generation_config,
    tokens_count: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_begin_suppress_tokens_count`.

proc ov_genai_whisper_generation_config_get_decoder_start_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: ptr int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_decoder_start_token_id`.

proc ov_genai_whisper_generation_config_get_generation_config*(
  config: ptr ov_genai_whisper_generation_config,
    generation_config: ptr ptr ov_genai_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_generation_config`.

proc ov_genai_whisper_generation_config_get_hotwords*(
  config: ptr ov_genai_whisper_generation_config, hotwords: cstring,
    hotwords_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_hotwords`.

proc ov_genai_whisper_generation_config_get_initial_prompt*(
  config: ptr ov_genai_whisper_generation_config, initial_prompt: cstring,
    prompt_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_initial_prompt`.

proc ov_genai_whisper_generation_config_get_is_multilingual*(
  config: ptr ov_genai_whisper_generation_config,
    is_multilingual: ptr bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_is_multilingual`.

proc ov_genai_whisper_generation_config_get_language*(
  config: ptr ov_genai_whisper_generation_config, language: cstring,
    language_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_language`.

proc ov_genai_whisper_generation_config_get_max_initial_timestamp_index*(
  config: ptr ov_genai_whisper_generation_config,
    index: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_max_initial_timestamp_index`.

proc ov_genai_whisper_generation_config_get_no_timestamps_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: ptr int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_no_timestamps_token_id`.

proc ov_genai_whisper_generation_config_get_pad_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: ptr int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_pad_token_id`.

proc ov_genai_whisper_generation_config_get_prev_sot_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: ptr int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_prev_sot_token_id`.

proc ov_genai_whisper_generation_config_get_return_timestamps*(
  config: ptr ov_genai_whisper_generation_config,
    return_timestamps: ptr bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_return_timestamps`.

proc ov_genai_whisper_generation_config_get_suppress_tokens*(
  config: ptr ov_genai_whisper_generation_config, tokens: ptr int64,
    tokens_count: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_suppress_tokens`.

proc ov_genai_whisper_generation_config_get_suppress_tokens_count*(
  config: ptr ov_genai_whisper_generation_config,
    tokens_count: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_suppress_tokens_count`.

proc ov_genai_whisper_generation_config_get_task*(
  config: ptr ov_genai_whisper_generation_config, task: cstring,
    task_size: ptr csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_task`.

proc ov_genai_whisper_generation_config_get_transcribe_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: ptr int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_transcribe_token_id`.

proc ov_genai_whisper_generation_config_get_translate_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: ptr int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_get_translate_token_id`.

proc ov_genai_whisper_generation_config_set_begin_suppress_tokens*(
  config: ptr ov_genai_whisper_generation_config, tokens: ptr int64,
    tokens_count: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_begin_suppress_tokens`.

proc ov_genai_whisper_generation_config_set_decoder_start_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_decoder_start_token_id`.

proc ov_genai_whisper_generation_config_set_hotwords*(
  config: ptr ov_genai_whisper_generation_config,
    hotwords: cstring): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_hotwords`.

proc ov_genai_whisper_generation_config_set_initial_prompt*(
  config: ptr ov_genai_whisper_generation_config,
    initial_prompt: cstring): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_initial_prompt`.

proc ov_genai_whisper_generation_config_set_is_multilingual*(
  config: ptr ov_genai_whisper_generation_config,
    is_multilingual: bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_is_multilingual`.

proc ov_genai_whisper_generation_config_set_language*(
  config: ptr ov_genai_whisper_generation_config,
    language: cstring): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_language`.

proc ov_genai_whisper_generation_config_set_max_initial_timestamp_index*(
  config: ptr ov_genai_whisper_generation_config,
    index: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_max_initial_timestamp_index`.

proc ov_genai_whisper_generation_config_set_no_timestamps_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_no_timestamps_token_id`.

proc ov_genai_whisper_generation_config_set_pad_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_pad_token_id`.

proc ov_genai_whisper_generation_config_set_prev_sot_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_prev_sot_token_id`.

proc ov_genai_whisper_generation_config_set_return_timestamps*(
  config: ptr ov_genai_whisper_generation_config,
    return_timestamps: bool): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_return_timestamps`.

proc ov_genai_whisper_generation_config_set_suppress_tokens*(
  config: ptr ov_genai_whisper_generation_config, tokens: ptr int64,
    tokens_count: csize_t): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_suppress_tokens`.

proc ov_genai_whisper_generation_config_set_task*(
  config: ptr ov_genai_whisper_generation_config,
    task: cstring): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_task`.

proc ov_genai_whisper_generation_config_set_transcribe_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_transcribe_token_id`.

proc ov_genai_whisper_generation_config_set_translate_token_id*(
  config: ptr ov_genai_whisper_generation_config,
    token_id: int64): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_set_translate_token_id`.

proc ov_genai_whisper_generation_config_validate*(
  config: ptr ov_genai_whisper_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_generation_config_validate`.

proc ov_genai_whisper_pipeline_free*(pipeline: ptr ov_genai_whisper_pipeline) {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_pipeline_free`.

proc ov_genai_whisper_pipeline_generate*(
  pipeline: ptr ov_genai_whisper_pipeline, raw_speech: ptr cfloat,
    raw_speech_size: csize_t, config: ptr ov_genai_whisper_generation_config,
    results: ptr ptr ov_genai_whisper_decoded_results): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_pipeline_generate`.

proc ov_genai_whisper_pipeline_get_generation_config*(
  pipeline: ptr ov_genai_whisper_pipeline,
    config: ptr ptr ov_genai_whisper_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_pipeline_get_generation_config`.

proc ov_genai_whisper_pipeline_set_generation_config*(
  pipeline: ptr ov_genai_whisper_pipeline,
    config: ptr ov_genai_whisper_generation_config): ov_status_e {.genaiImport.}

  ## Upstream C function `ov_genai_whisper_pipeline_set_generation_config`.

const
  GenAiApiSymbols* = array[153, string]([
    "ov_genai_chat_history_clear",
    "ov_genai_chat_history_create",
    "ov_genai_chat_history_create_from_json_container",
    "ov_genai_chat_history_empty",
    "ov_genai_chat_history_free",
    "ov_genai_chat_history_get_extra_context",
    "ov_genai_chat_history_get_first",
    "ov_genai_chat_history_get_last",
    "ov_genai_chat_history_get_message",
    "ov_genai_chat_history_get_messages",
    "ov_genai_chat_history_get_tools",
    "ov_genai_chat_history_pop_back",
    "ov_genai_chat_history_push_back",
    "ov_genai_chat_history_set_extra_context",
    "ov_genai_chat_history_set_tools",
    "ov_genai_chat_history_size",
    "ov_genai_decoded_results_create",
    "ov_genai_decoded_results_free",
    "ov_genai_decoded_results_get_perf_metrics",
    "ov_genai_decoded_results_get_string",
    "ov_genai_decoded_results_perf_metrics_free",
    "ov_genai_generation_config_create",
    "ov_genai_generation_config_create_from_json",
    "ov_genai_generation_config_free",
    "ov_genai_generation_config_get_max_new_tokens",
    "ov_genai_generation_config_set_assistant_confidence_threshold",
    "ov_genai_generation_config_set_diversity_penalty",
    "ov_genai_generation_config_set_do_sample",
    "ov_genai_generation_config_set_echo",
    "ov_genai_generation_config_set_eos_token_id",
    "ov_genai_generation_config_set_frequency_penalty",
    "ov_genai_generation_config_set_ignore_eos",
    "ov_genai_generation_config_set_include_stop_str_in_output",
    "ov_genai_generation_config_set_length_penalty",
    "ov_genai_generation_config_set_logprobs",
    "ov_genai_generation_config_set_max_length",
    "ov_genai_generation_config_set_max_new_tokens",
    "ov_genai_generation_config_set_max_ngram_size",
    "ov_genai_generation_config_set_min_new_tokens",
    "ov_genai_generation_config_set_min_p",
    "ov_genai_generation_config_set_no_repeat_ngram_size",
    "ov_genai_generation_config_set_num_assistant_tokens",
    "ov_genai_generation_config_set_num_beam_groups",
    "ov_genai_generation_config_set_num_beams",
    "ov_genai_generation_config_set_num_return_sequences",
    "ov_genai_generation_config_set_presence_penalty",
    "ov_genai_generation_config_set_repetition_penalty",
    "ov_genai_generation_config_set_rng_seed",
    "ov_genai_generation_config_set_stop_criteria",
    "ov_genai_generation_config_set_stop_strings",
    "ov_genai_generation_config_set_stop_token_ids",
    "ov_genai_generation_config_set_temperature",
    "ov_genai_generation_config_set_top_k",
    "ov_genai_generation_config_set_top_p",
    "ov_genai_generation_config_validate",
    "ov_genai_json_container_copy",
    "ov_genai_json_container_create",
    "ov_genai_json_container_create_array",
    "ov_genai_json_container_create_from_json_string",
    "ov_genai_json_container_create_object",
    "ov_genai_json_container_free",
    "ov_genai_json_container_to_json_string",
    "ov_genai_llm_pipeline_create",
    "ov_genai_llm_pipeline_finish_chat",
    "ov_genai_llm_pipeline_free",
    "ov_genai_llm_pipeline_generate",
    "ov_genai_llm_pipeline_generate_with_history",
    "ov_genai_llm_pipeline_get_generation_config",
    "ov_genai_llm_pipeline_set_generation_config",
    "ov_genai_llm_pipeline_start_chat",
    "ov_genai_perf_metrics_add_in_place",
    "ov_genai_perf_metrics_get_chat_template_duration",
    "ov_genai_perf_metrics_get_detokenization_duration",
    "ov_genai_perf_metrics_get_generate_duration",
    "ov_genai_perf_metrics_get_inference_duration",
    "ov_genai_perf_metrics_get_ipot",
    "ov_genai_perf_metrics_get_load_time",
    "ov_genai_perf_metrics_get_num_generation_tokens",
    "ov_genai_perf_metrics_get_num_input_tokens",
    "ov_genai_perf_metrics_get_throughput",
    "ov_genai_perf_metrics_get_tokenization_duration",
    "ov_genai_perf_metrics_get_tpot",
    "ov_genai_perf_metrics_get_ttft",
    "ov_genai_vlm_decoded_results_create",
    "ov_genai_vlm_decoded_results_free",
    "ov_genai_vlm_decoded_results_get_perf_metrics",
    "ov_genai_vlm_decoded_results_get_string",
    "ov_genai_vlm_decoded_results_perf_metrics_free",
    "ov_genai_vlm_pipeline_create",
    "ov_genai_vlm_pipeline_finish_chat",
    "ov_genai_vlm_pipeline_free",
    "ov_genai_vlm_pipeline_generate",
    "ov_genai_vlm_pipeline_generate_with_history",
    "ov_genai_vlm_pipeline_get_generation_config",
    "ov_genai_vlm_pipeline_set_generation_config",
    "ov_genai_vlm_pipeline_start_chat",
    "ov_genai_whisper_decoded_result_chunk_create",
    "ov_genai_whisper_decoded_result_chunk_free",
    "ov_genai_whisper_decoded_result_chunk_get_end_ts",
    "ov_genai_whisper_decoded_result_chunk_get_start_ts",
    "ov_genai_whisper_decoded_result_chunk_get_text",
    "ov_genai_whisper_decoded_results_create",
    "ov_genai_whisper_decoded_results_free",
    "ov_genai_whisper_decoded_results_get_chunk_at",
    "ov_genai_whisper_decoded_results_get_chunks_count",
    "ov_genai_whisper_decoded_results_get_perf_metrics",
    "ov_genai_whisper_decoded_results_get_score_at",
    "ov_genai_whisper_decoded_results_get_string",
    "ov_genai_whisper_decoded_results_get_text_at",
    "ov_genai_whisper_decoded_results_get_texts_count",
    "ov_genai_whisper_decoded_results_has_chunks",
    "ov_genai_whisper_generation_config_create",
    "ov_genai_whisper_generation_config_create_from_json",
    "ov_genai_whisper_generation_config_free",
    "ov_genai_whisper_generation_config_get_begin_suppress_tokens",
    "ov_genai_whisper_generation_config_get_begin_suppress_tokens_count",
    "ov_genai_whisper_generation_config_get_decoder_start_token_id",
    "ov_genai_whisper_generation_config_get_generation_config",
    "ov_genai_whisper_generation_config_get_hotwords",
    "ov_genai_whisper_generation_config_get_initial_prompt",
    "ov_genai_whisper_generation_config_get_is_multilingual",
    "ov_genai_whisper_generation_config_get_language",
    "ov_genai_whisper_generation_config_get_max_initial_timestamp_index",
    "ov_genai_whisper_generation_config_get_no_timestamps_token_id",
    "ov_genai_whisper_generation_config_get_pad_token_id",
    "ov_genai_whisper_generation_config_get_prev_sot_token_id",
    "ov_genai_whisper_generation_config_get_return_timestamps",
    "ov_genai_whisper_generation_config_get_suppress_tokens",
    "ov_genai_whisper_generation_config_get_suppress_tokens_count",
    "ov_genai_whisper_generation_config_get_task",
    "ov_genai_whisper_generation_config_get_transcribe_token_id",
    "ov_genai_whisper_generation_config_get_translate_token_id",
    "ov_genai_whisper_generation_config_set_begin_suppress_tokens",
    "ov_genai_whisper_generation_config_set_decoder_start_token_id",
    "ov_genai_whisper_generation_config_set_hotwords",
    "ov_genai_whisper_generation_config_set_initial_prompt",
    "ov_genai_whisper_generation_config_set_is_multilingual",
    "ov_genai_whisper_generation_config_set_language",
    "ov_genai_whisper_generation_config_set_max_initial_timestamp_index",
    "ov_genai_whisper_generation_config_set_no_timestamps_token_id",
    "ov_genai_whisper_generation_config_set_pad_token_id",
    "ov_genai_whisper_generation_config_set_prev_sot_token_id",
    "ov_genai_whisper_generation_config_set_return_timestamps",
    "ov_genai_whisper_generation_config_set_suppress_tokens",
    "ov_genai_whisper_generation_config_set_task",
    "ov_genai_whisper_generation_config_set_transcribe_token_id",
    "ov_genai_whisper_generation_config_set_translate_token_id",
    "ov_genai_whisper_generation_config_validate",
    "ov_genai_whisper_pipeline_create",
    "ov_genai_whisper_pipeline_free",
    "ov_genai_whisper_pipeline_generate",
    "ov_genai_whisper_pipeline_get_generation_config",
    "ov_genai_whisper_pipeline_set_generation_config"
  ])

{.pop.}
