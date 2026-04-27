#pragma once

#define SCALAR float
#define INDEX unsigned int

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

    void *createKDTree(void *vertex_position, INDEX nb_vertices);
    void destroyKDTree(void *kdtree);

    bool closestPoint(void const *kdtree, void const *point, void *cp);

#ifdef __cplusplus
}
#endif /* __cplusplus */
