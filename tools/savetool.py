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
SLOTS = 16
HEAP = 0x110
HEAP_SZ = SRM_SIZE - HEAP
BLOCK_SZ = 0x5300


def srm_new():
    srm = bytearray(SRM_SIZE)
    srm[0:5] = b'SNDJ1'
    srm[5] = 2
    for s in range(SLOTS):
        srm[0x10 + s * 16] = 0xFF
    return srm


def slot_info(srm, s):
    e = 0x10 + s * 16
    if srm[e] != 0xA5:
        return None
    off, size, crc = struct.unpack('<HHH', srm[e + 1:e + 7])
    name = srm[e + 8:e + 16].decode('latin1').rstrip()
    data = bytes(srm[HEAP + off:HEAP + off + size])
    ok = size <= HEAP_SZ and sndj_rle.crc16(data) == crc
    return {'off': off, 'size': size, 'crc': crc, 'name': name,
            'data': data, 'ok': ok}


def songs_of(srm):
    out = []
    for s in range(SLOTS):
        info = slot_info(srm, s)
        if info:
            out.append(info)
    return out


def layout(songs):
    srm = srm_new()
    off = 0
    for s, song in enumerate(songs):
        if off + len(song['data']) > HEAP_SZ:
            raise SystemExit('songs exceed the 32 KB save')
        e = 0x10 + s * 16
        srm[e + 1:e + 7] = struct.pack('<HHH', off, len(song['data']),
                                       sndj_rle.crc16(song['data']))
        srm[e + 8:e + 16] = song['name'].ljust(8)[:8].encode('latin1')
        srm[HEAP + off:HEAP + off + len(song['data'])] = song['data']
        srm[e] = 0xA5
        off += len(song['data'])
    return srm


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
        ok = srm[:5] == b'SNDJ1' and srm[5] == 2
        print(f'{path}: magic {"SNDJ1 v2" if ok else "MISSING/WRONG VERSION"}')
        free = HEAP_SZ
        for s in range(SLOTS):
            info = slot_info(srm, s)
            if info is None:
                continue
            free -= info['size']
            state = 'ok' if info['ok'] else 'BAD CRC'
            print(f"  {s:2d}: {info['name']:8s} {info['size']:5d} B "
                  f"@{info['off']:04X} crc ${info['crc']:04X} {state}")
        print(f'  free: {free} bytes')
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
        songs = songs_of(srm)
        entry = {'name': name, 'data': packed}
        if slot < len(songs):
            songs[slot] = entry
        else:
            songs.append(entry)
        open(path, 'wb').write(layout(songs))
        print(f'{sys.argv[4]} -> slot {min(slot, len(songs) - 1)}')
    elif cmd == 'erase':
        songs = songs_of(srm)
        if slot < len(songs):
            del songs[slot]
        open(path, 'wb').write(layout(songs))
        print(f'slot {slot} erased (list compacted)')
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
