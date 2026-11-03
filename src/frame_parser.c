/* SPDX-License-Identifier: Apache-2.0 */
#include "frame_parser.h"

#include <string.h>

#include "crc16.h"

uint32_t frame_payload_u32(const frame_t *frame, size_t offset)
{
    if ((frame == NULL) || ((offset + 4u) > (size_t)frame->length)) {
        return 0u;
    }

#if DEMO_BUG == 2
    /*
     * Seeded defect: each byte promotes to int before the shift, so any
     * payload byte with the top bit set overflows a signed int at << 24.
     * On most targets the result still looks correct, every unit test
     * passes, and no static analyzer flags it. UndefinedBehaviorSanitizer
     * catches it on the first test that uses a byte >= 0x80.
     */
    return (uint32_t)(((int)frame->payload[offset] << 24) |
                      ((int)frame->payload[offset + 1u] << 16) |
                      ((int)frame->payload[offset + 2u] << 8) |
                      ((int)frame->payload[offset + 3u]));
#else
    return (((uint32_t)frame->payload[offset] << 24) |
            ((uint32_t)frame->payload[offset + 1u] << 16) |
            ((uint32_t)frame->payload[offset + 2u] << 8) |
            ((uint32_t)frame->payload[offset + 3u]));
#endif
}

frame_status_t frame_parse(const uint8_t *data, size_t length, frame_t *out)
{
    if ((data == NULL) || (out == NULL)) {
        return FRAME_ERR_ARG;
    }

#if DEMO_BUG == 3
    /*
     * Seeded defect: read of an uninitialized automatic variable. cppcheck,
     * clang-tidy and gcc -fanalyzer all catch this without running anything.
     */
    size_t minimum_length;
    if (length < minimum_length) {
        return FRAME_ERR_TOO_SHORT;
    }
#else
    if (length < (size_t)FRAME_OVERHEAD) {
        return FRAME_ERR_TOO_SHORT;
    }
#endif

    if (data[0] != (uint8_t)FRAME_SYNC) {
        return FRAME_ERR_BAD_SYNC;
    }

    const uint8_t payload_length = data[1];
    if (payload_length > (uint8_t)FRAME_MAX_PAYLOAD) {
        return FRAME_ERR_BAD_LENGTH;
    }

#if DEMO_BUG == 1
    /*
     * Seeded defect: off by one. A frame carrying N payload bytes needs
     * N + 4 bytes on the wire, not N + 3. At exactly N + 3 the CRC fetch
     * below reads one byte past the caller's buffer. The unit tests only
     * pass well-formed frames, so they never reach it. AddressSanitizer
     * reports it as soon as the fuzzer tries that length.
     */
    if (length < ((size_t)payload_length + 3u)) {
        return FRAME_ERR_TOO_SHORT;
    }
#else
    if (length < ((size_t)payload_length + (size_t)FRAME_OVERHEAD)) {
        return FRAME_ERR_TOO_SHORT;
    }
#endif

    const size_t   crc_offset = 2u + (size_t)payload_length;
    const uint16_t received   = (uint16_t)((uint16_t)data[crc_offset] |
                                           ((uint16_t)data[crc_offset + 1u] << 8));
    const uint16_t computed   = crc16_ccitt(data, crc_offset);

    if (received != computed) {
        return FRAME_ERR_BAD_CRC;
    }

    out->length = payload_length;
    (void)memset(out->payload, 0, sizeof(out->payload));
    (void)memcpy(out->payload, &data[2], (size_t)payload_length);
    out->sequence = frame_payload_u32(out, 0u);

    return FRAME_OK;
}
