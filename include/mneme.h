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

/* Use default collection/index ef_search in mneme_collection_search_hnsw. */
#define MNEME_EF_SEARCH_DEFAULT 0u

typedef struct mneme_hnsw_config {
    uint32_t m;
    uint32_t ef_construction;
    uint32_t ef_search;
    uint64_t seed;
} mneme_hnsw_config_t;

/* Returns ABI version for compatibility checks. */
uint32_t mneme_abi_version(void);
/* Returns thread-local diagnostic text from the latest failing call on this thread. */
const char *mneme_last_error(void);

/* Creates a collection handle. Caller owns *out_collection and must free it. */
mneme_status_t mneme_collection_create(
    const char *name,
    uint32_t dimension,
    mneme_metric_t metric,
    mneme_collection_t **out_collection
);

/*
 * Frees a collection handle.
 *
 * Caller must ensure no other thread is using this handle while free runs.
 * After free returns, the handle pointer is invalid.
 */
void mneme_collection_free(mneme_collection_t *collection);

/* Inserts one vector row. */
mneme_status_t mneme_collection_insert(
    mneme_collection_t *collection,
    const char *id,
    const float *vector,
    uint32_t vector_len,
    const char *metadata
);

/*
 * Inserts many rows from contiguous vectors and parallel id/metadata arrays.
 *
 * Semantics:
 * - fail-fast and non-transactional: rows inserted before the first failing row remain inserted.
 * - rows are processed in index order [0, count).
 * - out_inserted (if non-null) is always written with the number of rows inserted
 *   before return (including partial progress on error).
 *
 * Input layout:
 * - ids points to count string pointers (each id must be non-null and NUL-terminated).
 * - vectors points to count * vector_len contiguous floats.
 * - metadata may be null; when non-null it points to count entries where each entry may be null.
 */
mneme_status_t mneme_collection_insert_batch(
    mneme_collection_t *collection,
    const char *const *ids,
    const float *vectors,
    uint32_t vector_len,
    const char *const *metadata,
    uint32_t count,
    uint32_t *out_inserted
);

/* Deletes one row by id. */
mneme_status_t mneme_collection_delete(
    mneme_collection_t *collection,
    const char *id
);

/*
 * Deletes many rows by id array.
 *
 * Semantics:
 * - fail-fast and non-transactional: deletions completed before the first failing row remain applied.
 * - rows are processed in index order [0, count).
 * - out_deleted (if non-null) is always written with the number of rows deleted
 *   before return (including partial progress on error).
 */
mneme_status_t mneme_collection_delete_batch(
    mneme_collection_t *collection,
    const char *const *ids,
    uint32_t count,
    uint32_t *out_deleted
);

/* Returns row count; returns 0 on null/invalid handle and sets last_error. */
uint64_t mneme_collection_count(mneme_collection_t *collection);

/* Performs exact flat top-k search. */
mneme_status_t mneme_collection_search_flat(
    mneme_collection_t *collection,
    const float *query,
    uint32_t query_len,
    uint32_t top_k,
    mneme_results_t **out_results
);

/* Builds in-memory HNSW index from current points. */
mneme_status_t mneme_collection_build_hnsw(
    mneme_collection_t *collection,
    const mneme_hnsw_config_t *config
);

/* Performs HNSW top-k search; use MNEME_EF_SEARCH_DEFAULT for default ef_search. */
mneme_status_t mneme_collection_search_hnsw(
    mneme_collection_t *collection,
    const float *query,
    uint32_t query_len,
    uint32_t top_k,
    /* ef_search = 0 uses collection/index default ef_search */
    uint32_t ef_search,
    mneme_results_t **out_results
);

/* Saves collection canonical state to disk. */
mneme_status_t mneme_collection_save(
    mneme_collection_t *collection,
    const char *path
);

/* Loads collection canonical state from disk into a new handle. */
mneme_status_t mneme_collection_load(
    const char *path,
    mneme_collection_t **out_collection
);

/* Returns number of search results. */
uint32_t mneme_results_len(const mneme_results_t *results);
/* Returns borrowed id pointer valid until mneme_results_free. */
const char *mneme_results_id(const mneme_results_t *results, uint32_t index);
/* Returns score at index. */
float mneme_results_score(const mneme_results_t *results, uint32_t index);
/* Frees result handle and invalidates borrowed id pointers. */
void mneme_results_free(mneme_results_t *results);

#ifdef __cplusplus
}
#endif

#endif
