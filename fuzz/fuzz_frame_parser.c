/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Fuzz target for frame_parse(), the only function in this codebase that
 * reads untrusted input. Reviews under the EU Cyber Resilience Act or
 * UNECE R155 usually start with interfaces like this one, and fuzzing
 * results are useful evidence for them.
 *
 *   ./build-fuzz/fuzz/fuzz_frame_parser fuzz/corpus -max_total_time=60
 */
#include <stddef.h>
#include <stdint.h>

#include "frame_parser.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    frame_t frame;

    if (frame_parse(data, size, &frame) == FRAME_OK) {
        /* Exercise the accessors on anything that decoded cleanly. */
        for (size_t offset = 0u; offset < (size_t)frame.length; offset++) {
            (void)frame_payload_u32(&frame, offset);
        }
    }

    return 0;
}
