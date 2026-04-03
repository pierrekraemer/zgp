#pragma once

#define SCALAR double
#define INDEX int

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

    void *createDenseMatrix(INDEX rows, INDEX cols);
    void destroyDenseMatrix(void *mat);

    void setDenseMatrixRow(void *mat, INDEX row, const SCALAR *row_vals, INDEX size);
    void solveDenseLeastSquares(const void *matA, const SCALAR *b, SCALAR *x, INDEX rows, INDEX cols);

#ifdef __cplusplus
}
#endif /* __cplusplus */
