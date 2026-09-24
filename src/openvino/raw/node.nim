# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: model input and output ports.
##
## Source of truth: `ov_node.h` from OpenVINO `2026.4.0`, SHA-256
## `d3bf280719c445139680347fc411dbf3088dcd510bfc3b5faa765f0430b04ab9`.
##
## The const and the mutable port are **separate types with separate release
## functions**, and the metadata getters accept only the const one. Treating
## them as interchangeable is the kind of guess the development plan forbids.
## Only the const port is bound, because `0.1.0` reads metadata and does not
## reshape.

import common
import loader
import shape

{.push styleChecks: off.}

type
  ov_output_const_port_t* = object
    ## A read-only port. Released with `ov_output_const_port_free`.
    ##
    ## Declared incomplete on purpose: the layout is private to OpenVINO.

  ov_output_port_t* = object
    ## A mutable port, needed only for reshaping.
    ##
    ## Declared for completeness so that signatures taking it can be spelled,
    ## but no function producing one is bound in `0.1.0`. It has its own
    ## release function, `ov_output_port_free`, which is also not bound.

proc ov_port_get_any_name*(port: ptr ov_output_const_port_t;
                           tensor_name: ptr cstring): ov_status_e
  {.openvinoImport.}
  ## Reads any one of the port's tensor names.
  ##
  ## Takes a **const** port. Allocates the string, so the caller must copy it
  ## and release the original with `ov_free`.

proc ov_port_get_element_type*(port: ptr ov_output_const_port_t;
                               tensor_type: ptr ov_element_type_e): ov_status_e
  {.openvinoImport.}
  ## Reads the port's element type. Takes a **const** port.

proc ov_const_port_get_shape*(port: ptr ov_output_const_port_t;
                              tensor_shape: ptr ov_shape_t): ov_status_e
  {.openvinoImport.}
  ## Reads the port's static shape.
  ##
  ## OpenVINO allocates the dimension storage, so a successful call must be
  ## paired with `ov_shape_free`.

proc ov_output_const_port_free*(port: ptr ov_output_const_port_t)
  {.openvinoImport.}
  ## Releases a const port. Not interchangeable with `ov_output_port_free`.

{.pop.}
