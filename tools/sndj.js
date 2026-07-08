// sndj.js — THE shared snesdj JS library (CLAUDE.md §17).
// One reference implementation, imported by every browser tool and
// self-tested under node (`node tools/sndj.js --selftest`, run by
// `make test`). Mirrors tools/sndj_brr.py and tools/sndj_rle.py exactly.
//
// Exports (browser: window.SNDJ / node: module.exports):
//   brrEncode(samples, loopBlock) / brrDecode(bytes)
//   poolParse(bytes) / poolBuild(entries)  -- SNDJPOOL images
//   rlePack(bytes) / rleUnpack(bytes, size) / crc16(bytes)
//   toImage(block) / fromImage(image)      -- SNDJ1 save image reorder
//   pitchForNote(note)                     -- the single tuning source
//   findMarker(rom, marker)

'use strict';

// ---------------------------------------------------------------- BRR codec
function clamp16(v) {
  v = Math.max(-0x8000, Math.min(0x7FFF, v));
  if (v > 0x3FFF) v -= 0x8000;
  else if (v < -0x4000) v += 0x8000;
  return v;
}

function filterPredict(f, p1, p2) {
  if (f === 0) return 0;
  if (f === 1) return p1 + (-p1 >> 4);
  if (f === 2) return (p1 << 1) + ((-((p1 << 1) + p1)) >> 5) - p2 + (p2 >> 4);
  return (p1 << 1) + ((-(p1 + (p1 << 2) + (p1 << 3))) >> 6) - p2 +
    (((p2 << 1) + p2) >> 4);
}

function brrEncodeBlock(samples, p1, p2, forceF0) {
  let best = null;
  const filters = forceF0 ? [0] : [0, 1, 2, 3];
  for (const filt of filters) {
    for (let rng = 0; rng <= 12; rng++) {
      const nibs = [];
      let tp1 = p1, tp2 = p2, err = 0;
      for (const s of samples) {
        const target = Math.trunc(s / 2);
        const pred = filterPredict(filt, tp1, tp2);
        const resid = target - pred;
        const base = rng ? (resid * 2) >> rng : resid * 2;
        let cb = null;
        for (let nib of [base, base + 1]) {
          nib = Math.max(-8, Math.min(7, nib));
          const dec = clamp16(((nib << rng) >> 1) + pred);
          const e = (dec - target) ** 2;
          if (cb === null || e < cb[0]) cb = [e, nib, dec];
        }
        err += cb[0];
        tp2 = tp1;
        tp1 = cb[2];
        nibs.push(cb[1] & 0x0F);
      }
      if (best === null || err < best[3]) {
        const block = new Uint8Array(9);
        block[0] = (rng << 4) | (filt << 2);
        for (let i = 0; i < 8; i++) {
          block[1 + i] = (nibs[i * 2] << 4) | nibs[i * 2 + 1];
        }
        best = [block, tp1, tp2, err];
      }
    }
  }
  return best;
}

function brrEncode(samples, loopBlock) {
  if (samples.length % 16 !== 0) throw new Error('length % 16 != 0');
  const nblocks = samples.length / 16;
  const out = new Uint8Array(nblocks * 9);
  let p1 = 0, p2 = 0;
  for (let b = 0; b < nblocks; b++) {
    const forceF0 = b === 0 || (loopBlock !== null && b === loopBlock);
    const [block, np1, np2] =
      brrEncodeBlock(samples.slice(b * 16, b * 16 + 16), p1, p2, forceF0);
    p1 = np1;
    p2 = np2;
    let hdr = block[0];
    if (b === nblocks - 1) {
      hdr |= 1;
      if (loopBlock !== null) hdr |= 2;
    }
    out[b * 9] = hdr;
    out.set(block.subarray(1), b * 9 + 1);
  }
  return out;
}

function brrDecode(bytes) {
  const out = [];
  let p1 = 0, p2 = 0;
  for (let off = 0; off + 9 <= bytes.length; off += 9) {
    const hdr = bytes[off];
    const rng = hdr >> 4, filt = (hdr >> 2) & 3;
    for (let i = 0; i < 8; i++) {
      const byte = bytes[off + 1 + i];
      for (let nib of [byte >> 4, byte & 0x0F]) {
        if (nib >= 8) nib -= 16;
        let s = rng <= 12 ? (nib << rng) >> 1 : 0;
        s += filterPredict(filt, p1, p2);
        s = clamp16(s);
        p2 = p1;
        p1 = s;
        out.push(s * 2);
      }
    }
    if (hdr & 1) break;
  }
  return out;
}

// ---------------------------------------------------------------- pool image
// v2: offsets/sizes in 9-byte BRR blocks; sample data never crosses a
// 32 KB ROM bank boundary (the image starts 6 bytes into its first bank).
const POOL_BANK0_SPAN = 0x7FFA;
const POOL_BANK_SPAN = 0x8000;
const POOL_MAX_ENTRIES = 56;

function poolBankPad(offset, size) {
  const bankOf = o => o < POOL_BANK0_SPAN ? 0
    : 1 + Math.floor((o - POOL_BANK0_SPAN) / POOL_BANK_SPAN);
  const bankEnd = o => {
    const b = bankOf(o);
    return b === 0 ? POOL_BANK0_SPAN : POOL_BANK0_SPAN + b * POOL_BANK_SPAN;
  };
  if (bankOf(offset) === bankOf(offset + size - 1)) return 0;
  return bankEnd(offset) - offset;
}

function poolParse(bytes) {
  const magic = String.fromCharCode(...bytes.slice(0, 8));
  if (magic !== 'SNDJPOOL') throw new Error('bad pool magic');
  if (bytes[8] !== 2) throw new Error('pool format v' + bytes[8]);
  const count = bytes[9];
  const entries = [];
  for (let i = 0; i < count; i++) {
    const e = 16 + i * 16;
    const name = String.fromCharCode(...bytes.slice(e, e + 8)).trimEnd();
    const off = (bytes[e + 8] | (bytes[e + 9] << 8)) * 9;
    const size = (bytes[e + 10] | (bytes[e + 11] << 8)) * 9;
    const loop = bytes[e + 12] | (bytes[e + 13] << 8);
    entries.push({
      name,
      loopBlock: loop === 0xFFFF ? null : loop,
      brr: bytes.slice(off, off + size),
    });
  }
  return entries;
}

function poolBuild(entries) {
  if (entries.length > POOL_MAX_ENTRIES) {
    throw new Error('too many pool entries (max ' + POOL_MAX_ENTRIES + ')');
  }
  const table = [];
  const chunks = [];
  const base = 16 + entries.length * 16;
  const dataStart = Math.ceil(base / 9) * 9;
  let off = dataStart;
  for (const e of entries) {
    let pad = poolBankPad(off, e.brr.length);
    if (pad) {
      pad = Math.ceil(pad / 9) * 9;
      chunks.push(new Uint8Array(pad).fill(0xFF));
      off += pad;
    }
    const name = (e.name || '').padEnd(8).slice(0, 8);
    const loop = e.loopBlock === null || e.loopBlock === undefined
      ? 0xFFFF : e.loopBlock;
    const offB = off / 9, sizeB = e.brr.length / 9;
    table.push(...[...name].map(c => c.charCodeAt(0)),
      offB & 0xFF, offB >> 8, sizeB & 0xFF, sizeB >> 8,
      loop & 0xFF, loop >> 8, 0, 0);
    chunks.push(e.brr);
    off += e.brr.length;
  }
  const head = [...'SNDJPOOL'].map(c => c.charCodeAt(0));
  head.push(2, entries.length, 0, 0, 0, 0, 0, 0);
  const out = new Uint8Array(off);
  out.fill(0xFF, base, dataStart);
  out.set(head, 0);
  out.set(table, 16);
  let p = dataStart;
  for (const b of chunks) {
    out.set(b, p);
    p += b.length;
  }
  return out;
}

// ------------------------------------------------------------------ RLE/CRC
function rlePack(data) {
  const out = [];
  let i = 0, litStart = null;
  const flush = (end) => {
    let s = litStart;
    while (s !== null && s < end) {
      const chunk = Math.min(128, end - s);
      out.push(chunk - 1);
      for (let k = 0; k < chunk; k++) out.push(data[s + k]);
      s += chunk;
    }
    litStart = null;
  };
  while (i < data.length) {
    let run = 1;
    while (i + run < data.length && data[i + run] === data[i] && run < 130) run++;
    if (run >= 3) {
      flush(i);
      out.push(0x80 + run - 3, data[i]);
      i += run;
    } else {
      if (litStart === null) litStart = i;
      i += run;
    }
  }
  flush(i);
  return new Uint8Array(out);
}

function rleUnpack(data, size) {
  const out = new Uint8Array(size);
  let i = 0, o = 0;
  while (o < size) {
    const c = data[i++];
    if (c < 0x80) {
      for (let k = 0; k <= c; k++) out[o++] = data[i++];
    } else {
      const b = data[i++];
      for (let k = 0; k < c - 0x80 + 3; k++) out[o++] = b;
    }
  }
  return out;
}

function crc16(data) {
  let crc = 0xFFFF;
  for (const b of data) {
    crc ^= b << 8;
    for (let k = 0; k < 8; k++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

const BLOCK_SZ = 0x5300;     // SAVEFORMAT.md v2
const PHRASES_OFF = 0x2300;  // interleaved phrase pool at the block end
const PHRASES_LEN = 0x3000;
const CHAINS_OFF = 0x1700;
const CHAINS_LEN = 0x0C00;

function toImage(block) {
  const img = new Uint8Array(BLOCK_SZ);
  let p = 0;
  for (let col = 0; col < 4; col++) {
    for (let k = PHRASES_OFF + col; k < PHRASES_OFF + PHRASES_LEN; k += 4) {
      img[p++] = block[k];
    }
  }
  for (let col = 0; col < 2; col++) {
    for (let k = CHAINS_OFF + col; k < CHAINS_OFF + CHAINS_LEN; k += 2) {
      img[p++] = block[k];
    }
  }
  img.set(block.slice(0, CHAINS_OFF), p);
  return img;
}

function fromImage(img) {
  const block = new Uint8Array(BLOCK_SZ);
  let p = 0;
  for (let col = 0; col < 4; col++) {
    for (let k = PHRASES_OFF + col; k < PHRASES_OFF + PHRASES_LEN; k += 4) {
      block[k] = img[p++];
    }
  }
  for (let col = 0; col < 2; col++) {
    for (let k = CHAINS_OFF + col; k < CHAINS_OFF + CHAINS_LEN; k += 2) {
      block[k] = img[p++];
    }
  }
  block.set(img.slice(p, BLOCK_SZ), 0);
  return block;
}

// ---------------------------------------------------------------- tuning/rom
function pitchForNote(note) {  // note 0-95 (C-0..B-7)
  const base = Math.round(0x4000 * 2 ** ((note % 12) / 12));
  return base >> (7 - Math.floor(note / 12));
}

function findMarker(rom, marker) {
  const m = [...marker].map(c => c.charCodeAt(0));
  outer:
  for (let i = 0; i + m.length < rom.length; i++) {
    for (let k = 0; k < m.length; k++) {
      if (rom[i + k] !== m[k]) continue outer;
    }
    return i + m.length;
  }
  return -1;
}

function fixChecksum(rom) {
  rom[0x7FDC] = 0xFF; rom[0x7FDD] = 0xFF;
  rom[0x7FDE] = 0x00; rom[0x7FDF] = 0x00;
  let total = 0;
  for (const b of rom) total = (total + b) & 0xFFFF;
  rom[0x7FDE] = total & 0xFF;
  rom[0x7FDF] = total >> 8;
  rom[0x7FDC] = ~total & 0xFF;
  rom[0x7FDD] = (~total >> 8) & 0xFF;
  return rom;
}

// ------------------------------------------------------------------ selftest
function selftest() {
  const assert = (c, m) => { if (!c) throw new Error('selftest: ' + m); };
  // BRR round-trip on a pad-ish wave
  const src = [];
  for (let i = 0; i < 128; i++) {
    const t = 2 * Math.PI * i / 128;
    src.push(Math.round((Math.sin(t) + 0.35 * Math.sin(2 * t)
      + 0.18 * Math.sin(3 * t) + 0.08 * Math.sin(5 * t)) / 1.61 * 24000));
  }
  const brr = brrEncode(src, 0);
  assert(brr.length === 72, 'brr size');
  assert((brr[63] & 3) === 3, 'END+LOOP flags');
  const dec = brrDecode(brr);
  assert(dec.length === 128, 'decode length');
  let err = 0, sig = 0;
  for (let i = 0; i < 128; i++) {
    err += (dec[i] - src[i]) ** 2;
    sig += src[i] ** 2;
  }
  const snr = 10 * Math.log10(sig / err);
  assert(snr > 26, 'BRR SNR ' + snr.toFixed(1));
  // pool round-trip
  const pool = poolBuild([
    { name: 'PAD', loopBlock: 0, brr },
    { name: 'HIT', loopBlock: null, brr: brr.slice(0, 18) },
  ]);
  const back = poolParse(pool);
  assert(back.length === 2 && back[0].name === 'PAD', 'pool names');
  assert(back[0].brr.length === 72 && back[1].loopBlock === null, 'pool fields');
  // RLE + CRC + image
  const blk = new Uint8Array(BLOCK_SZ);
  for (let i = PHRASES_OFF + 1; i < PHRASES_OFF + PHRASES_LEN; i += 4) blk[i] = 0xFF;
  for (let i = CHAINS_OFF; i < CHAINS_OFF + CHAINS_LEN; i += 2) blk[i] = 0xFF;
  for (let i = 0; i < 0x0400; i++) blk[i] = 0xFF;
  blk[0x1000] = 0x42;
  const img = toImage(blk);
  const packed = rlePack(img);
  assert(packed.length < 768, 'empty-song pack size ' + packed.length);
  const un = fromImage(rleUnpack(packed, BLOCK_SZ));
  for (let i = 0; i < BLOCK_SZ; i++) assert(un[i] === blk[i], 'rle byte ' + i);
  assert(crc16([...'123456789'].map(c => c.charCodeAt(0))) === 0x29B1, 'crc');
  // tuning matches the ROM tables
  assert(pitchForNote(48) === 0x0800, 'C-4 pitch');
  assert(pitchForNote(52) === 0x0A14, 'E-4 pitch');
  assert(pitchForNote(60) === 0x1000, 'C-5 pitch');
  console.log('sndj.js selftest: OK (BRR SNR ' + snr.toFixed(1) + ' dB, ' +
    'empty song ' + packed.length + ' bytes)');
}

const SNDJ = {
  brrEncode, brrDecode, poolParse, poolBuild,
  rlePack, rleUnpack, crc16, toImage, fromImage,
  pitchForNote, findMarker, fixChecksum, selftest,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SNDJ;
  if (process.argv.includes('--selftest') || require.main === module) selftest();
} else if (typeof window !== 'undefined') {
  window.SNDJ = SNDJ;
}
