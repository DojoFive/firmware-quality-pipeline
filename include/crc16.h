/* SPDX-License-Identifier: Apache-2.0 */
#ifndef CRC16_H
#define CRC16_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no final xor. */
uint16_t crc16_ccitt(const uint8_t *data, size_t length);

#ifdef __cplusplus
}
#endif

#endif /* CRC16_H */
