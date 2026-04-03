#include "small.h"
#include <eigen/Eigen/Dense>

using Matrix3d = Eigen::Matrix<SCALAR, 3, 3>;
using Vector3d = Eigen::Matrix<SCALAR, 3, 1>;
using Matrix4d = Eigen::Matrix<SCALAR, 4, 4>;
using Vector4d = Eigen::Matrix<SCALAR, 4, 1>;

extern "C"
{
    void computeInverseWithCheck4d(const SCALAR (*mat)[16], SCALAR (*inv)[16], bool *invertible)
    {
        Eigen::Map<const Matrix4d> m(*mat);
        Eigen::Map<Matrix4d> inverse(*inv);
        m.computeInverseWithCheck(inverse, *invertible);
    }

    void solveSymmetricLinearSystem4d(const SCALAR (*mat)[16], const SCALAR (*b)[4], SCALAR (*x)[4])
    {
        Eigen::Map<const Matrix4d> m(*mat);
        Eigen::Map<const Vector4d> bVec(*b);
        Eigen::Map<Vector4d> xVec(*x);
        Eigen::LDLT<Matrix4d> solver(m);
        xVec = solver.solve(bVec);
    }

    void eigenSolver3d(const SCALAR (*mat)[9], SCALAR (*eigenvalues)[3], SCALAR (*eigenvectors)[9])
    {
        Eigen::Map<const Matrix3d> m(*mat);
        Eigen::Map<Vector3d> evals(*eigenvalues);
        Eigen::Map<Matrix3d> evecs(*eigenvectors);
        Eigen::SelfAdjointEigenSolver<Matrix3d> solver(m);
        evals = solver.eigenvalues();
        evecs = solver.eigenvectors();
    }
}
