/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * ABI probe for the OpenVINO C API.
 *
 * Compiled against the pinned OpenVINO headers and linked into the Nim ABI
 * test, so every fact reported here is read from the real header rather than
 * transcribed. The Nim side compares these values against the declarations in
 * src/openvino/raw and fails when they disagree.
 *
 * This file must stay plain C. It must not use varargs, compiler-private ABI
 * attributes or platform APIs.
 */

#ifndef OPENVINO_NIM_TESTS_ABI_PROBE_H_
#define OPENVINO_NIM_TESTS_ABI_PROBE_H_

#include <stddef.h>

/* Sizes of the scalar types the binding depends on. */
size_t ov_nim_probe_sizeof_status(void);
size_t ov_nim_probe_sizeof_element_type(void);
size_t ov_nim_probe_sizeof_bool(void);
size_t ov_nim_probe_sizeof_size_t(void);
size_t ov_nim_probe_sizeof_int64(void);

/* Sizes and field offsets of the structs the binding passes or fills. */
size_t ov_nim_probe_sizeof_shape(void);
size_t ov_nim_probe_offsetof_shape_rank(void);
size_t ov_nim_probe_offsetof_shape_dims(void);

size_t ov_nim_probe_sizeof_property(void);
size_t ov_nim_probe_offsetof_property_key(void);
size_t ov_nim_probe_offsetof_property_value(void);

size_t ov_nim_probe_sizeof_version(void);
size_t ov_nim_probe_offsetof_version_build_number(void);
size_t ov_nim_probe_offsetof_version_description(void);

size_t ov_nim_probe_sizeof_available_devices(void);
size_t ov_nim_probe_offsetof_available_devices_devices(void);
size_t ov_nim_probe_offsetof_available_devices_size(void);

size_t ov_nim_probe_sizeof_profiling_info(void);
size_t ov_nim_probe_offsetof_profiling_info_status(void);
size_t ov_nim_probe_offsetof_profiling_info_real_time(void);
size_t ov_nim_probe_offsetof_profiling_info_cpu_time(void);
size_t ov_nim_probe_offsetof_profiling_info_node_name(void);
size_t ov_nim_probe_offsetof_profiling_info_exec_type(void);
size_t ov_nim_probe_offsetof_profiling_info_node_type(void);
size_t ov_nim_probe_sizeof_profiling_info_status_field(void);

size_t ov_nim_probe_sizeof_profiling_info_list(void);
size_t ov_nim_probe_sizeof_callback(void);

/*
 * Status codes, read from ov_status_e itself. The name table and the value
 * table are built from the same enumerator list, so an enumerator that is
 * renamed or renumbered upstream changes both together.
 *
 * Out-of-range indexes return 0 for the count-bearing calls and NULL for
 * names, so a mismatch surfaces as a failed comparison rather than a crash.
 */
int ov_nim_probe_status_count(void);
const char* ov_nim_probe_status_name(int index);
int ov_nim_probe_status_value(int index);

/* Element types, read from ov_element_type_e itself. */
int ov_nim_probe_element_type_count(void);
const char* ov_nim_probe_element_type_name(int index);
int ov_nim_probe_element_type_value(int index);

/* Profiling status enumerators, read from the anonymous nested enum. */
int ov_nim_probe_profiling_status_count(void);
const char* ov_nim_probe_profiling_status_name(int index);
int ov_nim_probe_profiling_status_value(int index);

#endif /* OPENVINO_NIM_TESTS_ABI_PROBE_H_ */
