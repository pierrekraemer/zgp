#pragma once

#define SCALAR float
#define INDEX unsigned int

#ifdef __cplusplus
extern "C"
{
#endif /* __cplusplus */

    void *createKDTree(void *vertex_position, INDEX nb_vertices);
    void destroyKDTree(void *kdtree);

    // cp is a pointer to an index of the closest point
    // returns true if a closest point was found, false otherwise (e.g. if the tree is empty)
    bool nearestNeighbor(void const *kdtree, void const *point, INDEX *cp_index);
    // cp is a pointer to an array of indices of the closest points
    // n is the number of closest points to find
    // returns the number of closest points found (can be less than n if there are not enough points in the tree)
    INDEX nearestNeighbors(void const *kdtree, void const *point, INDEX n, INDEX *cp_indices);

#ifdef __cplusplus
}
#endif /* __cplusplus */
