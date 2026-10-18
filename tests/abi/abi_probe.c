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
#include "openvino/c/ov_dimension.h"
#include "openvino/c/ov_infer_request.h"
#include "openvino/c/ov_layout.h"
#include "openvino/c/ov_partial_shape.h"
#include "openvino/c/ov_prepostprocess.h"
#include "openvino/c/ov_property.h"
#include "openvino/c/ov_rank.h"
#include "openvino/c/ov_shape.h"

/*
 * Alignment without C11 _Alignof, which not every C compiler Nim drives
 * accepts in its default mode: the offset of a member that follows a single
 * char is the member type's alignment.
 */
#define OV_NIM_PROBE_ALIGNOF(type) \
  offsetof(struct { char c; type member; }, member)

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

static const ov_nim_probe_entry_t g_color_format_table[] = {
    OV_NIM_PROBE_ENTRY(UNDEFINE),
    OV_NIM_PROBE_ENTRY(NV12_SINGLE_PLANE),
    OV_NIM_PROBE_ENTRY(NV12_TWO_PLANES),
    OV_NIM_PROBE_ENTRY(I420_SINGLE_PLANE),
    OV_NIM_PROBE_ENTRY(I420_THREE_PLANES),
    OV_NIM_PROBE_ENTRY(RGB),
    OV_NIM_PROBE_ENTRY(BGR),
    OV_NIM_PROBE_ENTRY(GRAY),
    OV_NIM_PROBE_ENTRY(RGBX),
    OV_NIM_PROBE_ENTRY(BGRX),
};

static const ov_nim_probe_entry_t g_resize_algorithm_table[] = {
    OV_NIM_PROBE_ENTRY(RESIZE_LINEAR),
    OV_NIM_PROBE_ENTRY(RESIZE_CUBIC),
    OV_NIM_PROBE_ENTRY(RESIZE_NEAREST),
};

static const ov_nim_probe_entry_t g_padding_mode_table[] = {
    OV_NIM_PROBE_ENTRY(CONSTANT),
    OV_NIM_PROBE_ENTRY(EDGE),
    OV_NIM_PROBE_ENTRY(REFLECT),
    OV_NIM_PROBE_ENTRY(SYMMETRIC),
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

size_t ov_nim_probe_alignof_callback(void) {
  return OV_NIM_PROBE_ALIGNOF(ov_callback_t);
}

size_t ov_nim_probe_offsetof_callback_func(void) {
  return offsetof(ov_callback_t, callback_func);
}

size_t ov_nim_probe_offsetof_callback_args(void) {
  return offsetof(ov_callback_t, args);
}

size_t ov_nim_probe_sizeof_dimension(void) { return sizeof(ov_dimension_t); }

size_t ov_nim_probe_alignof_dimension(void) {
  return OV_NIM_PROBE_ALIGNOF(ov_dimension_t);
}

size_t ov_nim_probe_offsetof_dimension_min(void) {
  return offsetof(ov_dimension_t, min);
}

size_t ov_nim_probe_offsetof_dimension_max(void) {
  return offsetof(ov_dimension_t, max);
}

size_t ov_nim_probe_sizeof_rank(void) { return sizeof(ov_rank_t); }

size_t ov_nim_probe_sizeof_partial_shape(void) {
  return sizeof(ov_partial_shape_t);
}

size_t ov_nim_probe_alignof_partial_shape(void) {
  return OV_NIM_PROBE_ALIGNOF(ov_partial_shape_t);
}

size_t ov_nim_probe_offsetof_partial_shape_rank(void) {
  return offsetof(ov_partial_shape_t, rank);
}

size_t ov_nim_probe_offsetof_partial_shape_dims(void) {
  return offsetof(ov_partial_shape_t, dims);
}

size_t ov_nim_probe_sizeof_color_format(void) {
  return sizeof(ov_color_format_e);
}

size_t ov_nim_probe_sizeof_resize_algorithm(void) {
  return sizeof(ov_preprocess_resize_algorithm_e);
}

size_t ov_nim_probe_sizeof_padding_mode(void) {
  return sizeof(ov_padding_mode_e);
}

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

int ov_nim_probe_color_format_count(void) {
  return table_count(g_color_format_table, sizeof(g_color_format_table));
}

const char* ov_nim_probe_color_format_name(int index) {
  return table_name(g_color_format_table, ov_nim_probe_color_format_count(),
                    index);
}

int ov_nim_probe_color_format_value(int index) {
  return table_value(g_color_format_table, ov_nim_probe_color_format_count(),
                     index);
}

int ov_nim_probe_resize_algorithm_count(void) {
  return table_count(g_resize_algorithm_table,
                     sizeof(g_resize_algorithm_table));
}

const char* ov_nim_probe_resize_algorithm_name(int index) {
  return table_name(g_resize_algorithm_table,
                    ov_nim_probe_resize_algorithm_count(), index);
}

int ov_nim_probe_resize_algorithm_value(int index) {
  return table_value(g_resize_algorithm_table,
                     ov_nim_probe_resize_algorithm_count(), index);
}

int ov_nim_probe_padding_mode_count(void) {
  return table_count(g_padding_mode_table, sizeof(g_padding_mode_table));
}

const char* ov_nim_probe_padding_mode_name(int index) {
  return table_name(g_padding_mode_table, ov_nim_probe_padding_mode_count(),
                    index);
}

int ov_nim_probe_padding_mode_value(int index) {
  return table_value(g_padding_mode_table, ov_nim_probe_padding_mode_count(),
                     index);
}
