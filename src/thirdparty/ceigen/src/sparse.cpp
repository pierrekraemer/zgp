#include "sparse.h"
#include <eigen/Eigen/Sparse>

using SparseMatrix = Eigen::SparseMatrix<SCALAR, Eigen::ColMajor, INDEX>;
using Vector = Eigen::Matrix<SCALAR, Eigen::Dynamic, 1>;
using Triplet = Eigen::Triplet<SCALAR, INDEX>;

extern "C"
{
    void mulSparseMatrixScalar(const void *mat, SCALAR scalar, void *matOut)
    {
        const SparseMatrix *sparseMat = static_cast<const SparseMatrix *>(mat);
        SparseMatrix *sparseMatOut = static_cast<SparseMatrix *>(matOut);
        *sparseMatOut = scalar * (*sparseMat);
    }

    void addSparseMatrices(const void *matA, const void *matB, void *matOut)
    {
        const SparseMatrix *sparseMatA = static_cast<const SparseMatrix *>(matA);
        const SparseMatrix *sparseMatB = static_cast<const SparseMatrix *>(matB);
        SparseMatrix *sparseMatOut = static_cast<SparseMatrix *>(matOut);
        *sparseMatOut = (*sparseMatA) + (*sparseMatB);
    }

    void *createSparseMatrix(INDEX rows, INDEX cols)
    {
        return new SparseMatrix(rows, cols);
    }

    void *createSparseMatrixFromTriplets(INDEX rows, INDEX cols,
                                         const void *triplets,
                                         INDEX nb_triplets)
    {
        const Triplet *triplets_ptr = static_cast<const Triplet *>(triplets);
        SparseMatrix *mat = new SparseMatrix(rows, cols);
        std::vector<Triplet> triplets_vec;
        triplets_vec.reserve(nb_triplets);
        for (INDEX i = 0; i < nb_triplets; i++)
            triplets_vec.push_back(triplets_ptr[i]);
        mat->setFromTriplets(triplets_vec.begin(), triplets_vec.end());
        return mat;
    }

    void *createDiagonalSparseMatrixFromArray(const SCALAR *diag_vals, INDEX size)
    {
        Eigen::Map<const Vector> diag(diag_vals, size);
        return new SparseMatrix(diag.asDiagonal());
    }

    void solveSymmetricSparseLinearSystem(const void *mat, const SCALAR *b, SCALAR *x, INDEX size)
    {
        const SparseMatrix *sparseMat = static_cast<const SparseMatrix *>(mat);
        Eigen::Map<const Vector> bVec(b, size);
        Eigen::Map<Vector> xVec(x, size);

        Eigen::SimplicialLDLT<SparseMatrix> solver(*sparseMat);
        xVec = solver.solve(bVec);
    }

    void destroySparseMatrix(void *mat)
    {
        SparseMatrix *sparseMat = static_cast<SparseMatrix *>(mat);
        delete sparseMat;
    }
}
