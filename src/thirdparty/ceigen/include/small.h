#pragma once

#include <stdbool.h>

#include "ceigen_types.h"

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

void ceigen_computeInverseWithCheck4d(const ceigen_scalar (*mat)[16],
                                      ceigen_scalar (*inv)[16],
                                      bool *invertible);
void ceigen_solveSymmetricLinearSystem4d(const ceigen_scalar (*mat)[16],
                                         const ceigen_scalar (*b)[4],
                                         ceigen_scalar (*x)[4]);
void ceigen_eigenSolver3d(const ceigen_scalar (*mat)[9],
                          ceigen_scalar (*eigenvalues)[3],
                          ceigen_scalar (*eigenvectors)[9]);
void ceigen_svd3d(const ceigen_scalar (*mat)[9], ceigen_scalar (*U)[9],
                  ceigen_scalar (*S)[3], ceigen_scalar (*V)[9]);

#ifdef __cplusplus
}
#endif /* __cplusplus */
