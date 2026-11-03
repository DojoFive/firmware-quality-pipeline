// SPDX-License-Identifier: Apache-2.0
#include <gtest/gtest.h>

#include "crc16.h"

TEST(Crc16, KnownAnswerCheckString) {
    const uint8_t input[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
    EXPECT_EQ(crc16_ccitt(input, sizeof(input)), 0x29B1u);
}

TEST(Crc16, EmptyInputReturnsSeed) {
    const uint8_t input[1] = {0};
    EXPECT_EQ(crc16_ccitt(input, 0u), 0xFFFFu);
}

TEST(Crc16, NullInputIsHandled) {
    EXPECT_EQ(crc16_ccitt(nullptr, 16u), 0xFFFFu);
}

TEST(Crc16, SingleBitChangeChangesResult) {
    const uint8_t a[] = {0x01, 0x02, 0x03, 0x04};
    const uint8_t b[] = {0x01, 0x02, 0x03, 0x05};
    EXPECT_NE(crc16_ccitt(a, sizeof(a)), crc16_ccitt(b, sizeof(b)));
}
