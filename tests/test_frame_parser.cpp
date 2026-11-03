// SPDX-License-Identifier: Apache-2.0
#include <gtest/gtest.h>

#include <cstdint>
#include <vector>

#include "crc16.h"
#include "frame_parser.h"

namespace {

// Heap allocated so AddressSanitizer knows exactly where the buffer ends. An
// oversized stack array would hide a read past the end of the frame.
std::vector<uint8_t> MakeFrame(const std::vector<uint8_t>& payload) {
    std::vector<uint8_t> frame;
    frame.push_back(FRAME_SYNC);
    frame.push_back(static_cast<uint8_t>(payload.size()));
    frame.insert(frame.end(), payload.begin(), payload.end());

    const uint16_t crc = crc16_ccitt(frame.data(), frame.size());
    frame.push_back(static_cast<uint8_t>(crc & 0xFFu));
    frame.push_back(static_cast<uint8_t>((crc >> 8) & 0xFFu));
    return frame;
}

}  // namespace

TEST(FrameParser, RejectsNullArguments) {
    frame_t  out{};
    uint8_t  data[8] = {};
    EXPECT_EQ(frame_parse(nullptr, sizeof(data), &out), FRAME_ERR_ARG);
    EXPECT_EQ(frame_parse(data, sizeof(data), nullptr), FRAME_ERR_ARG);
}

TEST(FrameParser, RejectsRunts) {
    frame_t              out{};
    std::vector<uint8_t> data = {FRAME_SYNC, 0x00u, 0x00u};
    EXPECT_EQ(frame_parse(data.data(), data.size(), &out), FRAME_ERR_TOO_SHORT);
}

TEST(FrameParser, RejectsBadSync) {
    frame_t out{};
    auto    frame = MakeFrame({0x01u, 0x02u});
    frame[0]      = 0x00u;
    EXPECT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_ERR_BAD_SYNC);
}

TEST(FrameParser, RejectsOversizedLength) {
    frame_t              out{};
    std::vector<uint8_t> data = {FRAME_SYNC, FRAME_MAX_PAYLOAD + 1u, 0x00u, 0x00u, 0x00u};
    EXPECT_EQ(frame_parse(data.data(), data.size(), &out), FRAME_ERR_BAD_LENGTH);
}

TEST(FrameParser, RejectsCorruptedCrc) {
    frame_t out{};
    auto    frame = MakeFrame({0xDEu, 0xADu, 0xBEu, 0xEFu});
    frame.back() ^= 0xFFu;
    EXPECT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_ERR_BAD_CRC);
}

TEST(FrameParser, AcceptsEmptyPayload) {
    frame_t out{};
    auto    frame = MakeFrame({});
    ASSERT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_OK);
    EXPECT_EQ(out.length, 0u);
}

TEST(FrameParser, AcceptsMaximumPayload) {
    frame_t              out{};
    std::vector<uint8_t> payload(FRAME_MAX_PAYLOAD, 0x5Au);
    auto                 frame = MakeFrame(payload);
    ASSERT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_OK);
    EXPECT_EQ(out.length, FRAME_MAX_PAYLOAD);
}

TEST(FrameParser, DecodesPayloadBytes) {
    frame_t out{};
    auto    frame = MakeFrame({0x11u, 0x22u, 0x33u, 0x44u});
    ASSERT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_OK);
    ASSERT_EQ(out.length, 4u);
    EXPECT_EQ(out.payload[0], 0x11u);
    EXPECT_EQ(out.payload[3], 0x44u);
}

TEST(FrameParser, PayloadU32RejectsOutOfRange) {
    frame_t out{};
    auto    frame = MakeFrame({0x01u, 0x02u});
    ASSERT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_OK);
    EXPECT_EQ(frame_payload_u32(&out, 0u), 0u);
    EXPECT_EQ(frame_payload_u32(nullptr, 0u), 0u);
}

// This test exercises seeded defect 2. The correct and the broken code both
// produce the expected value below on a typical host, so the test passes
// either way. Only UBSan distinguishes them.
TEST(FrameParser, PayloadU32DecodesHighBitValues) {
    frame_t out{};
    auto    frame = MakeFrame({0xFFu, 0xEEu, 0xDDu, 0xCCu});
    ASSERT_EQ(frame_parse(frame.data(), frame.size(), &out), FRAME_OK);
    EXPECT_EQ(frame_payload_u32(&out, 0u), 0xFFEEDDCCu);
    EXPECT_EQ(out.sequence, 0xFFEEDDCCu);
}
