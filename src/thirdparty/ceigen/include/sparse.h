#pragma once

#define SCALAR double
#define INDEX int

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

    void mulSparseMatrixScalar(const void *mat, SCALAR scalar, void *matOut);
    void addSparseMatrices(const void *matA, const void *matB, void *matOut);

    void *createSparseMatrix(INDEX rows, INDEX cols);
    void *createSparseMatrixFromTriplets(INDEX rows, INDEX cols,
                                         const void *triplets,
                                         INDEX nb_triplets);
    void *createDiagonalSparseMatrixFromArray(const SCALAR *diag_vals, INDEX size);
    void solveSymmetricSparseLinearSystem(const void *mat, const SCALAR *b, SCALAR *x, INDEX size);
    void destroySparseMatrix(void *mat);

#ifdef __cplusplus
}
#endif /* __cplusplus */
