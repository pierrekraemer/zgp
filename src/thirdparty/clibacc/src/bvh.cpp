#include <cstdlib>
#include <cmath>

#include "bvh.h"
#include "libacc/bvh_tree.h"

struct Vec3f
{
    float coords[3];
    Vec3f(float f = 0.f)
    {
        coords[0] = f;
        coords[1] = f;
        coords[2] = f;
    }
    Vec3f(float x, float y, float z)
    {
        coords[0] = x;
        coords[1] = y;
        coords[2] = z;
    }
    float &operator[](int i) { return coords[i]; }
    const float &operator[](int i) const { return coords[i]; }
    Vec3f operator+(const Vec3f &v) const { return Vec3f(coords[0] + v.coords[0], coords[1] + v.coords[1], coords[2] + v.coords[2]); }
    Vec3f operator-(const Vec3f &v) const { return Vec3f(coords[0] - v.coords[0], coords[1] - v.coords[1], coords[2] - v.coords[2]); }
    Vec3f operator*(float f) const { return Vec3f(coords[0] * f, coords[1] * f, coords[2] * f); }
    friend Vec3f operator*(float f, const Vec3f &v) { return v * f; }
    void operator+=(const Vec3f &v)
    {
        coords[0] += v.coords[0];
        coords[1] += v.coords[1];
        coords[2] += v.coords[2];
    }
    void operator/=(float f)
    {
        coords[0] /= f;
        coords[1] /= f;
        coords[2] /= f;
    }
    float square_norm() const { return coords[0] * coords[0] + coords[1] * coords[1] + coords[2] * coords[2]; }
    float norm() const { return std::sqrt(square_norm()); }
    Vec3f cross(const Vec3f &v) const
    {
        return Vec3f(coords[1] * v.coords[2] - coords[2] * v.coords[1],
                     coords[2] * v.coords[0] - coords[0] * v.coords[2],
                     coords[0] * v.coords[1] - coords[1] * v.coords[0]);
    }
    float dot(const Vec3f &v) const { return coords[0] * v.coords[0] + coords[1] * v.coords[1] + coords[2] * v.coords[2]; }
};

using BVH = acc::BVHTree<INDEX, Vec3f>;

extern "C"
{
    // TODO: too much data copying..
    // Data could be passed directly as needed by the BVH constructor,
    // i.e. an array of triangles (Vec3f[3])
    // vector could also be avoided by passing raw pointer and size
    void *createTrianglesBVH(INDEX *triangle_vertex_indices, INDEX nb_triangles, void *vertex_position, INDEX nb_vertices)
    {
        const Vec3f *vertex_position_array = static_cast<const Vec3f *>(vertex_position);
        const INDEX nb_indices = nb_triangles * 3;
        std::vector<INDEX> triangle_vertex_indices_vector;
        triangle_vertex_indices_vector.reserve(nb_indices);
        for (INDEX i = 0; i < nb_indices; i++)
            triangle_vertex_indices_vector.push_back(triangle_vertex_indices[i]);
        std::vector<Vec3f> vertex_position_vector;
        vertex_position_vector.reserve(nb_vertices);
        for (INDEX i = 0; i < nb_vertices; i++)
            vertex_position_vector.push_back(vertex_position_array[i]);
        return new BVH(triangle_vertex_indices_vector, vertex_position_vector);
    }

    void destroyTrianglesBVH(void *bvh)
    {
        BVH *b = static_cast<BVH *>(bvh);
        delete b;
    }

    bool intersect(void const *bvh, void const *ray, void *hit)
    {
        BVH const *b = static_cast<const BVH *>(bvh);
        BVH::Ray const *r = static_cast<BVH::Ray const *>(ray);
        BVH::Hit *h = static_cast<BVH::Hit *>(hit);
        return b->intersect(*r, *h);
    }

    void closestPoint(void const *bvh, void const *point, void *cp, INDEX *tri, void *bcoords)
    {
        BVH const *b = static_cast<BVH const *>(bvh);
        Vec3f const *point_vec = static_cast<Vec3f const *>(point);
        Vec3f *cp_vec = static_cast<Vec3f *>(cp);
        Vec3f *bcoords_vec = static_cast<Vec3f *>(bcoords);
        b->closest_point(*point_vec, *cp_vec, *tri, *bcoords_vec);
    }
}
