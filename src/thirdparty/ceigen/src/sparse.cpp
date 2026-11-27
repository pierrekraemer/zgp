#include "sparse.h"
#include <eigen/Eigen/Sparse>
#include <utility>

using SparseMatrix = Eigen::SparseMatrix<ceigen_scalar, Eigen::ColMajor, ceigen_index>;
using DenseMatrix = Eigen::Matrix<ceigen_scalar, Eigen::Dynamic, Eigen::Dynamic>;
using Vector = Eigen::Matrix<ceigen_scalar, Eigen::Dynamic, 1>;

struct CEigenTripletIterator {
  const CEigenTriplet *ptr;

  ceigen_index row() const { return ptr->row; }
  ceigen_index col() const { return ptr->col; }
  ceigen_scalar value() const { return ptr->value; }

  const CEigenTripletIterator &operator*() const { return *this; }
  const CEigenTripletIterator *operator->() const { return this; }
  CEigenTripletIterator &operator++() {
    ++ptr;
    return *this;
  }
  bool operator==(const CEigenTripletIterator &other) const {
    return ptr == other.ptr;
  }
  bool operator!=(const CEigenTripletIterator &other) const {
    return ptr != other.ptr;
  }
};

struct CEigenSparseMatrix {
  SparseMatrix inner;
  template <typename... Args>
  explicit CEigenSparseMatrix(Args &&...args)
      : inner(std::forward<Args>(args)...) {}
};

struct CEigenFactorizedSparseMatrix {
  Eigen::SimplicialLDLT<SparseMatrix> inner;
  explicit CEigenFactorizedSparseMatrix(const SparseMatrix &mat) : inner(mat) {}
};

extern "C" {
CEigenSparseMatrix *ceigen_createSparseMatrix(ceigen_index rows,
                                              ceigen_index cols) {
  return new CEigenSparseMatrix(rows, cols);
}

CEigenSparseMatrix *
ceigen_createSparseMatrixFromTriplets(ceigen_index rows, ceigen_index cols,
                                      const CEigenTriplet *triplets,
                                      ceigen_index nb_triplets) {
  auto *mat = new CEigenSparseMatrix(rows, cols);
  if (nb_triplets > 0)
    mat->inner.setFromTriplets(CEigenTripletIterator{triplets},
                               CEigenTripletIterator{triplets + nb_triplets});
  return mat;
}

CEigenSparseMatrix *
ceigen_createDiagonalSparseMatrixFromArray(const ceigen_scalar *diag_vals,
                                           ceigen_index size) {
  Eigen::Map<const Vector> diag(diag_vals, size);
  return new CEigenSparseMatrix(diag.asDiagonal());
}

void ceigen_destroySparseMatrix(CEigenSparseMatrix *mat) { delete mat; }

void ceigen_mulSparseMatrixScalar(const CEigenSparseMatrix *mat,
                                  ceigen_scalar scalar,
                                  CEigenSparseMatrix *matOut) {
  matOut->inner = scalar * mat->inner;
}

void ceigen_addSparseMatrices(const CEigenSparseMatrix *matA,
                              const CEigenSparseMatrix *matB,
                              CEigenSparseMatrix *matOut) {
  matOut->inner = matA->inner + matB->inner;
}

void ceigen_directSolveSymmetricSparseLinearSystem(
    const CEigenSparseMatrix *mat, const ceigen_scalar *b, ceigen_scalar *x,
    ceigen_index size) {
  Eigen::Map<const Vector> bVec(b, size);
  Eigen::Map<Vector> xVec(x, size);

  Eigen::SimplicialLDLT<SparseMatrix> solver(mat->inner);
  xVec = solver.solve(bVec);
}

void ceigen_iterativeSolveSymmetricSparseLinearSystem(
    const CEigenSparseMatrix *mat, const ceigen_scalar *b, ceigen_scalar *x,
    ceigen_index size, ceigen_index max_iterations, ceigen_scalar tolerance) {
  Eigen::Map<const Vector> bVec(b, size);
  Eigen::Map<Vector> xVec(x, size);

  Eigen::ConjugateGradient<SparseMatrix, Eigen::Lower | Eigen::Upper> solver;
  solver.setMaxIterations(max_iterations);
  solver.setTolerance(tolerance);
  solver.compute(mat->inner);
  xVec = solver.solveWithGuess(bVec, xVec);
}

void ceigen_iterativeSolveSymmetricSparseLinearSystemMultipleRHS(
    const CEigenSparseMatrix *mat, const ceigen_scalar *b, ceigen_scalar *x,
    ceigen_index rows, ceigen_index cols, ceigen_index max_iterations,
    ceigen_scalar tolerance) {
  Eigen::Map<const DenseMatrix> bMat(b, rows, cols);
  Eigen::Map<DenseMatrix> xMat(x, rows, cols);

  Eigen::ConjugateGradient<SparseMatrix, Eigen::Lower | Eigen::Upper> solver;
  solver.setMaxIterations(max_iterations);
  solver.setTolerance(tolerance);
  solver.compute(mat->inner);
  xMat = solver.solveWithGuess(bMat, xMat);
}

CEigenFactorizedSparseMatrix *
ceigen_factorizeSymmetricSparseMatrix(const CEigenSparseMatrix *mat) {
  return new CEigenFactorizedSparseMatrix(mat->inner);
}

void ceigen_solveWithFactorizedMatrix(
    const CEigenFactorizedSparseMatrix *solver, const ceigen_scalar *b,
    ceigen_scalar *x, ceigen_index size) {
  Eigen::Map<const Vector> bVec(b, size);
  Eigen::Map<Vector> xVec(x, size);
  xVec = solver->inner.solve(bVec);
}

void ceigen_solveWithFactorizedMatrixMultipleRHS(
    const CEigenFactorizedSparseMatrix *solver, const ceigen_scalar *b,
    ceigen_scalar *x, ceigen_index rows, ceigen_index cols) {
  Eigen::Map<const DenseMatrix> bMat(b, rows, cols);
  Eigen::Map<DenseMatrix> xMat(x, rows, cols);
  xMat = solver->inner.solve(bMat);
}

void ceigen_destroyFactorizedMatrix(CEigenFactorizedSparseMatrix *solver) {
  delete solver;
}
}
