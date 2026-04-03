#include "sparse.h"
#include <eigen/Eigen/Dense>

using DenseMatrix = Eigen::Matrix<SCALAR, Eigen::Dynamic, Eigen::Dynamic>;
using Vector = Eigen::Matrix<SCALAR, Eigen::Dynamic, 1>;

extern "C"
{
    void *createDenseMatrix(INDEX rows, INDEX cols)
    {
        DenseMatrix *denseMat = new DenseMatrix(rows, cols);
        denseMat->setZero();
        return denseMat;
    }

    void destroyDenseMatrix(void *mat)
    {
        DenseMatrix *denseMat = static_cast<DenseMatrix *>(mat);
        delete denseMat;
    }

    void setDenseMatrixRow(void *mat, INDEX row, const SCALAR *row_vals, INDEX size)
    {
        DenseMatrix *denseMat = static_cast<DenseMatrix *>(mat);
        Eigen::Map<const Vector> rowVec(row_vals, size);
        denseMat->row(row) = rowVec.transpose();
    }

    void solveDenseLeastSquares(const void *matA, const SCALAR *b, SCALAR *x, INDEX rows, INDEX cols)
    {
        const DenseMatrix *denseMatA = static_cast<const DenseMatrix *>(matA);
        Eigen::Map<const Vector> bVec(b, rows);
        Eigen::Map<Vector> xVec(x, cols);
        Eigen::LDLT<DenseMatrix> solver(denseMatA->transpose() * (*denseMatA));
        xVec = solver.solve(denseMatA->transpose() * bVec);
    }
}
