/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * See abi_probe.h. Every value returned here is computed by the C compiler
 * from the pinned OpenVINO headers.
 */

#include "abi_probe.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "openvino/c/ov_common.h"
#include "openvino/c/ov_core.h"
#include "openvino/c/ov_infer_request.h"
#include "openvino/c/ov_property.h"
#include "openvino/c/ov_shape.h"

/*
 * One entry per enumerator. Writing the name next to the enumerator itself
 * means the compiler supplies the value, so this table cannot drift from the
 * header the way a hand-copied list can. A renamed enumerator fails to
 * compile here, which is the intended alarm.
 */
typedef struct {
  const char* name;
  int value;
} ov_nim_probe_entry_t;

#define OV_NIM_PROBE_ENTRY(enumerator) \
  { #enumerator, (int)(enumerator) }

static const ov_nim_probe_entry_t g_status_table[] = {
    OV_NIM_PROBE_ENTRY(OK),
    OV_NIM_PROBE_ENTRY(GENERAL_ERROR),
    OV_NIM_PROBE_ENTRY(NOT_IMPLEMENTED),
    OV_NIM_PROBE_ENTRY(NETWORK_NOT_LOADED),
    OV_NIM_PROBE_ENTRY(PARAMETER_MISMATCH),
    OV_NIM_PROBE_ENTRY(NOT_FOUND),
    OV_NIM_PROBE_ENTRY(OUT_OF_BOUNDS),
    OV_NIM_PROBE_ENTRY(UNEXPECTED),
    OV_NIM_PROBE_ENTRY(REQUEST_BUSY),
    OV_NIM_PROBE_ENTRY(RESULT_NOT_READY),
    OV_NIM_PROBE_ENTRY(NOT_ALLOCATED),
    OV_NIM_PROBE_ENTRY(INFER_NOT_STARTED),
    OV_NIM_PROBE_ENTRY(NETWORK_NOT_READ),
    OV_NIM_PROBE_ENTRY(INFER_CANCELLED),
    OV_NIM_PROBE_ENTRY(INVALID_C_PARAM),
    OV_NIM_PROBE_ENTRY(UNKNOWN_C_ERROR),
    OV_NIM_PROBE_ENTRY(NOT_IMPLEMENT_C_METHOD),
    OV_NIM_PROBE_ENTRY(UNKNOW_EXCEPTION),
};

static const ov_nim_probe_entry_t g_element_type_table[] = {
    OV_NIM_PROBE_ENTRY(DYNAMIC), OV_NIM_PROBE_ENTRY(BOOLEAN),
    OV_NIM_PROBE_ENTRY(BF16),    OV_NIM_PROBE_ENTRY(F16),
    OV_NIM_PROBE_ENTRY(F32),     OV_NIM_PROBE_ENTRY(F64),
    OV_NIM_PROBE_ENTRY(I4),      OV_NIM_PROBE_ENTRY(I8),
    OV_NIM_PROBE_ENTRY(I16),     OV_NIM_PROBE_ENTRY(I32),
    OV_NIM_PROBE_ENTRY(I64),     OV_NIM_PROBE_ENTRY(U1),
    OV_NIM_PROBE_ENTRY(U2),      OV_NIM_PROBE_ENTRY(U3),
    OV_NIM_PROBE_ENTRY(U4),      OV_NIM_PROBE_ENTRY(U6),
    OV_NIM_PROBE_ENTRY(U8),      OV_NIM_PROBE_ENTRY(U16),
    OV_NIM_PROBE_ENTRY(U32),     OV_NIM_PROBE_ENTRY(U64),
    OV_NIM_PROBE_ENTRY(NF4),     OV_NIM_PROBE_ENTRY(F8E4M3),
    OV_NIM_PROBE_ENTRY(F8E5M3),  OV_NIM_PROBE_ENTRY(STRING),
    OV_NIM_PROBE_ENTRY(F4E2M1),  OV_NIM_PROBE_ENTRY(F8E8M0),
};

static const ov_nim_probe_entry_t g_profiling_status_table[] = {
    OV_NIM_PROBE_ENTRY(NOT_RUN),
    OV_NIM_PROBE_ENTRY(OPTIMIZED_OUT),
    OV_NIM_PROBE_ENTRY(EXECUTED),
};

static int table_count(const ov_nim_probe_entry_t* table, size_t bytes) {
  (void)table;
  return (int)(bytes / sizeof(ov_nim_probe_entry_t));
}

static const char* table_name(const ov_nim_probe_entry_t* table, int count,
                              int index) {
  if (index < 0 || index >= count) {
    return NULL;
  }
  return table[index].name;
}

static int table_value(const ov_nim_probe_entry_t* table, int count,
                       int index) {
  if (index < 0 || index >= count) {
    return 0;
  }
  return table[index].value;
}

size_t ov_nim_probe_sizeof_status(void) { return sizeof(ov_status_e); }

size_t ov_nim_probe_sizeof_element_type(void) {
  return sizeof(ov_element_type_e);
}

size_t ov_nim_probe_sizeof_bool(void) { return sizeof(bool); }

size_t ov_nim_probe_sizeof_size_t(void) { return sizeof(size_t); }

size_t ov_nim_probe_sizeof_int64(void) { return sizeof(int64_t); }

size_t ov_nim_probe_sizeof_shape(void) { return sizeof(ov_shape_t); }

size_t ov_nim_probe_offsetof_shape_rank(void) {
  return offsetof(ov_shape_t, rank);
}

size_t ov_nim_probe_offsetof_shape_dims(void) {
  return offsetof(ov_shape_t, dims);
}

size_t ov_nim_probe_sizeof_property(void) { return sizeof(ov_property_t); }

size_t ov_nim_probe_offsetof_property_key(void) {
  return offsetof(ov_property_t, key);
}

size_t ov_nim_probe_offsetof_property_value(void) {
  return offsetof(ov_property_t, value);
}

size_t ov_nim_probe_sizeof_version(void) { return sizeof(ov_version_t); }

size_t ov_nim_probe_offsetof_version_build_number(void) {
  return offsetof(ov_version_t, buildNumber);
}

size_t ov_nim_probe_offsetof_version_description(void) {
  return offsetof(ov_version_t, description);
}

size_t ov_nim_probe_sizeof_available_devices(void) {
  return sizeof(ov_available_devices_t);
}

size_t ov_nim_probe_offsetof_available_devices_devices(void) {
  return offsetof(ov_available_devices_t, devices);
}

size_t ov_nim_probe_offsetof_available_devices_size(void) {
  return offsetof(ov_available_devices_t, size);
}

size_t ov_nim_probe_sizeof_profiling_info(void) {
  return sizeof(ov_profiling_info_t);
}

size_t ov_nim_probe_offsetof_profiling_info_status(void) {
  return offsetof(ov_profiling_info_t, status);
}

size_t ov_nim_probe_offsetof_profiling_info_real_time(void) {
  return offsetof(ov_profiling_info_t, real_time);
}

size_t ov_nim_probe_offsetof_profiling_info_cpu_time(void) {
  return offsetof(ov_profiling_info_t, cpu_time);
}

size_t ov_nim_probe_offsetof_profiling_info_node_name(void) {
  return offsetof(ov_profiling_info_t, node_name);
}

size_t ov_nim_probe_offsetof_profiling_info_exec_type(void) {
  return offsetof(ov_profiling_info_t, exec_type);
}

size_t ov_nim_probe_offsetof_profiling_info_node_type(void) {
  return offsetof(ov_profiling_info_t, node_type);
}

size_t ov_nim_probe_sizeof_profiling_info_status_field(void) {
  ov_profiling_info_t info;
  return sizeof(info.status);
}

size_t ov_nim_probe_sizeof_profiling_info_list(void) {
  return sizeof(ov_profiling_info_list_t);
}

size_t ov_nim_probe_sizeof_callback(void) { return sizeof(ov_callback_t); }

int ov_nim_probe_status_count(void) {
  return table_count(g_status_table, sizeof(g_status_table));
}

const char* ov_nim_probe_status_name(int index) {
  return table_name(g_status_table, ov_nim_probe_status_count(), index);
}

int ov_nim_probe_status_value(int index) {
  return table_value(g_status_table, ov_nim_probe_status_count(), index);
}

int ov_nim_probe_element_type_count(void) {
  return table_count(g_element_type_table, sizeof(g_element_type_table));
}

const char* ov_nim_probe_element_type_name(int index) {
  return table_name(g_element_type_table, ov_nim_probe_element_type_count(),
                    index);
}

int ov_nim_probe_element_type_value(int index) {
  return table_value(g_element_type_table, ov_nim_probe_element_type_count(),
                     index);
}

int ov_nim_probe_profiling_status_count(void) {
  return table_count(g_profiling_status_table,
                     sizeof(g_profiling_status_table));
}

const char* ov_nim_probe_profiling_status_name(int index) {
  return table_name(g_profiling_status_table,
                    ov_nim_probe_profiling_status_count(), index);
}

int ov_nim_probe_profiling_status_value(int index) {
  return table_value(g_profiling_status_table,
                     ov_nim_probe_profiling_status_count(), index);
}
