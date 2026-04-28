#include "mneme.h"

int main(void) {
    mneme_collection_t *collection = 0;
    if (mneme_collection_create("docs", 3, MNEME_METRIC_COSINE, &collection) != MNEME_OK) {
        return 1;
    }

    const float v1[3] = {1.0f, 0.0f, 0.0f};
    const float v2[3] = {0.0f, 1.0f, 0.0f};
    const float v3[3] = {0.0f, 0.0f, 1.0f};
    if (mneme_collection_insert(collection, "a", v1, 3, 0) != MNEME_OK) return 1;
    if (mneme_collection_insert(collection, "b", v2, 3, 0) != MNEME_OK) return 1;
    if (mneme_collection_insert(collection, "c", v3, 3, 0) != MNEME_OK) return 1;

    mneme_results_t *flat_results = 0;
    if (mneme_collection_search_flat(collection, v1, 3, 2, &flat_results) != MNEME_OK) return 1;
    mneme_results_free(flat_results);

    const mneme_hnsw_config_t cfg = {
        .m = 16,
        .ef_construction = 64,
        .ef_search = 32,
        .seed = 42,
    };
    if (mneme_collection_build_hnsw(collection, &cfg) != MNEME_OK) return 1;

    mneme_results_t *hnsw_results = 0;
    if (mneme_collection_search_hnsw(collection, v1, 3, 2, 64, &hnsw_results) != MNEME_OK) return 1;
    mneme_results_free(hnsw_results);

    mneme_collection_free(collection);
    return 0;
}
