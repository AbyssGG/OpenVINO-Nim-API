# SPDX-License-Identifier: Apache-2.0

## ABI tests: every bound constant and layout fact is compared against the
## pinned OpenVINO headers rather than against a second hand-written list.
##
## The C probe in `abi_probe.c` is compiled against the real headers and linked
## into this test, so the values on the C side are produced by the compiler.
## A disagreement means the Nim declaration is wrong, not that the test is out
## of date.
##
## This test needs the OpenVINO C headers but never loads the runtime and never
## calls into OpenVINO. Run it with `nimble testAbi`, which supplies the
## include path and fails with an explicit message when it is missing.

import std/unittest

import openvino/raw/common

{.compile: "abi_probe.c".}

{.push importc, cdecl.}

proc ov_nim_probe_sizeof_status(): csize_t
proc ov_nim_probe_sizeof_element_type(): csize_t
proc ov_nim_probe_sizeof_bool(): csize_t
proc ov_nim_probe_sizeof_size_t(): csize_t
proc ov_nim_probe_sizeof_int64(): csize_t

proc ov_nim_probe_sizeof_shape(): csize_t
proc ov_nim_probe_offsetof_shape_rank(): csize_t
proc ov_nim_probe_offsetof_shape_dims(): csize_t

proc ov_nim_probe_sizeof_property(): csize_t
proc ov_nim_probe_offsetof_property_key(): csize_t
proc ov_nim_probe_offsetof_property_value(): csize_t

proc ov_nim_probe_sizeof_version(): csize_t
proc ov_nim_probe_offsetof_version_build_number(): csize_t
proc ov_nim_probe_offsetof_version_description(): csize_t

proc ov_nim_probe_sizeof_available_devices(): csize_t
proc ov_nim_probe_offsetof_available_devices_devices(): csize_t
proc ov_nim_probe_offsetof_available_devices_size(): csize_t

proc ov_nim_probe_sizeof_profiling_info(): csize_t
proc ov_nim_probe_offsetof_profiling_info_status(): csize_t
proc ov_nim_probe_offsetof_profiling_info_real_time(): csize_t
proc ov_nim_probe_offsetof_profiling_info_cpu_time(): csize_t
proc ov_nim_probe_offsetof_profiling_info_node_name(): csize_t
proc ov_nim_probe_offsetof_profiling_info_exec_type(): csize_t
proc ov_nim_probe_offsetof_profiling_info_node_type(): csize_t
proc ov_nim_probe_sizeof_profiling_info_status_field(): csize_t

proc ov_nim_probe_sizeof_profiling_info_list(): csize_t
proc ov_nim_probe_sizeof_callback(): csize_t

proc ov_nim_probe_status_count(): cint
proc ov_nim_probe_status_name(index: cint): cstring
proc ov_nim_probe_status_value(index: cint): cint

proc ov_nim_probe_element_type_count(): cint
proc ov_nim_probe_element_type_name(index: cint): cstring
proc ov_nim_probe_element_type_value(index: cint): cint

proc ov_nim_probe_profiling_status_count(): cint
proc ov_nim_probe_profiling_status_name(index: cint): cstring
proc ov_nim_probe_profiling_status_value(index: cint): cint

{.pop.}

suite "scalar ABI":
  test "the bound ov_status_e has the same width as the C enum":
    checkpoint("nim sizeof=" & $sizeof(ov_status_e) &
      " c sizeof=" & $ov_nim_probe_sizeof_status())
    check csize_t(sizeof(ov_status_e)) == ov_nim_probe_sizeof_status()

  test "the bound ov_element_type_e has the same width as the C enum":
    checkpoint("nim sizeof=" & $sizeof(ov_element_type_e) &
      " c sizeof=" & $ov_nim_probe_sizeof_element_type())
    check csize_t(sizeof(ov_element_type_e)) ==
      ov_nim_probe_sizeof_element_type()

  test "csize_t matches C size_t":
    check csize_t(sizeof(csize_t)) == ov_nim_probe_sizeof_size_t()

  test "int64 matches C int64_t":
    check csize_t(sizeof(int64)) == ov_nim_probe_sizeof_int64()

  test "Nim bool matches C bool, which ov_model_is_dynamic returns":
    checkpoint("nim sizeof=" & $sizeof(bool) &
      " c sizeof=" & $ov_nim_probe_sizeof_bool())
    check csize_t(sizeof(bool)) == ov_nim_probe_sizeof_bool()

suite "status codes":
  test "the probe and the binding know the same number of status codes":
    checkpoint("bound=" & $StatusCodes.len &
      " probed=" & $ov_nim_probe_status_count())
    check cint(StatusCodes.len) == ov_nim_probe_status_count()

  test "every status code read from the header matches the bound value":
    # Driven by the C side so that a status code present in the header but
    # missing from the binding fails here rather than going unnoticed.
    for index in 0 ..< ov_nim_probe_status_count():
      let
        name = $ov_nim_probe_status_name(index)
        probed = ov_nim_probe_status_value(index)
      checkpoint("status " & name & ": probed=" & $probed)
      check statusValue(name) == ov_status_e(probed)

  test "NOT_ALLOCATED is minus ten, which the prototype named ALLOCATED":
    # The prototype bound -10 under the wrong name. Pinned explicitly because
    # it is a documented defect, not merely a value in a table.
    check statusValue("NOT_ALLOCATED") == ov_status_e(-10)

  test "the four C wrapper status codes the prototype omitted are bound":
    check statusValue("INVALID_C_PARAM") == ov_status_e(-14)
    check statusValue("UNKNOWN_C_ERROR") == ov_status_e(-15)
    check statusValue("NOT_IMPLEMENT_C_METHOD") == ov_status_e(-16)
    check statusValue("UNKNOW_EXCEPTION") == ov_status_e(-17)

suite "element types":
  test "the probe and the binding know the same number of element types":
    checkpoint("bound=" & $ElementTypes.len &
      " probed=" & $ov_nim_probe_element_type_count())
    check cint(ElementTypes.len) == ov_nim_probe_element_type_count()

  test "every element type read from the header matches the bound value":
    for index in 0 ..< ov_nim_probe_element_type_count():
      let
        name = $ov_nim_probe_element_type_name(index)
        probed = ov_nim_probe_element_type_value(index)
      checkpoint("element type " & name & ": probed=" & $probed)
      check elementTypeValue(name) == ov_element_type_e(probed)

  test "U8 is sixteen, not the thirteen the prototype bound":
    # The prototype omitted U2, U3 and U6, which shifted everything from U8
    # upward by three. Any u8 input tensor was handed to the runtime as U3.
    # This is the data-corruption defect from the audit, pinned by value.
    check elementTypeValue("U8") == ov_element_type_e(16)
    check elementTypeValue("U2") == ov_element_type_e(12)
    check elementTypeValue("U3") == ov_element_type_e(13)
    check elementTypeValue("U6") == ov_element_type_e(15)

  test "the upstream spelling F8E5M3 is preserved despite its comment":
    # The header comment says f8e5m2 while the symbol is F8E5M3. The symbol
    # wins: renaming it would break the ABI contract.
    check elementTypeValue("F8E5M3") == ov_element_type_e(22)

suite "struct layout":
  test "ov_shape_t is a rank and a dims pointer in that order":
    check ov_nim_probe_sizeof_shape() ==
      ov_nim_probe_sizeof_int64() + csize_t(sizeof(pointer))
    check ov_nim_probe_offsetof_shape_rank() == 0
    check ov_nim_probe_offsetof_shape_dims() == ov_nim_probe_sizeof_int64()

  test "ov_property_t is two pointers in key then value order":
    check ov_nim_probe_sizeof_property() == csize_t(2 * sizeof(pointer))
    check ov_nim_probe_offsetof_property_key() == 0
    check ov_nim_probe_offsetof_property_value() == csize_t(sizeof(pointer))

  test "ov_version_t is two string pointers":
    check ov_nim_probe_sizeof_version() == csize_t(2 * sizeof(pointer))
    check ov_nim_probe_offsetof_version_build_number() == 0
    check ov_nim_probe_offsetof_version_description() ==
      csize_t(sizeof(pointer))

  test "ov_available_devices_t is a string array then a size":
    check ov_nim_probe_offsetof_available_devices_devices() == 0
    check ov_nim_probe_offsetof_available_devices_size() ==
      csize_t(sizeof(pointer))

  test "the ov_profiling_info_t status field is a C int, not an int64":
    # The prototype declared this field as int32 without verifying it. The
    # field is an anonymous nested enum, so its width is whatever the C
    # compiler gives an enum.
    checkpoint("status field sizeof=" &
      $ov_nim_probe_sizeof_profiling_info_status_field())
    check ov_nim_probe_sizeof_profiling_info_status_field() ==
      ov_nim_probe_sizeof_status()
    check ov_nim_probe_offsetof_profiling_info_status() == 0

  test "ov_profiling_info_t places both times before the three strings":
    let
      realTime = ov_nim_probe_offsetof_profiling_info_real_time()
      cpuTime = ov_nim_probe_offsetof_profiling_info_cpu_time()
      nodeName = ov_nim_probe_offsetof_profiling_info_node_name()
      execType = ov_nim_probe_offsetof_profiling_info_exec_type()
      nodeType = ov_nim_probe_offsetof_profiling_info_node_type()
    checkpoint("real=" & $realTime & " cpu=" & $cpuTime &
      " node=" & $nodeName & " exec=" & $execType & " type=" & $nodeType)
    check realTime < cpuTime
    check cpuTime < nodeName
    check nodeName < execType
    check execType < nodeType
    check cpuTime - realTime == ov_nim_probe_sizeof_int64()
    check execType - nodeName == csize_t(sizeof(pointer))
    check nodeType - execType == csize_t(sizeof(pointer))

  test "ov_profiling_info_list_t and ov_callback_t are a pointer pair":
    check ov_nim_probe_sizeof_profiling_info_list() ==
      csize_t(2 * sizeof(pointer))
    check ov_nim_probe_sizeof_callback() == csize_t(2 * sizeof(pointer))

suite "profiling status enumerators":
  test "the nested profiling status enum runs from zero in header order":
    check ov_nim_probe_profiling_status_count() == 3
    check $ov_nim_probe_profiling_status_name(0) == "NOT_RUN"
    check ov_nim_probe_profiling_status_value(0) == 0
    check $ov_nim_probe_profiling_status_name(1) == "OPTIMIZED_OUT"
    check ov_nim_probe_profiling_status_value(1) == 1
    check $ov_nim_probe_profiling_status_name(2) == "EXECUTED"
    check ov_nim_probe_profiling_status_value(2) == 2
