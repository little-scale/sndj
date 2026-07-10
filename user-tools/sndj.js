// sndj.js — THE shared sndj JS library (CLAUDE.md §17).
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
        const target = Math.floor(s / 2);  // python // floors negatives
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
    const s8 = v => (v > 127 ? v - 256 : v);
    entries.push({
      name,
      loopBlock: loop === 0xFFFF ? null : loop,
      tuneSemis: s8(bytes[e + 14]),
      tuneFine: s8(bytes[e + 15]),
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
      loop & 0xFF, loop >> 8,
      (e.tuneSemis || 0) & 0xFF, (e.tuneFine || 0) & 0xFF);
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
// ------------------------------------------------------------------ SF2
// Mirror of tools/sndj_pool.py's soundfont pipeline, so the browser
// patcher imports .sf2 presets exactly like the factory build does.

function sf2Parse(bytes) {
  const u16 = o => bytes[o] | (bytes[o + 1] << 8);
  const u32 = o => (bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16) |
    (bytes[o + 3] << 24)) >>> 0;
  const chunks = {};
  const walk = (pos, end) => {
    while (pos < end - 8) {
      const cid = String.fromCharCode(...bytes.slice(pos, pos + 4));
      const size = u32(pos + 4);
      const body = pos + 8;
      if (cid === 'LIST') walk(body + 4, body + size);
      else chunks[cid] = { off: body, size };
      pos = body + size + (size & 1);
    }
  };
  walk(12, bytes.length);
  if (!chunks.smpl || !chunks.shdr) throw new Error('not an SF2 (no smpl/shdr)');
  const recs = (name, sz) => {
    if (!chunks[name]) return [];
    const out = [];
    for (let i = 0; i < Math.floor(chunks[name].size / sz); i++) {
      out.push(chunks[name].off + i * sz);
    }
    return out;
  };
  const str = (o, n) => {
    let s = '';
    for (let i = 0; i < n; i++) {
      if (bytes[o + i] === 0) break;
      s += String.fromCharCode(bytes[o + i]);
    }
    return s;
  };
  // preset ownership: phdr -> pbag -> pgen(41) -> inst -> ibag -> igen(53)
  const phdr = recs('phdr', 38), pbag = recs('pbag', 4), pgen = recs('pgen', 4);
  const inst = recs('inst', 22), ibag = recs('ibag', 4), igen = recs('igen', 4);
  const instSamples = [];
  for (let i = 0; i < inst.length - 1; i++) {
    const b0 = u16(inst[i] + 20), b1 = u16(inst[i + 1] + 20);
    const sids = new Set();
    for (let bg = b0; bg < b1; bg++) {
      const g0 = u16(ibag[bg]), g1 = u16(ibag[bg + 1]);
      for (let g = g0; g < g1; g++) {
        if (u16(igen[g]) === 53) sids.add(u16(igen[g] + 2));
      }
    }
    instSamples.push(sids);
  }
  const presetOf = {};
  for (let p = 0; p < phdr.length - 1; p++) {
    const pname = str(phdr[p], 20);
    const b0 = u16(phdr[p] + 24), b1 = u16(phdr[p + 1] + 24);
    for (let bg = b0; bg < b1; bg++) {
      const g0 = u16(pbag[bg]), g1 = u16(pbag[bg + 1]);
      for (let g = g0; g < g1; g++) {
        if (u16(pgen[g]) === 41) {
          const sids = instSamples[u16(pgen[g] + 2)];
          if (sids) for (const sid of sids) {
            if (!(sid in presetOf)) presetOf[sid] = pname;
          }
        }
      }
    }
  }
  const smpl = chunks.smpl.off;
  const out = [];
  const n = Math.floor(chunks.shdr.size / 46) - 1;
  for (let i = 0; i < n; i++) {
    const r = chunks.shdr.off + i * 46;
    const start = u32(r + 20), end = u32(r + 24);
    const ls = u32(r + 28), le = u32(r + 32);
    const rate = u32(r + 36);
    const root = bytes[r + 40];
    const corr = bytes[r + 41] > 127 ? bytes[r + 41] - 256 : bytes[r + 41];
    const pcm = new Int16Array(end - start);
    for (let k = 0; k < pcm.length; k++) {
      const o = smpl + (start + k) * 2;
      const v = bytes[o] | (bytes[o + 1] << 8);
      pcm[k] = v > 32767 ? v - 65536 : v;
    }
    out.push({
      name: str(r, 20), pcm, rate, root, corr,
      loop: (le > ls && ls >= start) ? [ls - start, le - start] : null,
      preset: presetOf[i] || null,
    });
  }
  return out;
}

// linear resample, bit-matching tools/sndj_pool.py resample()
// (int() truncates toward zero; round() is round-half-to-even)
function pyRound(x) {
  const f = Math.floor(x);
  const d = x - f;
  if (d < 0.5) return f;
  if (d > 0.5) return f + 1;
  return f % 2 === 0 ? f : f + 1;
}

function sf2Resample(samples, srcRate, dstRate) {
  if (srcRate === dstRate) return Array.from(samples);
  const ratio = srcRate / dstRate;
  const n = Math.trunc(samples.length / ratio);
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const p = i * ratio;
    const i0 = Math.trunc(p);
    const fr = p - i0;
    const a = samples[i0];
    const b = i0 + 1 < samples.length ? samples[i0 + 1] : a;
    out[i] = Math.trunc(a + (b - a) * fr);
  }
  return out;
}

// looped melodic prep: exact-loop resample with the root key baked in.
// Returns { pcm, loopBlock, tuneSemis, tuneFine } (python parity).
function sf2Melodic(s, trim) {
  trim = trim || 0;
  if (!s.loop) throw new Error(s.name + ' has no loop');
  let rootEff = (s.root || 60) - (s.corr || 0) / 100;
  if (!(rootEff >= 24 && rootEff <= 108)) rootEff = 60;
  const shift = 61 - rootEff + trim;
  const scale = Math.pow(2, -shift / 12);
  const ideal = scale * 32000 / s.rate;
  const [ls, le] = s.loop;
  const loopLen = le - ls;
  const target = Math.max(16, pyRound(loopLen * ideal / 16) * 16);
  const factor = target / loopLen;
  let pcm = sf2Resample(s.pcm, s.rate, s.rate * factor);
  let lsOut = pyRound(ls * factor);
  const cut = lsOut % 16;
  pcm = pcm.slice(cut);
  lsOut -= cut;
  const end = lsOut + target;
  while (pcm.length < end) pcm.push(pcm[pcm.length - target]);
  pcm = pcm.slice(0, end);
  const cents = 1200 * Math.log2(factor / ideal);
  const semis = pyRound(cents / 100);
  const fine = Math.max(-128, Math.min(127, pyRound((cents - semis * 100) * 2.56)));
  return { pcm, loopBlock: lsOut / 16, tuneSemis: semis, tuneFine: fine };
}

// one-shot prep at 8 kHz (kit slots tune -24), python parity
function sf2Oneshot(s, capMs) {
  let src = Array.from(s.pcm);
  let end = src.length;
  while (end > 16 && Math.abs(src[end - 1]) < 300) end--;
  src = src.slice(0, end);
  let pcm = sf2Resample(src, s.rate, 8000);
  pcm = pcm.slice(0, Math.trunc(8 * (capMs || 160)));
  const fadeN = Math.min(256, pcm.length);
  for (let i = 0; i < fadeN; i++) {
    const k = pcm.length - fadeN + i;
    pcm[k] = Math.floor(pcm[k] * (fadeN - i) / fadeN);
  }
  pcm = pcm.slice(0, Math.trunc(pcm.length / 16) * 16);
  if (pcm.length < 16) pcm = new Array(16).fill(0);
  return { pcm, loopBlock: null, tuneSemis: 0, tuneFine: 0 };
}

// ------------------------------------------------------------- WAV import
// RIFF scan for the bits decodeAudioData throws away: the sample rate
// and the sampler chunk's loop + root key. A WAV with a smpl loop can
// ride the exact same melodic pipeline as an sf2 preset.
function wavInfo(bytes) {
  const u32 = o => (bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16) |
    (bytes[o + 3] << 24)) >>> 0;
  const id = o => String.fromCharCode(...bytes.slice(o, o + 4));
  if (id(0) !== 'RIFF' || id(8) !== 'WAVE') return null;
  const info = { rate: 0, root: 60, loop: null };
  let pos = 12;
  while (pos + 8 <= bytes.length) {
    const cid = id(pos), size = u32(pos + 4), body = pos + 8;
    if (cid === 'fmt ') {
      info.rate = u32(body + 4);
    } else if (cid === 'smpl') {
      const root = u32(body + 12);
      if (root > 0 && root < 128) info.root = root;
      const nloops = u32(body + 28);
      if (nloops > 0) {
        const ls = u32(body + 44), le = u32(body + 48);
        if (le > ls) info.loop = [ls, le + 1];  // smpl end is inclusive
      }
    }
    pos = body + size + (size & 1);
  }
  return info.rate ? info : null;
}

// ------------------------------------------------------------ ARAM budget
// Mirror of src/pool.asm's residency math: samples upload from $1209
// (after the 9-byte silent stub at ARAM_SAMPLES $1200) and must end on a
// page BELOW the echo floor (ESA page = $100 - 8*EDL; EDL 0 still
// reserves the top page). Anything past the floor is mapped to the
// silent stub on the console — it simply doesn't sound.
function aramBudget(entries, resident) {
  const base = 0x1209;
  const inSet = i => !resident || resident.has(i);
  const sampleBytes = entries.reduce((a, e, i) =>
    a + (inSet(i) ? e.brr.length : 0), 0);
  const end = base + sampleBytes;
  const endPage = end >> 8;
  let maxEdl = -1;
  for (let edl = 15; edl >= 0; edl--) {
    const ceilPage = edl === 0 ? 0xFF : 0x100 - 8 * edl;
    if (endPage < ceilPage) { maxEdl = edl; break; }
  }
  return {
    sampleBytes, end,
    capacity: 0xFF00 - base,            // usable sample bytes at EDL 0
    maxEdl,                             // -1: samples overflow ARAM
    maxMs: maxEdl > 0 ? maxEdl * 16 : 0,
    overBy: Math.max(0, end - 0xFF00),
  };
}

// ------------------------------------------------------------- SRAM (.srm)
// SNDJ1 v2: 16-entry directory at $0010 (status, offset16, size16,
// crc16, rsvd, name8) over one packed heap at $0110. Offline tools can
// simply re-layout the heap in entry order on every write.
const SRM_SIZE = 0x8000;
const SRM_SLOTS = 16;
const SRM_DIR = 0x10;
const SRM_HEAP = 0x110;
const SRM_HEAP_SZ = SRM_SIZE - SRM_HEAP;

function srmNew() {
  const srm = new Uint8Array(SRM_SIZE);
  srm.set([...'SNDJ1'].map(c => c.charCodeAt(0)), 0);
  srm[5] = 2;
  for (let s = 0; s < SRM_SLOTS; s++) srm[SRM_DIR + s * 16] = 0xFF;
  return srm;
}

function srmParse(srm) {
  const magic = String.fromCharCode(...srm.slice(0, 5));
  const valid = magic === 'SNDJ1' && srm[5] === 2;
  const slots = [];
  let free = SRM_HEAP_SZ;
  for (let s = 0; s < SRM_SLOTS; s++) {
    const e = SRM_DIR + s * 16;
    if (srm[e] !== 0xA5) {
      slots.push({ index: s, empty: true });
      continue;
    }
    const off = srm[e + 1] | (srm[e + 2] << 8);
    const size = srm[e + 3] | (srm[e + 4] << 8);
    const crc = srm[e + 5] | (srm[e + 6] << 8);
    const name = String.fromCharCode(...srm.slice(e + 8, e + 16)).trimEnd();
    const data = srm.slice(SRM_HEAP + off, SRM_HEAP + off + size);
    free -= size;
    slots.push({
      index: s, empty: false, off, size, crc, name,
      ok: size <= SRM_HEAP_SZ && crc16(data) === crc,
      packed: data,
    });
  }
  return { valid, slots, free };
}

// rebuild the image from a song list (packed heap in entry order)
function srmLayout(songs) {
  const srm = srmNew();
  let off = 0;
  songs.forEach((song, s) => {
    if (off + song.packed.length > SRM_HEAP_SZ) {
      throw new Error('songs exceed the 32 KB save');
    }
    const e = SRM_DIR + s * 16;
    srm[e + 1] = off & 0xFF;
    srm[e + 2] = off >> 8;
    srm[e + 3] = song.packed.length & 0xFF;
    srm[e + 4] = song.packed.length >> 8;
    const crc = crc16(song.packed);
    srm[e + 5] = crc & 0xFF;
    srm[e + 6] = crc >> 8;
    srm.set([...(song.name || '').padEnd(8).slice(0, 8)]
      .map(c => c.charCodeAt(0)), e + 8);
    srm.set(song.packed, SRM_HEAP + off);
    srm[e] = 0xA5;
    off += song.packed.length;
  });
  return srm;
}

function srmSongs(srm) {
  return srmParse(srm).slots.filter(s => !s.empty)
    .map(s => ({ name: s.name, packed: s.packed }));
}

function srmInsert(srm, slotIdx, sndjBytes) {
  const { name, packed } = sndjFileParse(sndjBytes);
  const songs = srmSongs(srm);
  if (slotIdx > songs.length || slotIdx >= SRM_SLOTS) {
    throw new Error('the packed list has no slot ' + slotIdx);
  }
  songs[slotIdx] = { name, packed };
  return srmLayout(songs);
}

function srmErase(srm, slotIdx) {
  const songs = srmSongs(srm);
  songs.splice(slotIdx, 1);
  return srmLayout(songs);
}

function srmExtract(srm, slotIdx) {
  const { slots } = srmParse(srm);
  const s = slots[slotIdx];
  if (!s || s.empty) throw new Error('slot ' + slotIdx + ' is empty');
  return sndjFileBuild(s.name, s.packed);
}

function srmFreeRegion() { return 0; }  // v1 relic kept for API shape

// .sndj song file: "SNDJ1" ver name[8] packedSize crc16 packedBytes
function sndjFileBuild(name, packed) {
  const out = new Uint8Array(18 + packed.length);
  out.set([...'SNDJ1'].map(c => c.charCodeAt(0)), 0);
  out[5] = 1;
  out.set([...(name || '').padEnd(8).slice(0, 8)].map(c => c.charCodeAt(0)), 6);
  out[14] = packed.length & 0xFF;
  out[15] = packed.length >> 8;
  const crc = crc16(packed);
  out[16] = crc & 0xFF;
  out[17] = crc >> 8;
  out.set(packed, 18);
  return out;
}

function sndjFileParse(bytes) {
  if (String.fromCharCode(...bytes.slice(0, 5)) !== 'SNDJ1' || bytes[5] !== 1) {
    throw new Error('not a .sndj file');
  }
  const name = String.fromCharCode(...bytes.slice(6, 14)).trimEnd();
  const size = bytes[14] | (bytes[15] << 8);
  const crc = bytes[16] | (bytes[17] << 8);
  const packed = bytes.slice(18, 18 + size);
  if (crc16(packed) !== crc) throw new Error('.sndj CRC mismatch');
  return { name, packed };
}

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

// --------------------------------------------------------------- S-DSP model
// A sample-accurate model of the S-DSP, ported from blargg's snes_spc
// (the reference emulation core). It is what lets every browser tool
// audition and render *actual console sound*: BRR decode through the
// 4-tap Gaussian interpolator, hardware ADSR/GAIN envelopes, the noise
// LFSR, pitch modulation, and the echo delay line with its 8-tap FIR
// and feedback path, including the chip's int16 truncation quirks.
//
//   const d = dspNew(aram);          // aram: Uint8Array(65536)
//   dspWrite(d, reg, val);           // any of the 128 registers
//   const {l, r} = dspRun(d, n);     // n stereo samples at 32000 Hz

const GAUSS = [
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
  1,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,
  2,2,3,3,3,3,3,4,4,4,4,4,5,5,5,5,
  6,6,6,6,7,7,7,8,8,8,9,9,9,10,10,10,
  11,11,11,12,12,13,13,14,14,15,15,15,16,16,17,17,
  18,19,19,20,20,21,21,22,23,23,24,24,25,26,27,27,
  28,29,29,30,31,32,32,33,34,35,36,36,37,38,39,40,
  41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,
  58,59,60,61,62,64,65,66,67,69,70,71,73,74,76,77,
  78,80,81,83,84,86,87,89,90,92,94,95,97,99,100,102,
  104,106,107,109,111,113,115,117,118,120,122,124,126,128,130,132,
  134,137,139,141,143,145,147,150,152,154,156,159,161,163,166,168,
  171,173,175,178,180,183,186,188,191,193,196,199,201,204,207,210,
  212,215,218,221,224,227,230,233,236,239,242,245,248,251,254,257,
  260,263,267,270,273,276,280,283,286,290,293,297,300,304,307,311,
  314,318,321,325,328,332,336,339,343,347,351,354,358,362,366,370,
  374,378,381,385,389,393,397,401,405,410,414,418,422,426,430,434,
  439,443,447,451,456,460,464,469,473,477,482,486,491,495,499,504,
  508,513,517,522,527,531,536,540,545,550,554,559,563,568,573,577,
  582,587,592,596,601,606,611,615,620,625,630,635,640,644,649,654,
  659,664,669,674,678,683,688,693,698,703,708,713,718,723,728,732,
  737,742,747,752,757,762,767,772,777,782,787,792,797,802,806,811,
  816,821,826,831,836,841,846,851,855,860,865,870,875,880,884,889,
  894,899,904,908,913,918,923,927,932,937,941,946,951,955,960,965,
  969,974,978,983,988,992,997,1001,1005,1010,1014,1019,1023,1027,1032,1036,
  1040,1045,1049,1053,1057,1061,1066,1070,1074,1078,1082,1086,1090,1094,1098,1102,
  1106,1109,1113,1117,1121,1125,1128,1132,1136,1139,1143,1146,1150,1153,1157,1160,
  1164,1167,1170,1174,1177,1180,1183,1186,1190,1193,1196,1199,1202,1205,1207,1210,
  1213,1216,1219,1221,1224,1227,1229,1232,1234,1237,1239,1241,1244,1246,1248,1251,
  1253,1255,1257,1259,1261,1263,1265,1267,1269,1270,1272,1274,1275,1277,1279,1280,
  1282,1283,1284,1286,1287,1288,1290,1291,1292,1293,1294,1295,1296,1297,1297,1298,
  1299,1300,1300,1301,1302,1302,1303,1303,1303,1304,1304,1304,1304,1304,1305,1305,
];

const ENV_RELEASE = 0, ENV_ATTACK = 1, ENV_DECAY = 2, ENV_SUSTAIN = 3;
const COUNTER_RATES = [
  0x7801, 2048, 1536, 1280, 1024, 768, 640, 512, 384, 320, 256, 192,
  160, 128, 96, 80, 64, 48, 40, 32, 24, 20, 16, 12, 10, 8, 6, 5, 4, 3, 2, 1,
];
const COUNTER_OFFSETS = [
  1, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536,
  0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 536, 0, 1040, 0, 0,
];

const i8 = v => (v << 24) >> 24;
const i16 = v => (v << 16) >> 16;
const clamp = v => (v > 32767 ? 32767 : v < -32768 ? -32768 : v);

function dspNew(aram) {
  const d = {
    aram,
    regs: new Uint8Array(128),
    voices: [],
    counter: 0,
    everyOther: 1,
    newKon: 0, kon: 0, tKoff: 0,
    noise: 0x4000,
    echoHist: [], echoHistPos: 0,
    echoOffset: 0, echoLength: 0,
    echoOutL: 0, echoOutR: 0,
  };
  for (let i = 0; i < 8; i++) d.echoHist.push([0, 0]);
  for (let v = 0; v < 8; v++) {
    d.voices.push({
      buf: new Int32Array(24),   // 12 decoded samples, double copy
      bufPos: 0, interpPos: 0,
      brrAddr: 0, brrOffset: 1,
      vbit: 1 << v,
      konDelay: 0,
      envMode: ENV_RELEASE, env: 0, hiddenEnv: 0,
      tOutput: 0,
    });
  }
  d.regs[0x6C] = 0xE0;           // FLG: reset, mute, echo write off
  return d;
}

function dspWrite(d, reg, val) {
  reg &= 0x7F; val &= 0xFF;
  d.regs[reg] = val;
  if (reg === 0x4C) d.newKon = val;
  else if (reg === 0x7C) d.regs[0x7C] = 0;      // any ENDX write clears it
}

function readCounter(d, rate) {
  return (d.counter + COUNTER_OFFSETS[rate]) % COUNTER_RATES[rate];
}

function runEnvelope(d, v, vx) {
  let env = v.env;
  if (v.envMode === ENV_RELEASE) {
    if ((env -= 8) < 0) env = 0;
    v.env = env;
    return;
  }
  const adsr0 = d.regs[vx + 5];
  let rate;
  let envData = d.regs[vx + 6];                  // adsr1
  if (adsr0 & 0x80) {                            // ADSR
    if (v.envMode >= ENV_DECAY) {
      env--;
      env -= env >> 8;
      rate = envData & 0x1F;                     // sustain rate
      if (v.envMode === ENV_DECAY) rate = ((adsr0 >> 3) & 0x0E) + 0x10;
    } else {                                     // attack
      rate = ((adsr0 & 0x0F) * 2) + 1;
      env += rate < 31 ? 0x20 : 0x400;
    }
  } else {                                       // GAIN
    envData = d.regs[vx + 7];
    const mode = envData >> 5;
    if (mode < 4) {                              // direct level
      env = envData * 0x10;
      rate = 31;
    } else {
      rate = envData & 0x1F;
      if (mode === 4) env -= 0x20;               // linear decrease
      else if (mode < 6) { env--; env -= env >> 8; }  // exp decrease
      else {                                     // linear / bent increase
        env += 0x20;
        if (mode > 6 && (v.hiddenEnv >>> 0) >= 0x600) env += 8 - 0x20;
      }
    }
  }
  if ((env >> 8) === (envData >> 5) && v.envMode === ENV_DECAY) {
    v.envMode = ENV_SUSTAIN;
  }
  v.hiddenEnv = env;
  if (env > 0x7FF || env < 0) {
    env = env < 0 ? 0 : 0x7FF;
    if (v.envMode === ENV_ATTACK) v.envMode = ENV_DECAY;
  }
  if (readCounter(d, rate) === 0) v.env = env;
}

function decodeBrr(d, v, header, brrByte) {
  let nybbles = (brrByte << 8) | d.aram[(v.brrAddr + v.brrOffset + 1) & 0xFFFF];
  let pos = v.bufPos;
  if ((v.bufPos += 4) >= 12) v.bufPos = 0;
  const shift = header >> 4;
  const filter = header & 0x0C;
  for (let end = pos + 4; pos < end; pos++, nybbles = (nybbles << 4) & 0xFFFF) {
    let s = ((nybbles << 16) >> 28);             // sign-extended top nibble
    if (shift <= 12) s = (s << shift) >> 1;
    else s &= ~0x7FF;
    const p1 = v.buf[pos + 11];
    const p2 = v.buf[pos + 10] >> 1;
    if (filter >= 8) {
      s += p1;
      s -= p2;
      if (filter === 8) { s += p2 >> 4; s += (p1 * -3) >> 6; }
      else { s += (p1 * -13) >> 7; s += (p2 * 3) >> 4; }
    } else if (filter) {
      s += p1 >> 1;
      s += (-p1) >> 5;
    }
    s = i16(clamp(s) * 2);
    v.buf[pos + 12] = v.buf[pos] = s;
  }
}

function dspRun(d, n) {
  const outL = new Int16Array(n);
  const outR = new Int16Array(n);
  const { aram, regs } = d;
  for (let i = 0; i < n; i++) {
    // global per-sample state (misc_27..30)
    d.everyOther ^= 1;
    if (d.everyOther) d.newKon &= ~d.kon;
    if (d.everyOther) {
      d.kon = d.newKon;
      d.tKoff = regs[0x5C];
    }
    if (--d.counter < 0) d.counter = 30719;
    if (readCounter(d, regs[0x6C] & 0x1F) === 0) {
      const feedback = (d.noise << 13) ^ (d.noise << 14);
      d.noise = (feedback & 0x4000) ^ (d.noise >> 1);
    }
    const tPmon = regs[0x2D] & 0xFE;
    const tNon = regs[0x3D];
    const tEon = regs[0x4D];
    const tDir = regs[0x5D];
    const flg = regs[0x6C];
    let mainL = 0, mainR = 0, echoL = 0, echoR = 0;
    let prevOut = 0;                             // PMON source (voice n-1)
    let endx = regs[0x7C];

    for (let vn = 0; vn < 8; vn++) {
      const v = d.voices[vn];
      const vx = vn << 4;
      // V1/V2: directory entry + pitch
      const dirAddr = ((tDir << 8) + regs[vx + 4] * 4) & 0xFFFF;
      const entry = v.konDelay ? dirAddr : (dirAddr + 2) & 0xFFFF;
      const brrNextAddr = aram[entry] | (aram[(entry + 1) & 0xFFFF] << 8);
      let pitch = regs[vx + 2] | ((regs[vx + 3] & 0x3F) << 8);
      // V3b: BRR header + byte
      const brrByte = aram[(v.brrAddr + v.brrOffset) & 0xFFFF];
      let header = aram[v.brrAddr];
      // V3c
      if (tPmon & v.vbit) pitch += ((prevOut >> 5) * pitch) >> 10;
      if (v.konDelay) {
        if (v.konDelay === 5) {
          v.brrAddr = brrNextAddr;
          v.brrOffset = 1;
          v.bufPos = 0;
          header = 0;                            // ignored on this sample
        }
        v.env = 0;
        v.hiddenEnv = 0;
        v.interpPos = 0;
        if (--v.konDelay & 3) v.interpPos = 0x4000;
        pitch = 0;
      }
      // gaussian interpolation
      const off = (v.interpPos >> 4) & 0xFF;
      const bi = (v.interpPos >> 12) + v.bufPos;
      let out = (GAUSS[255 - off] * v.buf[bi]) >> 11;
      out += (GAUSS[511 - off] * v.buf[bi + 1]) >> 11;
      out += (GAUSS[256 + off] * v.buf[bi + 2]) >> 11;
      out = i16(out);
      out += (GAUSS[off] * v.buf[bi + 3]) >> 11;
      out = clamp(out) & ~1;
      if (tNon & v.vbit) out = i16(d.noise * 2);
      v.tOutput = ((out * v.env) >> 11) & ~1;
      // silence on soft reset or an END-without-LOOP block
      if ((flg & 0x80) || (header & 3) === 1) {
        v.envMode = ENV_RELEASE;
        v.env = 0;
      }
      if (d.everyOther) {
        if (d.tKoff & v.vbit) v.envMode = ENV_RELEASE;
        if (d.kon & v.vbit) {
          v.konDelay = 5;
          v.envMode = ENV_ATTACK;
          endx &= ~v.vbit;                       // KON clears the ENDX bit
        }
      }
      if (!v.konDelay) runEnvelope(d, v, vx);
      // V4: decode + advance
      if (v.interpPos >= 0x4000) {
        decodeBrr(d, v, header, brrByte);
        if ((v.brrOffset += 2) >= 9) {
          v.brrAddr = (v.brrAddr + 9) & 0xFFFF;
          if (header & 1) {
            v.brrAddr = brrNextAddr;
            endx |= v.vbit;
          }
          v.brrOffset = 1;
        }
      }
      v.interpPos = (v.interpPos & 0x3FFF) + pitch;
      if (v.interpPos > 0x7FFF) v.interpPos = 0x7FFF;
      // V5: mix into main + echo sums
      const ampL = (v.tOutput * i8(regs[vx + 0])) >> 7;
      const ampR = (v.tOutput * i8(regs[vx + 1])) >> 7;
      mainL = clamp(mainL + ampL);
      mainR = clamp(mainR + ampR);
      if (tEon & v.vbit) {
        echoL = clamp(echoL + ampL);
        echoR = clamp(echoR + ampR);
      }
      // V6-V9 telemetry
      regs[vx + 8] = v.env >> 4;                 // ENVX
      regs[vx + 9] = (v.tOutput >> 8) & 0xFF;    // OUTX
      prevOut = v.tOutput;
    }
    regs[0x7C] = endx;

    // echo_22..25: read the delay line, run the FIR
    d.echoHistPos = (d.echoHistPos + 1) & 7;
    const tEsa = regs[0x6D];
    const echoPtr = ((tEsa << 8) + d.echoOffset) & 0xFFFF;
    const hist = d.echoHist;
    hist[d.echoHistPos][0] =
      i16(aram[echoPtr] | (aram[(echoPtr + 1) & 0xFFFF] << 8)) >> 1;
    hist[d.echoHistPos][1] =
      i16(aram[(echoPtr + 2) & 0xFFFF] | (aram[(echoPtr + 3) & 0xFFFF] << 8)) >> 1;
    let firL = 0, firR = 0;
    for (let t = 0; t < 7; t++) {
      const h = hist[(d.echoHistPos + t + 1) & 7];
      firL += (h[0] * i8(regs[0x0F + t * 0x10])) >> 6;
      firR += (h[1] * i8(regs[0x0F + t * 0x10])) >> 6;
    }
    firL = i16(firL);
    firR = i16(firR);
    const h7 = hist[d.echoHistPos];              // newest = tap 7
    firL += i16((h7[0] * i8(regs[0x7F])) >> 6);
    firR += i16((h7[1] * i8(regs[0x7F])) >> 6);
    const echoInL = clamp(firL) & ~1;
    const echoInR = clamp(firR) & ~1;
    // echo_26/27: final outputs + feedback
    let l = clamp(i16((mainL * i8(regs[0x0C])) >> 7)
      + i16((echoInL * i8(regs[0x2C])) >> 7));
    let r = clamp(i16((mainR * i8(regs[0x1C])) >> 7)
      + i16((echoInR * i8(regs[0x3C])) >> 7));
    if (flg & 0x40) { l = 0; r = 0; }
    outL[i] = l;
    outR[i] = r;
    d.echoOutL = clamp(echoL + i16((echoInL * i8(regs[0x0D])) >> 7)) & ~1;
    d.echoOutR = clamp(echoR + i16((echoInR * i8(regs[0x0D])) >> 7)) & ~1;
    // echo_29/30: write back + advance
    if (!(regs[0x6C] & 0x20)) {
      aram[echoPtr] = d.echoOutL & 0xFF;
      aram[(echoPtr + 1) & 0xFFFF] = (d.echoOutL >> 8) & 0xFF;
      aram[(echoPtr + 2) & 0xFFFF] = d.echoOutR & 0xFF;
      aram[(echoPtr + 3) & 0xFFFF] = (d.echoOutR >> 8) & 0xFF;
    }
    d.echoOutL = 0;
    d.echoOutR = 0;
    if (d.echoOffset === 0) d.echoLength = (regs[0x7D] & 0x0F) * 0x800;
    d.echoOffset += 4;
    if (d.echoOffset >= d.echoLength) d.echoOffset = 0;
  }
  return { l: outL, r: outR };
}

// 16-bit stereo PCM WAV container
function wavBuild(l, r, rate) {
  const n = l.length;
  const out = new Uint8Array(44 + n * 4);
  const dv = new DataView(out.buffer);
  const tag = (o, s) => { for (let i = 0; i < s.length; i++) out[o + i] = s.charCodeAt(i); };
  tag(0, 'RIFF'); dv.setUint32(4, 36 + n * 4, true); tag(8, 'WAVE');
  tag(12, 'fmt '); dv.setUint32(16, 16, true);
  dv.setUint16(20, 1, true); dv.setUint16(22, 2, true);
  dv.setUint32(24, rate, true); dv.setUint32(28, rate * 4, true);
  dv.setUint16(32, 4, true); dv.setUint16(34, 16, true);
  tag(36, 'data'); dv.setUint32(40, n * 4, true);
  for (let i = 0; i < n; i++) {
    dv.setInt16(44 + i * 4, l[i], true);
    dv.setInt16(46 + i * 4, r[i], true);
  }
  return out;
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
    { name: 'PAD', loopBlock: 0, tuneSemis: -3, tuneFine: 64, brr },
    { name: 'HIT', loopBlock: null, brr: brr.slice(0, 18) },
  ]);
  const back = poolParse(pool);
  assert(back.length === 2 && back[0].name === 'PAD', 'pool names');
  assert(back[0].brr.length === 72 && back[1].loopBlock === null, 'pool fields');
  assert(back[0].tuneSemis === -3 && back[0].tuneFine === 64 &&
    back[1].tuneSemis === 0, 'pool tune fields');

  // srm + .sndj round trip
  const blk2 = new Uint8Array(BLOCK_SZ);
  blk2[0] = 7; blk2[0x2300] = 49;
  const packed2 = rlePack(toImage(blk2));
  let srm = srmNew();
  srm = srmInsert(srm, 0, sndjFileBuild('SELFTEST', packed2));
  srm = srmInsert(srm, 1, sndjFileBuild('SECOND', packed2));
  const parsed = srmParse(srm);
  assert(parsed.valid && parsed.slots[0].ok && parsed.slots[1].ok &&
    parsed.slots[1].name === 'SECOND' &&
    parsed.slots[1].off === parsed.slots[0].size, 'srm v2 packed layout');
  const rt = fromImage(rleUnpack(sndjFileParse(srmExtract(srm, 1)).packed, BLOCK_SZ));
  assert(rt[0] === 7 && rt[0x2300] === 49, 'srm song round trip');
  const erased = srmParse(srmErase(srm, 0));
  assert(!erased.slots[0].empty && erased.slots[0].name === 'SECOND' &&
    erased.slots[0].off === 0 && erased.slots[1].empty,
    'srm erase compacts the list');
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
  // ---- S-DSP model ----
  // ARAM: directory at $0100 (entry 0 -> $0200), the pad wave above as
  // a looped BRR at $0200, echo buffer up at $E000.
  const aram = new Uint8Array(65536);
  aram[0x100] = 0x00; aram[0x101] = 0x02;   // start
  aram[0x102] = 0x00; aram[0x103] = 0x02;   // loop
  aram.set(brr, 0x200);
  const d = dspNew(aram);
  const W = (r, v) => dspWrite(d, r, v);
  W(0x5D, 0x01);                            // DIR = $0100
  W(0x0C, 0x7F); W(0x1C, 0x7F);             // MVOL
  W(0x6C, 0x00);                            // FLG: run, echo write off
  W(0x00, 0x60); W(0x01, 0x60);             // V0 VOL
  W(0x04, 0x00);                            // SRCN 0
  W(0x07, 0x7F);                            // GAIN direct, full
  W(0x02, 0x00); W(0x03, 0x10);             // pitch $1000 = native rate
  const pre = dspRun(d, 32);
  assert(pre.l.every(v => v === 0), 'dsp silent before KON');
  W(0x4C, 0x01);                            // KON V0
  const g = dspRun(d, 512);
  let peak = 0, sum = 0;
  for (let i = 0; i < 512; i++) {
    peak = Math.max(peak, Math.abs(g.l[i]));
    sum += g.l[i];
  }
  assert(peak > 8000 && peak < 32768, 'dsp voice peak ' + peak);
  assert(Math.abs(sum / 512) < peak / 8, 'dsp voice roughly zero-mean');
  assert(d.regs[0x08] === 0x7F, 'ENVX shows the direct GAIN level');
  assert((d.regs[0x7C] & 1) === 1, 'ENDX set after the loop wrapped');
  // pitch $1000 plays the 128-sample loop at 250 Hz: strong periodicity
  let match = 0;
  for (let i = 128; i < 384; i++) {
    match += Math.abs(g.l[i] - g.l[i + 128]) < 1200 ? 1 : 0;
  }
  assert(match > 224, 'dsp loop periodicity ' + match + '/256');
  // ADSR: fast attack to $7FF, then decay leaks toward the sustain level
  W(0x05, 0x8F); W(0x06, 0xE0);             // A=15 D=0 SL=7 SR=0
  W(0x4C, 0x01);
  dspRun(d, 64);
  assert(d.regs[0x08] > 0x70, 'ADSR attack reached full (' + d.regs[0x08] + ')');
  W(0x5C, 0x01);                            // KOF
  dspRun(d, 300);
  assert(d.regs[0x08] === 0, 'release ran out');
  const tail = dspRun(d, 16);
  assert(tail.l.every(v => v === 0), 'voice silent after release');
  W(0x5C, 0x00);
  // noise: NON voice with no meaningful sample still makes sound
  W(0x3D, 0x01); W(0x07, 0x7F); W(0x6C, 0x1F); W(0x4C, 0x01);
  const nz = dspRun(d, 256);
  let nzp = 0;
  for (const v of nz.l) nzp = Math.max(nzp, Math.abs(v));
  assert(nzp > 4000, 'noise generator audible (' + nzp + ')');
  W(0x3D, 0x00); W(0x5C, 0x01); dspRun(d, 300); W(0x5C, 0x00);
  // PMON: V1 modulated by V0 differs from the same patch unmodulated
  const render = pmon => {
    const d2 = dspNew(new Uint8Array(aram));
    dspWrite(d2, 0x5D, 0x01); dspWrite(d2, 0x0C, 0x7F); dspWrite(d2, 0x1C, 0x7F);
    dspWrite(d2, 0x6C, 0x00); dspWrite(d2, 0x2D, pmon ? 0x02 : 0x00);
    for (const vn of [0, 1]) {
      const vx = vn << 4;
      dspWrite(d2, vx + 4, 0); dspWrite(d2, vx + 7, 0x7F);
      dspWrite(d2, vx + 2, 0x00); dspWrite(d2, vx + 3, vn ? 0x10 : 0x04);
    }
    dspWrite(d2, 0x10, 0x70); dspWrite(d2, 0x11, 0x70);  // V1 audible
    dspWrite(d2, 0x4C, 0x03);
    return dspRun(d2, 400).l;
  };
  const pOn = render(true), pOff = render(false);
  let diff = 0;
  for (let i = 100; i < 400; i++) diff += Math.abs(pOn[i] - pOff[i]);
  assert(diff > 50000, 'PMON bends the carrier (diff ' + diff + ')');
  // echo: an EON'd impulse comes back EDL*512 samples later through
  // a flat FIR, and the delay line landed in ARAM at ESA
  const d3 = dspNew(new Uint8Array(aram));
  const W3 = (r, v) => dspWrite(d3, r, v);
  W3(0x5D, 0x01); W3(0x0C, 0x7F); W3(0x1C, 0x7F);
  W3(0x6D, 0xE0); W3(0x7D, 0x01);           // ESA $E000, EDL 1 = 512 samples
  W3(0x2C, 0x7F); W3(0x3C, 0x7F);           // EVOL
  W3(0x0D, 0x00);                           // no feedback
  W3(0x4D, 0x01);                           // EON V0
  W3(0x0F, 0x7F);                           // FIR tap 0 only: flat
  W3(0x6C, 0x00);                           // FLG: echo write ENABLED
  dspRun(d3, 8);                            // latch echo length at offset 0
  W3(0x00, 0x60); W3(0x01, 0x60); W3(0x04, 0); W3(0x07, 0x7F);
  W3(0x02, 0x00); W3(0x03, 0x10);
  W3(0x4C, 0x01);
  const e1 = dspRun(d3, 96);                // dry hit
  W3(0x5C, 0x01);
  dspRun(d3, 300);                          // release fully
  W3(0x00, 0); W3(0x01, 0);                 // and mute the dry path
  const gap = dspRun(d3, 80);               // still before the echo returns
  let wrote = false;                        // dry hit still sits in the line
  for (let i = 0xE000; i < 0xE800; i++) wrote = wrote || d3.aram[i] !== 0;
  assert(wrote, 'echo delay line written at ESA');
  const wet = dspRun(d3, 512);              // the echo window
  let dryP = 0, gapP = 0, wetP = 0;
  for (const v of e1.l) dryP = Math.max(dryP, Math.abs(v));
  for (const v of gap.l) gapP = Math.max(gapP, Math.abs(v));
  for (const v of wet.l) wetP = Math.max(wetP, Math.abs(v));
  assert(dryP > 8000, 'echo test dry peak ' + dryP);
  assert(gapP < 64, 'silence before the echo returns (' + gapP + ')');
  assert(wetP > dryP / 8, 'echo came back through the FIR (' + wetP + ')');
  // WAV container geometry
  const wav = wavBuild(g.l, g.r, 32000);
  assert(wav.length === 44 + 512 * 4 &&
    String.fromCharCode(...wav.slice(0, 4)) === 'RIFF', 'wav container');

  // WAV metadata scan (rate + smpl loop/root)
  const wavHdr = [];
  const w32 = v => wavHdr.push(v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >>> 24));
  const wtag = t => { for (const c of t) wavHdr.push(c.charCodeAt(0)); };
  wtag('RIFF'); w32(4 + 8 + 16 + 8 + 60); wtag('WAVE');
  wtag('fmt '); w32(16); w32(0); w32(22050); w32(0); w32(0);
  wavHdr[wavHdr.length - 16] = 1;  // PCM tag low byte
  wtag('smpl'); w32(60); w32(0); w32(0); w32(0); w32(67); w32(0); w32(0);
  w32(0); w32(1); w32(0); w32(0); w32(0); w32(100); w32(299); w32(0); w32(0);
  const wi = wavInfo(new Uint8Array(wavHdr));
  assert(wi && wi.rate === 22050 && wi.root === 67 &&
    wi.loop && wi.loop[0] === 100 && wi.loop[1] === 300,
    'wav smpl chunk parsed (rate/root/loop)');

  // ARAM budget calculator (mirrors pool.asm residency)
  const mkE = n => ({ brr: new Uint8Array(n) });
  assert(aramBudget([]).maxEdl === 15, 'empty pool leaves the full echo');
  assert(aramBudget([mkE(54000)]).maxEdl === 3,
    '54000 B of samples cap the echo at EDL 3');
  const over = aramBudget([mkE(61000)]);
  assert(over.maxEdl === -1 && over.overBy === 337,
    'overflowing pool reports the silent overrun');

  console.log('sndj.js selftest: OK (BRR SNR ' + snr.toFixed(1) + ' dB, ' +
    'empty song ' + packed.length + ' bytes, dsp voice peak ' + peak + ')');
}

const SNDJ = {
  sf2Parse, sf2Melodic, sf2Oneshot, sf2Resample,
  SRM_SIZE, SRM_SLOTS, SRM_HEAP_SZ,
  srmNew, srmParse, srmExtract, srmInsert, srmErase, srmLayout,
  sndjFileBuild, sndjFileParse,
  brrEncode, brrDecode, poolParse, poolBuild, aramBudget, wavInfo,
  rlePack, rleUnpack, crc16, toImage, fromImage,
  pitchForNote, findMarker, fixChecksum, selftest,
  dspNew, dspWrite, dspRun, wavBuild,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SNDJ;
  if (process.argv.includes('--selftest') || require.main === module) selftest();
} else if (typeof window !== 'undefined') {
  window.SNDJ = SNDJ;
}
