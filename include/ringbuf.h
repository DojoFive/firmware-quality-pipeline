/* SPDX-License-Identifier: Apache-2.0 */
#ifndef RINGBUF_H
#define RINGBUF_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Fixed-capacity byte FIFO. The caller owns the storage, so there is no
 * dynamic allocation anywhere in this module.
 */
typedef struct {
    uint8_t *storage;
    size_t   capacity;
    size_t   head;
    size_t   tail;
    size_t   count;
} ringbuf_t;

bool   ringbuf_init(ringbuf_t *rb, uint8_t *storage, size_t capacity);
bool   ringbuf_push(ringbuf_t *rb, uint8_t value);
bool   ringbuf_pop(ringbuf_t *rb, uint8_t *out);
size_t ringbuf_count(const ringbuf_t *rb);
bool   ringbuf_is_full(const ringbuf_t *rb);
void   ringbuf_reset(ringbuf_t *rb);

#ifdef __cplusplus
}
#endif

#endif /* RINGBUF_H */
