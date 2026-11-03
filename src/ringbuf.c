/* SPDX-License-Identifier: Apache-2.0 */
#include "ringbuf.h"

bool ringbuf_init(ringbuf_t *rb, uint8_t *storage, size_t capacity)
{
    if ((rb == NULL) || (storage == NULL) || (capacity == 0u)) {
        return false;
    }

    rb->storage  = storage;
    rb->capacity = capacity;
    rb->head     = 0u;
    rb->tail     = 0u;
    rb->count    = 0u;

    return true;
}

bool ringbuf_push(ringbuf_t *rb, uint8_t value)
{
    if ((rb == NULL) || (rb->storage == NULL) || (rb->count == rb->capacity)) {
        return false;
    }

    rb->storage[rb->head] = value;
    rb->head              = (rb->head + 1u) % rb->capacity;
    rb->count++;

    return true;
}

bool ringbuf_pop(ringbuf_t *rb, uint8_t *out)
{
    if ((rb == NULL) || (out == NULL) || (rb->storage == NULL) || (rb->count == 0u)) {
        return false;
    }

    *out = rb->storage[rb->tail];

#if DEMO_BUG == 4
    /*
     * Seeded defect: the modulus is wrong by one. Every access stays inside
     * the allocation, so no sanitizer or static analyzer reports it. Only a
     * test that pushes past the wrap point detects it.
     */
    rb->tail = (rb->tail + 1u) % (rb->capacity - 1u);
#else
    rb->tail = (rb->tail + 1u) % rb->capacity;
#endif

    rb->count--;

    return true;
}

size_t ringbuf_count(const ringbuf_t *rb)
{
    return (rb == NULL) ? 0u : rb->count;
}

bool ringbuf_is_full(const ringbuf_t *rb)
{
    return (rb != NULL) && (rb->count == rb->capacity);
}

void ringbuf_reset(ringbuf_t *rb)
{
    if (rb != NULL) {
        rb->head  = 0u;
        rb->tail  = 0u;
        rb->count = 0u;
    }
}
