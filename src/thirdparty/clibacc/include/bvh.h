#pragma once

#define SCALAR float
#define INDEX unsigned int

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

    void *createTrianglesBVH(INDEX *triangle_vertex_indices, INDEX nb_triangles, void *vertex_position, INDEX nb_vertices);
    void destroyTrianglesBVH(void *bvh);

    bool intersect(void const *bvh, void const *ray, void *hit);
    void closestPoint(void const *bvh, void const *point, void *cp, INDEX *tri, void *bcoords);

#ifdef __cplusplus
}
#endif /* __cplusplus */
