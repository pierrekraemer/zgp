#pragma once

#include <stdbool.h>

#define SCALAR double

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

    void computeInverseWithCheck4d(const SCALAR (*mat)[16], SCALAR (*inv)[16], bool *invertible);
    void solveSymmetricLinearSystem4d(const SCALAR (*mat)[16], const SCALAR (*b)[4], SCALAR (*x)[4]);
    void eigenSolver3d(const SCALAR (*mat)[9], SCALAR (*eigenvalues)[3], SCALAR (*eigenvectors)[9]);

#ifdef __cplusplus
}
#endif /* __cplusplus */
