#!/usr/bin/env python3
"""fixsum.py — recompute the SNES internal header checksum of a LoROM image.

The header is hand-rolled in src/header.asm (deterministic, no assembler
directive magic); this fixes up $7FDC (complement) / $7FDE (checksum) after
linking. Power-of-two ROM sizes only, which is all we ever emit.
"""
import sys


def main(path):
    data = bytearray(open(path, 'rb').read())
    assert len(data) & (len(data) - 1) == 0, "ROM size must be a power of two"
    # Neutralise the checksum fields, then sum. The four bytes are counted
    # as $FF $FF $00 $00 by convention.
    data[0x7FDC:0x7FE0] = b'\xFF\xFF\x00\x00'
    total = sum(data) & 0xFFFF
    data[0x7FDE] = total & 0xFF
    data[0x7FDF] = total >> 8
    data[0x7FDC] = ~total & 0xFF
    data[0x7FDD] = (~total >> 8) & 0xFF
    open(path, 'wb').write(data)
    print(f"fixsum: {path} checksum ${total:04X}")


if __name__ == '__main__':
    main(sys.argv[1])
