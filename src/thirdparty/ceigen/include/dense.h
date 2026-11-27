#pragma once

#include "ceigen_types.h"

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

void ceigen_solveDenseLeastSquares(const ceigen_scalar *matA,
                                   const ceigen_scalar *b, ceigen_scalar *x,
                                   ceigen_index rows, ceigen_index cols);

#ifdef __cplusplus
}
#endif /* __cplusplus */
