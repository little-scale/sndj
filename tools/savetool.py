#!/usr/bin/env python3
"""savetool.py — CLI mirror of savetool.html (SNDJ1 cart saves + .sndj files).

Usage:
  savetool.py list  save.srm
  savetool.py new   save.srm
  savetool.py extract save.srm SLOT out.sndj
  savetool.py insert  save.srm SLOT in.sndj [NAME]
  savetool.py erase   save.srm SLOT
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sndj_rle

SRM_SIZE = 0x8000
REGIONS = 5
REGION_SZ = 0x1880
SLOTS = 4
BLOCK_SZ = 0x5300


def srm_new():
    srm = bytearray(SRM_SIZE)
    srm[0:5] = b'SNDJ1'
    srm[5] = 1
    for s in range(SLOTS):
        srm[0x10 + s * 16] = 0xFF
    return srm


def slot_info(srm, s):
    e = 0x10 + s * 16
    if srm[e] != 0xA5:
        return None
    region = srm[e + 1]
    size, crc = struct.unpack('<HH', srm[e + 2:e + 6])
    name = srm[e + 6:e + 14].decode('latin1').rstrip()
    data = bytes(srm[0x100 + region * REGION_SZ:0x100 + region * REGION_SZ + size])
    ok = region < REGIONS and size <= REGION_SZ and sndj_rle.crc16(data) == crc
    return {'region': region, 'size': size, 'crc': crc, 'name': name,
            'data': data, 'ok': ok}


def free_region(srm):
    used = {srm[0x10 + s * 16 + 1] for s in range(SLOTS)
            if srm[0x10 + s * 16] == 0xA5}
    for r in range(REGIONS):
        if r not in used:
            return r
    raise SystemExit('no free region')


def sndj_build(name, packed):
    crc = sndj_rle.crc16(packed)
    return (b'SNDJ1' + bytes([1]) + name.ljust(8)[:8].encode('latin1')
            + struct.pack('<HH', len(packed), crc) + packed)


def sndj_parse(data):
    assert data[:5] == b'SNDJ1' and data[5] == 1, 'not a .sndj file'
    name = data[6:14].decode('latin1').rstrip()
    size, crc = struct.unpack('<HH', data[14:18])
    packed = data[18:18 + size]
    assert sndj_rle.crc16(packed) == crc, '.sndj CRC mismatch'
    return name, packed


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    cmd, path = sys.argv[1], sys.argv[2]
    if cmd == 'new':
        open(path, 'wb').write(srm_new())
        print(f'{path}: new SNDJ1 cart image')
        return
    srm = bytearray(open(path, 'rb').read()[:SRM_SIZE].ljust(SRM_SIZE, b'\0'))
    if cmd == 'list':
        ok = srm[:5] == b'SNDJ1'
        print(f'{path}: magic {"SNDJ1" if ok else "MISSING"}')
        for s in range(SLOTS):
            info = slot_info(srm, s)
            if info is None:
                print(f'  slot {s}: - empty -')
            else:
                state = 'ok' if info['ok'] else 'BAD CRC'
                print(f"  slot {s}: {info['name']:8s} {info['size']:5d} B "
                      f"region {info['region']} crc ${info['crc']:04X} {state}")
        return
    slot = int(sys.argv[3])
    if cmd == 'extract':
        info = slot_info(srm, slot)
        if info is None:
            raise SystemExit(f'slot {slot} is empty')
        open(sys.argv[4], 'wb').write(sndj_build(info['name'], info['data']))
        print(f"slot {slot} ({info['name']}) -> {sys.argv[4]}")
    elif cmd == 'insert':
        name, packed = sndj_parse(open(sys.argv[4], 'rb').read())
        if len(sys.argv) > 5:
            name = sys.argv[5]
        if len(packed) > REGION_SZ:
            raise SystemExit('song too big for a slot')
        e = 0x10 + slot * 16
        srm[e] = 0
        region = free_region(srm)
        srm[0x100 + region * REGION_SZ:0x100 + region * REGION_SZ + len(packed)] = packed
        srm[e + 1] = region
        srm[e + 2:e + 6] = struct.pack('<HH', len(packed), sndj_rle.crc16(packed))
        srm[e + 6:e + 14] = name.ljust(8)[:8].encode('latin1')
        srm[e] = 0xA5
        open(path, 'wb').write(srm)
        print(f'{sys.argv[4]} -> slot {slot} (region {region})')
    elif cmd == 'erase':
        srm[0x10 + slot * 16] = 0xFF
        open(path, 'wb').write(srm)
        print(f'slot {slot} erased')
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
