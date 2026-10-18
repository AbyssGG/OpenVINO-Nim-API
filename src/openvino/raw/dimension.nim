# SPDX-License-Identifier: Apache-2.0

## OpenVINO C ABI: dimensions and ranks.
##
## Source of truth: `ov_dimension.h` from OpenVINO `2026.4.0`, SHA-256
## `6902eef9978a7ea551e2c562e76f66cf04611fb52225fb4863d3fbcbd5afd6ab`, and
## `ov_rank.h`, SHA-256
## `10ff53b49b5911b92edd96004711639003aeb577ab9a26d783e1812d1ee99267`.
##
## A dimension is a closed interval `[min, max]` where `max == -1` means "no
## upper bound". A port reports an unbounded dimension as `{0, -1}`. The two
## `_is_dynamic` predicates are bound for completeness but misclassify static
## zero-length dimensions and rank 0; the managed layer does not call them. See
## `docs/decisions/0004-partial-shape-representation.md`.

import loader

{.push styleChecks: off.}

type
  ov_dimension_t* = object
    ## One dimension as an inclusive interval. Passed and returned by value.
    ##
    ## Layout (two `int64_t`, `min` first) is verified by the ABI test.
    min*: int64
      ## Inclusive lower bound.
    max*: int64
      ## Inclusive upper bound, or `-1` for "unbounded".

  ov_rank_t* = ov_dimension_t
    ## A rank uses the same interval representation as a dimension.

proc ov_dimension_is_dynamic*(dim: ov_dimension_t): bool {.openvinoImport.}
  ## Reports whether `dim` is dynamic.
  ##
  ## **Quirk**: returns `false` only when `min == max && max > 0`, so a static
  ## zero-length dimension `{0, 0}` is reported as dynamic. The managed layer
  ## decides staticness itself.

proc ov_rank_is_dynamic*(rank: ov_rank_t): bool {.openvinoImport.}
  ## Reports whether `rank` is dynamic.
  ##
  ## **Quirk**: returns `false` only when `min == max && max > 0`, so rank 0
  ## (a scalar) is reported as dynamic.

{.pop.}
