#ifndef MNEME_H
#define MNEME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mneme_collection mneme_collection_t;
typedef struct mneme_results mneme_results_t;

typedef uint32_t mneme_status_t;
enum {
    MNEME_OK = 0,
    MNEME_ERROR_INVALID_ARGUMENT = 1,
    MNEME_ERROR_OUT_OF_MEMORY = 2,
    MNEME_ERROR_DIMENSION_MISMATCH = 3,
    MNEME_ERROR_IO = 4,
    MNEME_ERROR_INDEX_NOT_BUILT = 5,
    MNEME_ERROR_INDEX_STALE = 6,
    MNEME_ERROR_INTERNAL = 255
};

typedef uint32_t mneme_metric_t;
enum {
    MNEME_METRIC_COSINE = 1
};

typedef struct mneme_hnsw_config {
    uint32_t m;
    uint32_t ef_construction;
    uint32_t ef_search;
    uint64_t seed;
} mneme_hnsw_config_t;

uint32_t mneme_abi_version(void);
const char *mneme_last_error(void);

mneme_status_t mneme_collection_create(
    const char *name,
    uint32_t dimension,
    mneme_metric_t metric,
    mneme_collection_t **out_collection
);

void mneme_collection_free(mneme_collection_t *collection);

mneme_status_t mneme_collection_insert(
    mneme_collection_t *collection,
    const char *id,
    const float *vector,
    uint32_t vector_len,
    const char *metadata
);

mneme_status_t mneme_collection_insert_batch(
    mneme_collection_t *collection,
    const char *const *ids,
    const float *vectors,
    uint32_t vector_len,
    const char *const *metadata,
    uint32_t count,
    uint32_t *out_inserted
);

mneme_status_t mneme_collection_delete(
    mneme_collection_t *collection,
    const char *id
);

mneme_status_t mneme_collection_delete_batch(
    mneme_collection_t *collection,
    const char *const *ids,
    uint32_t count,
    uint32_t *out_deleted
);

uint64_t mneme_collection_count(const mneme_collection_t *collection);

mneme_status_t mneme_collection_search_flat(
    mneme_collection_t *collection,
    const float *query,
    uint32_t query_len,
    uint32_t top_k,
    mneme_results_t **out_results
);

mneme_status_t mneme_collection_build_hnsw(
    mneme_collection_t *collection,
    const mneme_hnsw_config_t *config
);

mneme_status_t mneme_collection_search_hnsw(
    mneme_collection_t *collection,
    const float *query,
    uint32_t query_len,
    uint32_t top_k,
    /* ef_search = 0 uses collection/index default ef_search */
    uint32_t ef_search,
    mneme_results_t **out_results
);

mneme_status_t mneme_collection_save(
    mneme_collection_t *collection,
    const char *path
);

mneme_status_t mneme_collection_load(
    const char *path,
    mneme_collection_t **out_collection
);

uint32_t mneme_results_len(const mneme_results_t *results);
const char *mneme_results_id(const mneme_results_t *results, uint32_t index);
float mneme_results_score(const mneme_results_t *results, uint32_t index);
void mneme_results_free(mneme_results_t *results);

#ifdef __cplusplus
}
#endif

#endif
