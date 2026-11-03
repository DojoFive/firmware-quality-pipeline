// SPDX-License-Identifier: Apache-2.0
#include <gtest/gtest.h>

#include "ringbuf.h"

namespace {

class RingbufTest : public ::testing::Test {
protected:
    void SetUp() override { ASSERT_TRUE(ringbuf_init(&rb, storage, sizeof(storage))); }

    uint8_t   storage[8] = {};
    ringbuf_t rb{};
};

}  // namespace

TEST_F(RingbufTest, RejectsBadArguments) {
    ringbuf_t other{};
    EXPECT_FALSE(ringbuf_init(nullptr, storage, sizeof(storage)));
    EXPECT_FALSE(ringbuf_init(&other, nullptr, sizeof(storage)));
    EXPECT_FALSE(ringbuf_init(&other, storage, 0u));
}

TEST_F(RingbufTest, PushPopRoundTrip) {
    uint8_t value = 0u;
    EXPECT_TRUE(ringbuf_push(&rb, 0x42u));
    EXPECT_EQ(ringbuf_count(&rb), 1u);
    EXPECT_TRUE(ringbuf_pop(&rb, &value));
    EXPECT_EQ(value, 0x42u);
    EXPECT_EQ(ringbuf_count(&rb), 0u);
}

TEST_F(RingbufTest, PopOnEmptyFails) {
    uint8_t value = 0u;
    EXPECT_FALSE(ringbuf_pop(&rb, &value));
}

TEST_F(RingbufTest, PushWhenFullFails) {
    for (uint8_t i = 0u; i < sizeof(storage); i++) {
        ASSERT_TRUE(ringbuf_push(&rb, i));
    }
    EXPECT_TRUE(ringbuf_is_full(&rb));
    EXPECT_FALSE(ringbuf_push(&rb, 0xFFu));
}

// This test catches seeded defect 4, which corrupts the read index only after
// the tail wraps. A test that never fills the buffer more than once passes
// against the broken code.
TEST_F(RingbufTest, SurvivesRepeatedWraparound) {
    uint8_t value = 0u;
    for (uint32_t cycle = 0u; cycle < 4u; cycle++) {
        for (uint8_t i = 0u; i < sizeof(storage); i++) {
            ASSERT_TRUE(ringbuf_push(&rb, static_cast<uint8_t>(cycle * 16u + i)));
        }
        for (uint8_t i = 0u; i < sizeof(storage); i++) {
            ASSERT_TRUE(ringbuf_pop(&rb, &value));
            EXPECT_EQ(value, static_cast<uint8_t>(cycle * 16u + i))
                << "wrong byte on cycle " << cycle << " index " << static_cast<int>(i);
        }
    }
}

TEST_F(RingbufTest, ResetClearsState) {
    ASSERT_TRUE(ringbuf_push(&rb, 1u));
    ringbuf_reset(&rb);
    EXPECT_EQ(ringbuf_count(&rb), 0u);
}
