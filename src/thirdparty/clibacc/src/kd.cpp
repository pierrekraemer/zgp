#include <cstdlib>
#include <cmath>

#include "kd.h"
#include "libacc/kd_tree.h"

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

    bool nearestNeighbor(void const *kdtree, void const *point, INDEX *cp_index)
    {
        auto *k = static_cast<const KDTree *>(kdtree);
        auto *p = static_cast<const std::array<float, 3> *>(point);

        std::pair<INDEX, float> nn;
        if (k->find_nn(*p, &nn))
        {
            *cp_index = nn.first;
            return true;
        }
        else
            return false;
    }

    INDEX nearestNeighbors(void const *kdtree, void const *point, INDEX n, INDEX *cp_indices)
    {
        auto *k = static_cast<const KDTree *>(kdtree);
        auto *p = static_cast<const std::array<float, 3> *>(point);

        std::vector<std::pair<INDEX, float>> nns;
        k->find_nns(*p, n, &nns);
        for (INDEX i = 0; i < nns.size(); ++i)
            cp_indices[i] = nns[i].first;
        return nns.size();
    }
}
