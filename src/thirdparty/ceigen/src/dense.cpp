#include "dense.h"
#include <eigen/Eigen/Dense>

using DenseMatrix = Eigen::Matrix<ceigen_scalar, Eigen::Dynamic, Eigen::Dynamic>;
using Vector = Eigen::Matrix<ceigen_scalar, Eigen::Dynamic, 1>;

extern "C" {
void ceigen_solveDenseLeastSquares(const ceigen_scalar *matA,
                                   const ceigen_scalar *b, ceigen_scalar *x,
                                   ceigen_index rows, ceigen_index cols) {
  Eigen::Map<const DenseMatrix> denseMatA(matA, rows, cols);
  Eigen::Map<const Vector> bVec(b, rows);
  Eigen::Map<Vector> xVec(x, cols);
  Eigen::LDLT<DenseMatrix> solver(denseMatA.transpose() * denseMatA);
  xVec = solver.solve(denseMatA.transpose() * bVec);
}
}
