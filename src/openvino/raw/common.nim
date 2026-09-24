# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: status codes and element types.
##
## Source of truth: `ov_common.h` from OpenVINO `2026.4.0`, upstream tag
## `2026.4.0`, SHA-256 `a5dd4572f231054e3f2a8c7f77558f257f43b8bc9dbc2c1ffc2b3999dd9e50fd`.
## Every declaration below is located in `docs/c-api-coverage.md`.
##
## This module declares ABI and nothing else. It performs no I/O, copies no
## data, converts no values and raises no exceptions. Turning a status code
## into a Nim exception is the managed layer's job.
##
## `ov_status_e` and `ov_element_type_e` are bound as `cint` aliases with
## constants rather than as Nim enums. A Nim enum would be the more idiomatic
## choice, but it is the wrong one at an ABI boundary: a value the runtime
## returns and this binding does not know would leave the enum holding an
## illegal value, after which `$` and `case` stop being reliable. A `cint`
## carries an unknown value safely, and the managed layer rejects it
## explicitly. See `docs/decisions` and plan section 2.10 for the measurement
## behind this.
##
## The upstream spellings are ABI, not style. `UNKNOW_EXCEPTION` is spelled
## that way in the header, and `F8E5M3` is the symbol name even though its own
## header comment says `f8e5m2`. Renaming either is forbidden.

{.push styleChecks: off.}

type
  ov_status_e* = cint
    ## Return type of nearly every OpenVINO C function. `OK` means success.

  ov_element_type_e* = cint
    ## Tensor element type. Values rise implicitly from `DYNAMIC` in the
    ## header, so a missing value shifts every later one.

const
  OK* = ov_status_e(0)
  GENERAL_ERROR* = ov_status_e(-1)
  NOT_IMPLEMENTED* = ov_status_e(-2)
  NETWORK_NOT_LOADED* = ov_status_e(-3)
  PARAMETER_MISMATCH* = ov_status_e(-4)
  NOT_FOUND* = ov_status_e(-5)
  OUT_OF_BOUNDS* = ov_status_e(-6)
  UNEXPECTED* = ov_status_e(-7)
  REQUEST_BUSY* = ov_status_e(-8)
  RESULT_NOT_READY* = ov_status_e(-9)
  NOT_ALLOCATED* = ov_status_e(-10)
  INFER_NOT_STARTED* = ov_status_e(-11)
  NETWORK_NOT_READ* = ov_status_e(-12)
  INFER_CANCELLED* = ov_status_e(-13)
  INVALID_C_PARAM* = ov_status_e(-14)
  UNKNOWN_C_ERROR* = ov_status_e(-15)
  NOT_IMPLEMENT_C_METHOD* = ov_status_e(-16)
  UNKNOW_EXCEPTION* = ov_status_e(-17)

const
  DYNAMIC* = ov_element_type_e(0)
  BOOLEAN* = ov_element_type_e(1)
  BF16* = ov_element_type_e(2)
  F16* = ov_element_type_e(3)
  F32* = ov_element_type_e(4)
  F64* = ov_element_type_e(5)
  I4* = ov_element_type_e(6)
  I8* = ov_element_type_e(7)
  I16* = ov_element_type_e(8)
  I32* = ov_element_type_e(9)
  I64* = ov_element_type_e(10)
  U1* = ov_element_type_e(11)
  U2* = ov_element_type_e(12)
  U3* = ov_element_type_e(13)
  U4* = ov_element_type_e(14)
  U6* = ov_element_type_e(15)
  U8* = ov_element_type_e(16)
  U16* = ov_element_type_e(17)
  U32* = ov_element_type_e(18)
  U64* = ov_element_type_e(19)
  NF4* = ov_element_type_e(20)
  F8E4M3* = ov_element_type_e(21)
  F8E5M3* = ov_element_type_e(22)
  STRING* = ov_element_type_e(23)
  F4E2M1* = ov_element_type_e(24)
  F8E8M0* = ov_element_type_e(25)

{.pop.}

# The tables below are not part of the C ABI. They exist so that the ABI test
# can walk every bound constant and compare it against what the C probe reads
# from the header, instead of spot-checking a few by hand. They therefore use
# this project's naming rules rather than upstream spellings.

const StatusCodes*: array[18, tuple[name: string, value: ov_status_e]] = [
  ("OK", OK),
  ("GENERAL_ERROR", GENERAL_ERROR),
  ("NOT_IMPLEMENTED", NOT_IMPLEMENTED),
  ("NETWORK_NOT_LOADED", NETWORK_NOT_LOADED),
  ("PARAMETER_MISMATCH", PARAMETER_MISMATCH),
  ("NOT_FOUND", NOT_FOUND),
  ("OUT_OF_BOUNDS", OUT_OF_BOUNDS),
  ("UNEXPECTED", UNEXPECTED),
  ("REQUEST_BUSY", REQUEST_BUSY),
  ("RESULT_NOT_READY", RESULT_NOT_READY),
  ("NOT_ALLOCATED", NOT_ALLOCATED),
  ("INFER_NOT_STARTED", INFER_NOT_STARTED),
  ("NETWORK_NOT_READ", NETWORK_NOT_READ),
  ("INFER_CANCELLED", INFER_CANCELLED),
  ("INVALID_C_PARAM", INVALID_C_PARAM),
  ("UNKNOWN_C_ERROR", UNKNOWN_C_ERROR),
  ("NOT_IMPLEMENT_C_METHOD", NOT_IMPLEMENT_C_METHOD),
  ("UNKNOW_EXCEPTION", UNKNOW_EXCEPTION)]
  ## Every bound `ov_status_e` constant, paired with its upstream spelling.

const ElementTypes*: array[26, tuple[name: string,
                                     value: ov_element_type_e]] = [
  ("DYNAMIC", DYNAMIC),
  ("BOOLEAN", BOOLEAN),
  ("BF16", BF16),
  ("F16", F16),
  ("F32", F32),
  ("F64", F64),
  ("I4", I4),
  ("I8", I8),
  ("I16", I16),
  ("I32", I32),
  ("I64", I64),
  ("U1", U1),
  ("U2", U2),
  ("U3", U3),
  ("U4", U4),
  ("U6", U6),
  ("U8", U8),
  ("U16", U16),
  ("U32", U32),
  ("U64", U64),
  ("NF4", NF4),
  ("F8E4M3", F8E4M3),
  ("F8E5M3", F8E5M3),
  ("STRING", STRING),
  ("F4E2M1", F4E2M1),
  ("F8E8M0", F8E8M0)]
  ## Every bound `ov_element_type_e` constant, paired with its upstream
  ## spelling.

proc statusValue*(name: string): ov_status_e =
  ## Returns the bound value of the status constant spelled `name`.
  ##
  ## Raises `KeyError` when the name is not bound, so a header that gains a
  ## status code fails the ABI test loudly instead of being skipped.
  for entry in StatusCodes:
    if entry.name == name:
      return entry.value
  raise newException(KeyError, "no bound ov_status_e constant named " & name)

proc elementTypeValue*(name: string): ov_element_type_e =
  ## Returns the bound value of the element-type constant spelled `name`.
  ##
  ## Raises `KeyError` when the name is not bound.
  for entry in ElementTypes:
    if entry.name == name:
      return entry.value
  raise newException(KeyError,
    "no bound ov_element_type_e constant named " & name)
