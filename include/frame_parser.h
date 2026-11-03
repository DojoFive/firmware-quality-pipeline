/* SPDX-License-Identifier: Apache-2.0 */
#ifndef FRAME_PARSER_H
#define FRAME_PARSER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Wire format of an inbound telemetry frame:
 *
 *   +--------+--------+-------------------+-----------------+
 *   | SYNC   | LENGTH | PAYLOAD (LENGTH)  | CRC16 (LE)      |
 *   | 0xA5   | u8     | 0..64 bytes       | over SYNC..LEN+ |
 *   +--------+--------+-------------------+-----------------+
 *
 * This module parses untrusted input, so it is the fuzz target. Everything
 * here is fixed-size and allocation-free.
 */

#define FRAME_SYNC          0xA5u
#define FRAME_MAX_PAYLOAD   64u
#define FRAME_OVERHEAD      4u   /* sync + length + crc16 */

typedef enum {
    FRAME_OK = 0,
    FRAME_ERR_ARG,
    FRAME_ERR_TOO_SHORT,
    FRAME_ERR_BAD_SYNC,
    FRAME_ERR_BAD_LENGTH,
    FRAME_ERR_BAD_CRC
} frame_status_t;

typedef struct {
    uint8_t  length;
    uint8_t  payload[FRAME_MAX_PAYLOAD];
    uint32_t sequence;
} frame_t;

frame_status_t frame_parse(const uint8_t *data, size_t length, frame_t *out);

/* Big-endian u32 read out of the decoded payload. Returns 0 if out of range. */
uint32_t frame_payload_u32(const frame_t *frame, size_t offset);

#ifdef __cplusplus
}
#endif

#endif /* FRAME_PARSER_H */
