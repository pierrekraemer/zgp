#include <cstdlib>
#include <cmath>

#include "kd.h"
#include "libacc/kd_tree.h"

// struct Vec3f
// {
//     float coords[3];
//     Vec3f(float f = 0.f)
//     {
//         coords[0] = f;
//         coords[1] = f;
//         coords[2] = f;
//     }
//     Vec3f(float x, float y, float z)
//     {
//         coords[0] = x;
//         coords[1] = y;
//         coords[2] = z;
//     }
//     float &operator[](int i) { return coords[i]; }
//     const float &operator[](int i) const { return coords[i]; }
//     Vec3f operator+(const Vec3f &v) const { return Vec3f(coords[0] + v.coords[0], coords[1] + v.coords[1], coords[2] + v.coords[2]); }
//     Vec3f operator-(const Vec3f &v) const { return Vec3f(coords[0] - v.coords[0], coords[1] - v.coords[1], coords[2] - v.coords[2]); }
//     Vec3f operator*(float f) const { return Vec3f(coords[0] * f, coords[1] * f, coords[2] * f); }
//     friend Vec3f operator*(float f, const Vec3f &v) { return v * f; }
//     void operator+=(const Vec3f &v)
//     {
//         coords[0] += v.coords[0];
//         coords[1] += v.coords[1];
//         coords[2] += v.coords[2];
//     }
//     void operator/=(float f)
//     {
//         coords[0] /= f;
//         coords[1] /= f;
//         coords[2] /= f;
//     }
//     float square_norm() const { return coords[0] * coords[0] + coords[1] * coords[1] + coords[2] * coords[2]; }
//     float norm() const { return std::sqrt(square_norm()); }
//     Vec3f cross(const Vec3f &v) const
//     {
//         return Vec3f(coords[1] * v.coords[2] - coords[2] * v.coords[1],
//                      coords[2] * v.coords[0] - coords[0] * v.coords[2],
//                      coords[0] * v.coords[1] - coords[1] * v.coords[0]);
//     }
//     float dot(const Vec3f &v) const { return coords[0] * v.coords[0] + coords[1] * v.coords[1] + coords[2] * v.coords[2]; }
// };

using KDTree = acc::KDTree<3, INDEX>;

extern "C"
{
    void *createKDTree(void *vertex_position, INDEX nb_vertices)
    {
        auto *vertex_position_array = static_cast<const std::array<float, 3> *>(vertex_position);
        return new KDTree(vertex_position_array, nb_vertices);
    }

    void destroyKDTree(void *kdtree)
    {
        KDTree *k = static_cast<KDTree *>(kdtree);
        delete k;
    }

    bool closestPoint(void const *kdtree, void const *point, void *cp)
    {
        auto *k = static_cast<const KDTree *>(kdtree);
        auto *p = static_cast<const std::array<float, 3> *>(point);
        auto *closest = static_cast<std::array<float, 3> *>(cp);

        std::pair<INDEX, float> nn;
        if (k->find_nn(*p, &nn))
        {
            *closest = k->vertex(nn.first);
            return true;
        }
        else
            return false;
    }
}
