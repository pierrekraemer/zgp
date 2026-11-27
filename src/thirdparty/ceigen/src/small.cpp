#include "small.h"
#include <eigen/Eigen/Dense>

using Matrix3d = Eigen::Matrix<ceigen_scalar, 3, 3>;
using Vector3d = Eigen::Matrix<ceigen_scalar, 3, 1>;
using Matrix4d = Eigen::Matrix<ceigen_scalar, 4, 4>;
using Vector4d = Eigen::Matrix<ceigen_scalar, 4, 1>;

extern "C" {
void ceigen_computeInverseWithCheck4d(const ceigen_scalar (*mat)[16],
                                      ceigen_scalar (*inv)[16],
                                      bool *invertible) {
  Eigen::Map<const Matrix4d> m(*mat);
  Eigen::Map<Matrix4d> inverse(*inv);
  m.computeInverseWithCheck(inverse, *invertible);
}

void ceigen_solveSymmetricLinearSystem4d(const ceigen_scalar (*mat)[16],
                                         const ceigen_scalar (*b)[4],
                                         ceigen_scalar (*x)[4]) {
  Eigen::Map<const Matrix4d> m(*mat);
  Eigen::Map<const Vector4d> bVec(*b);
  Eigen::Map<Vector4d> xVec(*x);
  Eigen::LDLT<Matrix4d> solver(m);
  xVec = solver.solve(bVec);
}

void ceigen_eigenSolver3d(const ceigen_scalar (*mat)[9],
                          ceigen_scalar (*eigenvalues)[3],
                          ceigen_scalar (*eigenvectors)[9]) {
  Eigen::Map<const Matrix3d> m(*mat);
  Eigen::Map<Vector3d> evals(*eigenvalues);
  Eigen::Map<Matrix3d> evecs(*eigenvectors);
  Eigen::SelfAdjointEigenSolver<Matrix3d> solver(m);
  evals = solver.eigenvalues();
  evecs = solver.eigenvectors();
}

void ceigen_svd3d(const ceigen_scalar (*mat)[9], ceigen_scalar (*U)[9],
                  ceigen_scalar (*S)[3], ceigen_scalar (*V)[9]) {
  Eigen::Map<const Matrix3d> m(*mat);
  Eigen::Map<Matrix3d> uMat(*U);
  Eigen::Map<Vector3d> sVec(*S);
  Eigen::Map<Matrix3d> vMat(*V);
  Eigen::JacobiSVD<Matrix3d> svd(m, Eigen::ComputeFullU | Eigen::ComputeFullV);
  uMat = svd.matrixU();
  sVec = svd.singularValues();
  vMat = svd.matrixV();
}
}
