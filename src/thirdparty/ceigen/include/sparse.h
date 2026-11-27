#pragma once

#include "ceigen_types.h"

#ifdef __cplusplus
extern "C" {
#endif /* __cplusplus */

typedef struct CEigenSparseMatrix CEigenSparseMatrix;
typedef struct CEigenFactorizedSparseMatrix CEigenFactorizedSparseMatrix;

typedef struct CEigenTriplet {
  ceigen_index row;
  ceigen_index col;
  ceigen_scalar value;
} CEigenTriplet;

CEigenSparseMatrix *ceigen_createSparseMatrix(ceigen_index rows,
                                              ceigen_index cols);
CEigenSparseMatrix *
ceigen_createSparseMatrixFromTriplets(ceigen_index rows, ceigen_index cols,
                                      const CEigenTriplet *triplets,
                                      ceigen_index nb_triplets);
CEigenSparseMatrix *
ceigen_createDiagonalSparseMatrixFromArray(const ceigen_scalar *diag_vals,
                                           ceigen_index size);
void ceigen_destroySparseMatrix(CEigenSparseMatrix *mat);

void ceigen_mulSparseMatrixScalar(const CEigenSparseMatrix *mat,
                                  ceigen_scalar scalar,
                                  CEigenSparseMatrix *matOut);
void ceigen_addSparseMatrices(const CEigenSparseMatrix *matA,
                              const CEigenSparseMatrix *matB,
                              CEigenSparseMatrix *matOut);

void ceigen_directSolveSymmetricSparseLinearSystem(
    const CEigenSparseMatrix *mat, const ceigen_scalar *b, ceigen_scalar *x,
    ceigen_index size);
void ceigen_iterativeSolveSymmetricSparseLinearSystem(
    const CEigenSparseMatrix *mat, const ceigen_scalar *b, ceigen_scalar *x,
    ceigen_index size, ceigen_index max_iterations, ceigen_scalar tolerance);
void ceigen_iterativeSolveSymmetricSparseLinearSystemMultipleRHS(
    const CEigenSparseMatrix *mat, const ceigen_scalar *b, ceigen_scalar *x,
    ceigen_index rows, ceigen_index cols, ceigen_index max_iterations,
    ceigen_scalar tolerance);

CEigenFactorizedSparseMatrix *
ceigen_factorizeSymmetricSparseMatrix(const CEigenSparseMatrix *mat);
void ceigen_solveWithFactorizedMatrix(
    const CEigenFactorizedSparseMatrix *solver, const ceigen_scalar *b,
    ceigen_scalar *x, ceigen_index size);
void ceigen_solveWithFactorizedMatrixMultipleRHS(
    const CEigenFactorizedSparseMatrix *solver, const ceigen_scalar *b,
    ceigen_scalar *x, ceigen_index rows, ceigen_index cols);
void ceigen_destroyFactorizedMatrix(CEigenFactorizedSparseMatrix *solver);

#ifdef __cplusplus
}
#endif /* __cplusplus */
