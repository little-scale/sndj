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
//   dspNew/dspWrite/dspRun                 -- sample-accurate S-DSP model
//   seqNew/seqTick/seqTickRun/seqRender    -- the reference sequencer
//                                             (mirrors src/engine.asm)

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
  if (!bytes || bytes.length < 16) throw new Error('pool header is truncated');
  const magic = String.fromCharCode(...bytes.slice(0, 8));
  if (magic !== 'SNDJPOOL') throw new Error('bad pool magic');
  if (bytes[8] !== 2) throw new Error('pool format v' + bytes[8]);
  const count = bytes[9];
  if (count > POOL_MAX_ENTRIES) throw new Error('pool has too many entries');
  const tableEnd = 16 + count * 16;
  if (tableEnd > bytes.length) throw new Error('pool table is truncated');
  const entries = [];
  for (let i = 0; i < count; i++) {
    const e = 16 + i * 16;
    const name = String.fromCharCode(...bytes.slice(e, e + 8)).trimEnd();
    const off = (bytes[e + 8] | (bytes[e + 9] << 8)) * 9;
    const size = (bytes[e + 10] | (bytes[e + 11] << 8)) * 9;
    const loop = bytes[e + 12] | (bytes[e + 13] << 8);
    if (!size) throw new Error('pool entry ' + i + ' has no BRR data');
    if (off < tableEnd || off + size > bytes.length) {
      throw new Error('pool entry ' + i + ' BRR range is outside the file');
    }
    if (loop !== 0xFFFF && loop >= size / 9) {
      throw new Error('pool entry ' + i + ' loop is outside its BRR data');
    }
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
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    if (!e.brr || !e.brr.length || e.brr.length % 9) {
      throw new Error('pool entry ' + i + ' BRR length must be a positive multiple of 9');
    }
    const blocks = e.brr.length / 9;
    if (e.loopBlock !== null && e.loopBlock !== undefined &&
        (!Number.isInteger(e.loopBlock) || e.loopBlock < 0 || e.loopBlock >= blocks)) {
      throw new Error('pool entry ' + i + ' loop is outside its BRR data');
    }
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
  if (!Number.isSafeInteger(size) || size < 0 || size > 0x1000000) {
    throw new Error('invalid RLE output size');
  }
  const out = new Uint8Array(size);
  let i = 0, o = 0;
  while (o < size) {
    if (i >= data.length) throw new Error('truncated RLE stream');
    const c = data[i++];
    if (c < 0x80) {
      const n = c + 1;
      if (i + n > data.length || o + n > size) throw new Error('invalid RLE literal');
      for (let k = 0; k < n; k++) out[o++] = data[i++];
    } else {
      if (i >= data.length) throw new Error('truncated RLE run');
      const b = data[i++];
      const n = c - 0x80 + 3;
      if (o + n > size) throw new Error('RLE run exceeds output');
      for (let k = 0; k < n; k++) out[o++] = b;
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
  if (!bytes || bytes.length < 12) throw new Error('SF2 header is truncated');
  if (bytes.length > 0x10000000) throw new Error('SF2 is too large');
  const tag = o => String.fromCharCode(...bytes.slice(o, o + 4));
  if (tag(0) !== 'RIFF' || tag(8) !== 'sfbk') throw new Error('not an SF2 RIFF');
  const need = (o, n, what) => {
    if (!Number.isSafeInteger(o) || o < 0 || o + n > bytes.length) {
      throw new Error((what || 'SF2 field') + ' is outside the file');
    }
  };
  const u16 = o => bytes[o] | (bytes[o + 1] << 8);
  const u32 = o => (bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16) |
    (bytes[o + 3] << 24)) >>> 0;
  const chunks = {};
  const riffEnd = 8 + u32(4);
  if (riffEnd > bytes.length || riffEnd < 12) throw new Error('bad SF2 RIFF size');
  const walk = (pos, end, depth = 0) => {
    if (depth > 8) throw new Error('SF2 LIST nesting is too deep');
    while (pos + 8 <= end) {
      need(pos, 8, 'SF2 chunk header');
      const cid = tag(pos);
      const size = u32(pos + 4);
      const body = pos + 8;
      if (body + size > end || body + size > bytes.length) {
        throw new Error('SF2 chunk ' + cid + ' exceeds its container');
      }
      if (cid === 'LIST') {
        if (size < 4) throw new Error('SF2 LIST is truncated');
        walk(body + 4, body + size, depth + 1);
      }
      else chunks[cid] = { off: body, size };
      pos = body + size + (size & 1);
    }
  };
  walk(12, riffEnd);
  if (!chunks.smpl || !chunks.shdr) throw new Error('not an SF2 (no smpl/shdr)');
  if (chunks.smpl.size % 2) throw new Error('SF2 smpl chunk has an odd size');
  const recs = (name, sz) => {
    if (!chunks[name]) return [];
    if (chunks[name].size % sz) throw new Error('SF2 ' + name + ' records are truncated');
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
    if (b0 > b1 || b1 >= ibag.length) throw new Error('SF2 instrument bag range is invalid');
    const sids = new Set();
    for (let bg = b0; bg < b1; bg++) {
      const g0 = u16(ibag[bg]), g1 = u16(ibag[bg + 1]);
      if (g0 > g1 || g1 > igen.length) throw new Error('SF2 instrument generator range is invalid');
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
    if (b0 > b1 || b1 >= pbag.length) throw new Error('SF2 preset bag range is invalid');
    for (let bg = b0; bg < b1; bg++) {
      const g0 = u16(pbag[bg]), g1 = u16(pbag[bg + 1]);
      if (g0 > g1 || g1 > pgen.length) throw new Error('SF2 preset generator range is invalid');
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
  if (n < 0 || n > 4096) throw new Error('SF2 sample count is invalid');
  const smplSamples = chunks.smpl.size / 2;
  let totalSamples = 0;
  for (let i = 0; i < n; i++) {
    const r = chunks.shdr.off + i * 46;
    const start = u32(r + 20), end = u32(r + 24);
    const ls = u32(r + 28), le = u32(r + 32);
    const rate = u32(r + 36);
    const root = bytes[r + 40];
    const corr = bytes[r + 41] > 127 ? bytes[r + 41] - 256 : bytes[r + 41];
    if (start > end || end > smplSamples) throw new Error('SF2 sample ' + i + ' range is invalid');
    if (!rate || rate > 768000) throw new Error('SF2 sample ' + i + ' rate is invalid');
    totalSamples += end - start;
    if (totalSamples > 0x4000000) throw new Error('SF2 decoded samples are too large');
    const pcm = new Int16Array(end - start);
    for (let k = 0; k < pcm.length; k++) {
      const o = smpl + (start + k) * 2;
      const v = bytes[o] | (bytes[o + 1] << 8);
      pcm[k] = v > 32767 ? v - 65536 : v;
    }
    out.push({
      name: str(r, 20), pcm, rate, root, corr,
      // shape-based (ripped fonts set sampleModes unreliably both ways);
      // degenerate loops read as one-shots
      loop: (le - ls >= 16 && le > ls && ls >= start && le <= end)
        ? [ls - start, le - start] : null,
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
  // SF2 roots are MIDI notes. Console C-5 is note index 60, which the MIDI
  // input path maps from MIDI 72 (stored phrase byte 61 is a different,
  // one-based representation and must not be used as an SF2 root target).
  const shift = 72 - rootEff + trim;
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
  let maxEdl = -1;
  for (let edl = 15; edl >= 0; edl--) {
    const ceilPage = edl === 0 ? 0xFF : 0x100 - 8 * edl;
    if (end <= (ceilPage << 8)) { maxEdl = edl; break; }
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
  if (!srm || srm.length < SRM_SIZE) throw new Error('save image is truncated');
  const magic = String.fromCharCode(...srm.slice(0, 5));
  const valid = magic === 'SNDJ1' && srm[5] === 2;
  const slots = [];
  const ranges = [];
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
    const bounds = size <= SRM_HEAP_SZ && off <= SRM_HEAP_SZ - size;
    const data = bounds ? srm.slice(SRM_HEAP + off, SRM_HEAP + off + size)
      : new Uint8Array();
    const slot = {
      index: s, empty: false, off, size, crc, name, bounds,
      ok: bounds && crc16(data) === crc,
      packed: data,
    };
    slots.push(slot);
    if (bounds) ranges.push({ start: off, end: off + size, slot });
  }
  ranges.sort((a, b) => a.start - b.start);
  let used = 0, lastEnd = 0;
  for (const r of ranges) {
    if (r.start < lastEnd) {
      r.slot.ok = false;
      const prior = ranges.find(x => x !== r && x.start < r.end && x.end > r.start);
      if (prior) prior.slot.ok = false;
    }
    used += Math.max(0, r.end - Math.max(r.start, lastEnd));
    lastEnd = Math.max(lastEnd, r.end);
  }
  const free = SRM_HEAP_SZ - used;
  return { valid, slots, free };
}

// rebuild the image from a song list (packed heap in entry order)
function srmLayout(songs) {
  if (!Array.isArray(songs) || songs.length > SRM_SLOTS) {
    throw new Error('save has too many songs (max ' + SRM_SLOTS + ')');
  }
  const srm = srmNew();
  let off = 0;
  songs.forEach((song, s) => {
    if (!song || !song.packed || song.packed.length > 0xFFFF) {
      throw new Error('song ' + s + ' has an invalid packed payload');
    }
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
  const parsed = srmParse(srm);
  if (!parsed.valid) throw new Error('not an SNDJ1 v2 save');
  const bad = parsed.slots.find(s => !s.empty && !s.ok);
  if (bad) throw new Error('save slot ' + bad.index + ' is corrupt; refusing to rewrite');
  return parsed.slots.filter(s => !s.empty)
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
  if (!s.ok) throw new Error('slot ' + slotIdx + ' is corrupt');
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
  if (!bytes || bytes.length < 18) throw new Error('.sndj header is truncated');
  if (String.fromCharCode(...bytes.slice(0, 5)) !== 'SNDJ1' || bytes[5] !== 1) {
    throw new Error('not a .sndj file');
  }
  const name = String.fromCharCode(...bytes.slice(6, 14)).trimEnd();
  const size = bytes[14] | (bytes[15] << 8);
  const crc = bytes[16] | (bytes[17] << 8);
  if (bytes.length !== 18 + size) throw new Error('.sndj size does not match the file');
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
  for (let i = 0; i + m.length <= rom.length; i++) {
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
  if (d.onWrite) d.onWrite(reg, val);           // register-log hook (spcexport)
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

// ------------------------------------------------------ reference sequencer
// A JS mirror of the console engine — src/engine.asm (tick pipeline,
// triggers, the A-Z executor, fx), src/apu.asm (apply_instrument, tune
// contexts, tempo) and src/pool.asm (residency: the ARAM image a song
// load builds) — driving the S-DSP model above. Every deviation from
// the asm is a bug. This is what plays .sndj songs in the browser
// (savetool preview, spcexport) and renders them to WAV offline.
//
//   const seq = seqNew(block, poolEntries);   // block: 0x5300 song image
//   const {l, r} = seqTickRun(seq);           // one engine tick of audio
//   const wav = seqRender(block, pool, 20);   // 20 s -> {l, r, rate}

const SEQ_SB = {
  SONG: 0x0000, INSTR: 0x0400, TABLES: 0x0800, GROOVES: 0x1000,
  WAVES: 0x1100, KITS: 0x1200, HEADER: 0x1600, CHAINS: 0x1700,
  PHRASES: 0x2300,
};
const SEQ_SH = {
  GROOVE: 0, TRANSPOSE: 1, MAGIC: 2, EDL: 3, EFB: 4, EVL: 5, EVR: 6,
  EON: 7, FIR: 8, NAME: 9, MODE: 17, BPM: 18, FIRTAPS: 19,
};
const SEQ_ARAM_DIR = 0x1000, SEQ_ARAM_WAVES = 0x1100, SEQ_ARAM_STUB = 0x1200;
const SEQ_DIR_SLOT_MAX = 56;      // sample slots 0-55 (0 = silence), waves 56-63
const SEQ_NOTE_OFF = 97, SEQ_NOTE_MAX = 96;

// src/main.asm fir_presets (SNFIR0)
const SEQ_FIR_PRESETS = [
  [0x7F, 0, 0, 0, 0, 0, 0, 0],                          // FLAT
  [0x58, 0x30, 0x12, 0x08, 0, 0, 0, 0],                 // DARK
  [0x70, 0xE8, 0x18, 0xF4, 0, 0, 0, 0],                 // BRIGHT
  [0x40, 0, 0, 0x40, 0, 0, 0, 0],                       // COMB
  [0x20, 0x30, 0x40, 0x30, 0x20, 0x10, 0x08, 0x04],     // SOFT
  [0x4C, 0x21, 0x12, 0x09, 0x05, 0x03, 0x02, 0x01],     // DKC HALL
  [0x60, 0xA0, 0x40, 0xD0, 0x20, 0xE8, 0x10, 0xF8],     // METAL
  [0x7F, 0, 0, 0, 0, 0, 0, 0],                          // USER
];
// src/apu.asm karp_burst_sr (BURST nibble -> exciter ADSR2 sustain rate)
const SEQ_KARP_SR = [20, 21, 22, 22, 23, 24, 25, 25, 26, 27, 28, 28, 29, 30, 31, 31];

// tools/maketables.py karp_entry: note m + EDL -> exciter pitch (the comb
// partial's exact frequency) and the 2-tap fractional pull
function karpEntry(m, edl) {
  const base = edl * 512;
  const f = 440 * 2 ** ((m - 57) / 12);
  const n = Math.max(1, Math.round(f * (base + 3.5) / 32000));
  const dd = Math.max(0, Math.min(7, 32000 * n / f - base));
  const pitch = Math.min(0x3FFF, Math.round(32000 * n / (base + dd) * 4096 / 1000));
  const i0 = Math.min(6, Math.floor(dd));
  return { pitch, i0, fr: Math.min(255, Math.round((dd - i0) * 256)) };
}

// ---- the ARAM image residency_build makes (src/pool.asm) ----
function seqAramBuild(block, pool) {
  const aram = new Uint8Array(65536);
  const poolMap = new Uint8Array(64);
  const sliceBase = new Uint8Array(64);
  const dir = (slot, start, loop) => {
    const o = SEQ_ARAM_DIR + slot * 4;
    aram[o] = start & 0xFF; aram[o + 1] = start >> 8;
    aram[o + 2] = loop & 0xFF; aram[o + 3] = loop >> 8;
  };
  // slot 0: the silent stub (END, no loop)
  aram[SEQ_ARAM_STUB] = 0x01;
  dir(0, SEQ_ARAM_STUB, SEQ_ARAM_STUB);
  const dirStart = [];                  // per pool idx: ARAM start + loop
  const dirLoop = [];
  let slot = 1, cursor = SEQ_ARAM_STUB + 9;
  const edl = block[SEQ_SB.HEADER + SEQ_SH.EDL] & 0x0F;
  const ceil = edl ? 0x100 - edl * 8 : 0xFF;      // echo buffer page ceiling
  const mark = i => {
    if (i >= pool.length || poolMap[i]) return;
    if (slot >= SEQ_DIR_SLOT_MAX) return;
    const e = pool[i], len = e.brr.length;
    if (cursor + len > 0xFFFF || ((cursor + len) >> 8) >= ceil) return;
    aram.set(e.brr, cursor);
    aram[cursor + len - 9] |= 0x02;     // force LOOP on the END block —
                                        // loop-or-not is the directory's choice
    dirStart[i] = cursor;
    dirLoop[i] = e.loopBlock === null ? SEQ_ARAM_STUB : cursor + e.loopBlock * 9;
    dir(slot, cursor, dirLoop[i]);
    poolMap[i] = slot++;
    cursor += len;
  };
  // scan instruments (SMP sample fields), then kits (slots with vol > 0)
  for (let id = 0; id < 64; id++) {
    const r = SEQ_SB.INSTR + id * 16;
    if ((block[r] & 0x07) === 0) mark(block[r + 1]);
  }
  for (let s = 0; s < 256; s++) {
    const k = SEQ_SB.KITS + s * 4;
    if (block[k + 2]) mark(block[k]);
  }
  // per-instrument directory aliases: SLICE windows + SMP LOOP overrides
  for (let id = 0; id < 64; id++) {
    const r = SEQ_SB.INSTR + id * 16, type = block[r] & 0x07;
    if (type === 4) {                                  // SLICE
      const n = (block[r + 7] >> 4) + 1;
      const blob = block[r + 1] & 0x3F;
      mark(blob);
      if (!poolMap[blob] || slot + n > SEQ_DIR_SLOT_MAX) continue;
      const stepBlocks = Math.floor(pool[blob].brr.length / 9 / n);
      if (!stepBlocks) continue;
      sliceBase[id] = slot;
      for (let i = 0; i < n; i++) {
        dir(slot++, dirStart[blob] + i * stepBlocks * 9, SEQ_ARAM_STUB);
      }
    } else if (type === 0) {                           // SMP LOOP override
      const mode = (block[r + 7] >> 1) & 0x03;         // 1 = ON, 2 = OFF
      if (!mode) continue;
      const blob = block[r + 1] & 0x3F;
      mark(blob);
      if (!poolMap[blob] || slot >= SEQ_DIR_SLOT_MAX) continue;
      let loop = SEQ_ARAM_STUB;
      if (mode === 1) {
        loop = dirLoop[blob] === SEQ_ARAM_STUB ? dirStart[blob] : dirLoop[blob];
      }
      dir(slot, dirStart[blob], loop);
      sliceBase[id] = slot++;
    }
  }
  // wave scratch slots (SRCN 56-63): compile the 8 drawn banks to
  // 2-block looped BRRs (range 11, filter 0) — src/wave.asm
  for (let bank = 0; bank < 8; bank++) {
    const slotAddr = SEQ_ARAM_WAVES + bank * 18;
    dir(56 + bank, slotAddr, slotAddr);
    aram[slotAddr] = 0xB0;              // range 11
    aram[slotAddr + 9] = 0xB3;          // range 11, LOOP+END
    for (let p = 0; p < 16; p++) {
      const s0 = (block[SEQ_SB.WAVES + bank * 32 + p * 2] - 8) & 0x0F;
      const s1 = (block[SEQ_SB.WAVES + bank * 32 + p * 2 + 1] - 8) & 0x0F;
      aram[slotAddr + 1 + p + (p >= 8 ? 1 : 0)] = (s0 << 4) | s1;
    }
  }
  return { aram, poolMap, sliceBase, sampleEnd: cursor };
}

// ---- construction: boot + song load + engine_go -----------------------------
function seqNew(block, pool, opts) {
  opts = opts || {};
  const { aram, poolMap, sliceBase, sampleEnd } = seqAramBuild(block, pool);
  const d = dspNew(aram);
  if (opts.onWrite) d.onWrite = opts.onWrite;
  const seq = {
    block, pool, aram, dsp: d, poolMap, sliceBase, sampleEnd,
    trig: { voice: 0, id: 0, type: 0, note: 0, semis: 0, fine: 0 },
    lastPitch: 0,
    engNoise: 0, engNon: 0, engEon: 0, engPmon: 0,
    konMask: 0, koffMask: 0, konCount: 0,
    gpos: 0, tickwait: 0, walkGuard: 16, row: 0x0F,
    samplesPerTick: 532, halted: false,
    tracks: [],
  };
  for (let t = 0; t < 8; t++) {
    seq.tracks.push({
      songrow: 0, cpos: 0, tsp: 0, chain: 0xFF, phrase: 0xFF, prow: 0xFF,
      instr: 0, instrActive: 0xFF, note: 0, pitch: 0,
      cmd: 0, cval: 0, dlyCnt: 0xFF, dlyNote: 0, killCnt: 0xFF,
      pending: 0xFF, playcnt: 0, mute: false,
      tbl: 0xFF, tblSpd: 0, tblCnt: 0, tblRow: 0,
      retPer: 0, retCnt: 0, slRate: 0, slNote: 0, slT: 0,
      arpPh: 0, vib: 0, vibPh: 0, trm: 0, trmPh: 0,
      voll: 0, volr: 0, fine: 0, chord: 0,
    });
  }
  const W = (r, v) => dspWrite(d, r, v);
  // boot (driver entry + apu_audio_init)
  W(0x5D, SEQ_ARAM_DIR >> 8);
  W(0x0C, 0x60); W(0x1C, 0x60);
  W(0x6D, 0xFF); W(0x7D, 0x00);
  W(0x5C, 0x00); W(0x3D, 0x00); W(0x2D, 0x00);
  W(0x6C, 0x20);
  for (let v = 0; v < 8; v++) {
    W(v * 16 + 0, 0x50); W(v * 16 + 1, 0x50);
    W(v * 16 + 4, 0x00); W(v * 16 + 5, 0xAF); W(v * 16 + 6, 0xCA);
  }
  // apu_echo_apply: header echo config
  const h = SEQ_SB.HEADER;
  W(0x2C, block[h + SEQ_SH.EVL]); W(0x3C, block[h + SEQ_SH.EVR]);
  W(0x0D, block[h + SEQ_SH.EFB]);
  seqEonSync(seq);
  for (let t = 0; t < 8; t++) W(0x0F + t * 16, block[h + SEQ_SH.FIRTAPS + t]);
  const edl = block[h + SEQ_SH.EDL] & 0x0F;
  const esa = edl ? (0x100 - edl * 8) & 0xFF : 0xFF;
  if (edl !== 0 || esa !== 0xFF) {      // the driver's unchanged-config fast path
    aram.fill(0, esa << 8, (esa << 8) + Math.max(1, edl * 8) * 256);
    W(0x6D, esa); W(0x7D, edl);
    W(0x6C, 0x00);                      // driver re-enable: unmute, echo on
  }
  // engine_go
  seqSetTempo(seq, block[h + SEQ_SH.BPM] || 150);
  if (opts.startRow) {                  // engine_play_row
    for (const trk of seq.tracks) trk.songrow = opts.startRow & 0x7F;
  }
  for (let t = 0; t < 8; t++) seqLoadSongrow(seq, t);
  return seq;
}

function seqSetTempo(seq, bpm) {
  if (bpm < 80) bpm = 80;
  seq.samplesPerTick = 4 * Math.floor(20000 / bpm);   // Timer-0 target * 4
}

// effective echo sends: instrument ECHO flag AND the channel's EON MASK bit
function seqEonSync(seq) {
  const b = seq.block;
  let eon = 0;
  for (let t = 0; t < 8; t++) {
    const id = seq.tracks[t].instr;
    if (id === 0xFF) continue;
    if ((b[SEQ_SB.INSTR + id * 16 + 7] & 1) &&
        (b[SEQ_SB.HEADER + SEQ_SH.EON] & (1 << t))) eon |= 1 << t;
  }
  seq.engEon = eon;
  dspWrite(seq.dsp, 0x4D, eon);
}

// ---- song walking (track_load_songrow / chain entries / chain step) ---------
function seqSongCell(seq, t, row) {
  return seq.block[SEQ_SB.SONG + t * 128 + row];
}

function seqLoadSongrow(seq, t) {
  const trk = seq.tracks[t];
  const cell = seqSongCell(seq, t, trk.songrow);
  trk.chain = cell;
  if (cell !== 0xFF) {
    trk.cpos = 0;
    seqLoadChainEntry(seq, t);
    return;
  }
  for (let row = trk.songrow + 1; row < 128; row++) {  // enter at the first
    if (seqSongCell(seq, t, row) !== 0xFF) {           // populated cell below
      trk.songrow = row;
      seqLoadSongrow(seq, t);
      return;
    }
  }
  trk.phrase = 0xFF;                    // nothing below: halt the track
}

function seqLoadChainEntry(seq, t) {
  const trk = seq.tracks[t];
  const o = SEQ_SB.CHAINS + trk.chain * 32 + trk.cpos * 2;
  const ph = seq.block[o];
  if (ph !== 0xFF) {
    trk.phrase = ph;
    trk.tsp = seq.block[o + 1];
    seq.walkGuard = 16;
    return;
  }
  if (trk.songrow === 0xFF) {           // standalone chain: loop or halt
    if (trk.cpos === 0) { trk.phrase = 0xFF; return; }
    trk.cpos = 0;
    seqLoadChainEntry(seq, t);
    return;
  }
  if (--seq.walkGuard === 0) { trk.phrase = 0xFF; return; }
  seqNextSongrow(seq, t);
}

// end of chain: the next song row, or loop to the top of the contiguous block
function seqNextSongrow(seq, t) {
  const trk = seq.tracks[t];
  if (trk.songrow + 1 < 128 && seqSongCell(seq, t, trk.songrow + 1) !== 0xFF) {
    trk.songrow++;
    seqLoadSongrow(seq, t);
    return;
  }
  let row = trk.songrow;
  while (row > 0 && seqSongCell(seq, t, row - 1) !== 0xFF) row--;
  trk.songrow = row;
  seqLoadSongrow(seq, t);
}

function seqChainStep(seq, t) {
  const trk = seq.tracks[t];
  if (trk.pending !== 0xFF) {           // LIVE-queued launch
    trk.chain = trk.pending;
    trk.pending = 0xFF;
    trk.songrow = 0xFF;                 // behaves as a standalone looping chain
    trk.cpos = 0;
    seqLoadChainEntry(seq, t);
    return;
  }
  if (trk.chain === 0xFE) return;       // standalone phrase loops
  trk.cpos = (trk.cpos + 1) & 0x0F;
  if (trk.cpos !== 0) { seqLoadChainEntry(seq, t); return; }
  seqNextSongrow(seq, t);
}

// ---- tune contexts (src/apu.asm) --------------------------------------------
function seqTunePool(seq, poolIdx, extraFine) {
  const e = seq.pool[poolIdx];
  let semis = e ? e.tuneSemis : 0;
  let s = (e ? e.tuneFine : 0) + extraFine;
  if (s >= 128) { s -= 256; semis++; }
  else if (s < -128) { s += 256; semis--; }
  seq.trig.semis = semis;
  seq.trig.fine = s;
}

function seqTuneLoad(seq, id) {
  const r = SEQ_SB.INSTR + id * 16, b = seq.block;
  const fine = i8(b[r + 6]), type = b[r] & 0x07;
  if (type === 0 || type === 3 || type === 4) seqTunePool(seq, b[r + 1] & 0x3F, fine);
  else if (type === 2) {                // WAV: +1 semi, -52 fine (8-bit wrap)
    seq.trig.semis = 1;
    seq.trig.fine = i8((fine - 52) & 0xFF);
  } else {                              // KIT (slot tune at trigger) / KARP
    seq.trig.semis = 0;
    seq.trig.fine = fine;
  }
}

function seqTrackTuneLoad(seq, t) {
  const id = seq.tracks[t].instr;
  if (id === 0xFF) { seq.trig.semis = 0; seq.trig.fine = 0; return; }
  seq.trig.id = id;
  seqTuneLoad(seq, id);
}

// ---- pitch (note_pitch_calc_only: table + fine interpolation) ---------------
function seqPitchCalc(seq, note) {
  const t = seq.trig;
  if (!t.semis && !t.fine) return pitchForNote(note);
  let n = note + t.semis;
  if (n < 0) n = 0;
  if (n >= 96) n = 95;
  let fine = t.fine;
  if (fine < 0) {
    if (n === 0) fine = 0;
    else { n--; fine &= 0xFF; }         // borrow a semitone, keep the fraction
  }
  if (!fine) return pitchForNote(n);
  const base = pitchForNote(n);
  if (n + 1 >= 96) return base;
  const delta = pitchForNote(n + 1) - base;
  return (base + ((delta * fine) >> 8)) & 0xFFFF;
}

function seqPitchWrite(seq, pitch) {
  const v = seq.trig.voice * 16;
  dspWrite(seq.dsp, v + 2, pitch & 0xFF);
  dspWrite(seq.dsp, v + 3, (pitch >> 8) & 0xFF);
}

// ---- apply_instrument --------------------------------------------------------
function seqApply(seq, id) {
  const g = seq.trig, b = seq.block, W = (r, v) => dspWrite(seq.dsp, r, v);
  g.id = id;
  seqTuneLoad(seq, id);
  const v = g.voice, vx = v * 16, bit = 1 << v;
  const r = SEQ_SB.INSTR + id * 16;
  const trk = seq.tracks[v];
  g.type = b[r] & 0x07;
  if (trk.instrActive === id) return;
  trk.instrActive = id;
  // SRCN: WAV = scratch slot; SMP alias (LOOP override) wins over the pool
  let srcn;
  if (g.type === 2) srcn = 56 + (b[r + 1] & 0x07);
  else if (g.type === 0 && seq.sliceBase[id]) srcn = seq.sliceBase[id];
  else srcn = seq.poolMap[b[r + 1] & 0x3F];
  W(vx + 4, srcn);
  // NON bit
  const non = g.type === 3 ? (seq.engNon | bit) : (seq.engNon & ~bit);
  if (non !== seq.engNon) { seq.engNon = non; W(0x3D, non); }
  // EON bit (KARP sends unconditionally — the exciter must reach the string)
  let eon;
  if (g.type === 5) eon = seq.engEon | bit;
  else if ((b[r + 7] & 1) && (b[SEQ_SB.HEADER + SEQ_SH.EON] & bit)) {
    eon = seq.engEon | bit;
  } else eon = seq.engEon & ~bit;
  if (eon !== seq.engEon) { seq.engEon = eon; W(0x4D, eon); }
  // envelope
  if (g.type === 5) {                   // KARP: seed burst
    W(vx + 5, 0xFF);
    W(vx + 6, SEQ_KARP_SR[b[r + 2] >> 4]);
  } else if (g.type === 4) {            // SLICE: attack + FADE nibbles
    W(vx + 5, 0x80 | (b[r + 2] & 0x0F));
    const fade = b[r + 2] >> 4;
    W(vx + 6, 0xE0 | (fade ? fade + 14 : 0));
  } else {
    W(vx + 5, b[r + 2] | 0x80);
    W(vx + 6, b[r + 3]);
  }
  // volume, latched as the voice's live level
  trk.voll = i8(b[r + 4]);
  trk.volr = i8(b[r + 5]);
  W(vx + 0, b[r + 4]);
  W(vx + 1, b[r + 5]);
}

// ---- type triggers -----------------------------------------------------------
function seqKitTrigger(seq) {
  const g = seq.trig, b = seq.block, W = (r, v) => dspWrite(seq.dsp, r, v);
  const kit = b[SEQ_SB.INSTR + g.id * 16 + 1] & 0x0F;
  const k = SEQ_SB.KITS + kit * 64 + (g.note & 0x0F) * 4;
  const vol = b[k + 2];
  if (!vol) return false;               // empty slot: no KON
  seqTunePool(seq, b[k] & 0x3F, 0);
  const vx = g.voice * 16;
  W(vx + 4, seq.poolMap[b[k] & 0x3F]);
  W(vx + 0, vol); W(vx + 1, vol);       // per-slot volume overrides
  let n = (60 + i8(b[k + 1])) & 0xFF;
  if (n >= 96) n = 60;                  // wild tunes snap back to native
  seq.lastPitch = seqPitchCalc(seq, n);
  seqPitchWrite(seq, seq.lastPitch);
  seq.tracks[g.voice].instrActive = 0xFF;
  return true;
}

function seqSliceTrigger(seq) {
  const g = seq.trig, b = seq.block;
  const r = SEQ_SB.INSTR + g.id * 16;
  const n = (b[r + 7] >> 4) + 1;
  seqTunePool(seq, b[r + 1] & 0x3F, i8(b[r + 6]));
  const slice = g.note % n;
  const base = seq.sliceBase[g.id];
  dspWrite(seq.dsp, g.voice * 16 + 4, base ? base + slice : 0);
  let note = (60 + i8(b[r + 9])) & 0xFF;
  if (note >= 96) note = 60;
  seq.lastPitch = seqPitchCalc(seq, note);
  seqPitchWrite(seq, seq.lastPitch);
  seq.tracks[g.voice].instrActive = 0xFF;
}

function seqKarpTrigger(seq) {
  const g = seq.trig, b = seq.block, W = (r, v) => dspWrite(seq.dsp, r, v);
  const r = SEQ_SB.INSTR + g.id * 16;
  const edl = b[SEQ_SB.HEADER + SEQ_SH.EDL] & 0x0F;
  const tab = karpEntry(g.note, edl === 2 ? 2 : 1);
  const damp = b[r + 2] & 0x0F;
  W(g.voice * 16 + 4, 56 + (b[r + 1] & 0x07));      // exciter wave bank
  W(0x0D, b[r + 3] & 0x7F);                         // feedback = SUSTAIN
  seqPitchWrite(seq, tab.pitch);
  seq.lastPitch = tab.pitch;
  // taps: tuning pair flanked by DAMP's smoothing sides (total always 127)
  const side = (15 - damp) * 2;
  const pair = 127 - 2 * side;
  const m = (pair * tab.fr) >> 8;
  const taps = [0, 0, 0, 0, 0, 0, 0, 0];
  taps[tab.i0] = pair - m;
  taps[tab.i0 + 1] = m;
  if (tab.i0 === 0) taps[0] += side; else taps[tab.i0 - 1] += side;
  if (tab.i0 >= 6) taps[7] += side; else taps[tab.i0 + 2] += side;
  for (let i = 0; i < 8; i++) W(0x0F + i * 16, taps[i]);
  seq.tracks[g.voice].instrActive = 0xFF;
}

// ---- track_trigger_note --------------------------------------------------------
function seqTriggerNote(seq, t, rawNote) {
  const g = seq.trig, b = seq.block, trk = seq.tracks[t];
  g.type = 0;
  g.voice = t;
  g.semis = 0;
  g.fine = 0;
  if (trk.instr !== 0xFF) seqApply(seq, trk.instr);
  // the instrument's table + LFO seeds
  if (g.id !== 0xFF) {
    const r = SEQ_SB.INSTR + g.id * 16;
    trk.vib = b[r + 14];
    trk.trm = b[r + 15];
    trk.vibPh = 0;
    trk.trmPh = 0;
    const tbl = b[r + 12], tbs = b[r + 13] & 0x0F;
    if (tbl >= 0x20) trk.tbl = 0xFF;
    else {
      trk.tblSpd = tbs;
      if (tbs === 0) {                  // note-sync: keep the row on re-trigger
        if (tbl !== trk.tbl) trk.tblRow = 0;
      } else trk.tblRow = 0;
      trk.tbl = tbl;
      trk.tblCnt = 1;                   // row 0 (or the kept row) runs this tick
    }
  }
  g.fine = i8((g.fine + i8(trk.fine)) & 0xFF);      // F command folds in
  let note = (rawNote + i8(trk.tsp) +
    i8(b[SEQ_SB.HEADER + SEQ_SH.TRANSPOSE]) - 1) & 0xFF;
  if (note >= SEQ_NOTE_MAX) note = SEQ_NOTE_MAX - 1;
  g.note = note;
  trk.note = note;
  let pitch;
  if (g.type === 1) {                   // KIT
    if (!seqKitTrigger(seq)) return;    // empty slot: no KON, no fanout
    pitch = seq.lastPitch;
  } else if (g.type === 4) {            // SLICE
    seqSliceTrigger(seq);
    pitch = seq.lastPitch;
  } else if (g.type === 5) {            // KARP
    seqKarpTrigger(seq);
    pitch = seq.lastPitch;
  } else if (g.type === 3) {            // NSE: the global noise clock
    const clk = b[SEQ_SB.INSTR + g.id * 16 + 1];
    seq.engNoise = (clk ? clk - 1 : note) & 0x1F;
    dspWrite(seq.dsp, 0x6C, seq.engNoise);
    pitch = seq.lastPitch;
  } else if (g.type === 2) {            // WAV: -1 octave, tuned context
    pitch = seqPitchCalc(seq, note) >> 1;
    seqPitchWrite(seq, pitch);
  } else {
    pitch = seqPitchCalc(seq, note);
    seqPitchWrite(seq, pitch);
  }
  trk.pitch = pitch & 0xFFFF;
  trk.slRate = 0;
  seq.konMask |= 1 << t;
  seqGrpFanout(seq, t);
}

// C-command chord: fan the trigger onto the two voices to the right.
// (Per-instrument GRP removed 2026-07-11; record bytes 8/10/11 reserved.)
function seqGrpFanout(seq, t) {
  const g = seq.trig, trk = seq.tracks[t];
  if (trk.instr === 0xFF || !trk.chord) return;
  const id = g.id;
  const baseNote = g.note;
  for (let m = 1; m <= 2; m++) {
    const voice = t + m;
    if (voice >= 8) break;
    g.voice = voice;
    const ofs = m === 1 ? trk.chord >> 4 : trk.chord & 0x0F;
    let note = (baseNote + ofs) & 0xFF;
    if (note >= SEQ_NOTE_MAX) note = SEQ_NOTE_MAX - 1;
    seqApply(seq, id);
    let pitch = seqPitchCalc(seq, note);
    if (g.type === 2) pitch >>= 1;      // WAV members keep the -1 octave
    seqPitchWrite(seq, pitch);
    seq.konMask |= 1 << voice;
  }
  g.voice = t;
}

// ---- the A-Z executor ----------------------------------------------------------
function seqVolWrite(seq, t) {
  const trk = seq.tracks[t];
  dspWrite(seq.dsp, t * 16 + 0, trk.voll & 0xFF);
  dspWrite(seq.dsp, t * 16 + 1, trk.volr & 0xFF);
}

// pre-trigger commands; returns true when the note trigger is consumed (D/L)
function seqCmdPre(seq, t, row) {
  const trk = seq.tracks[t], b = seq.block, W = (r, v) => dspWrite(seq.dsp, r, v);
  const cmd = trk.cmd, val = trk.cval;
  switch (cmd) {
    case 7: {                           // G xy: the public 2-step groove
      b[SEQ_SB.GROOVES] = (val >> 4) || 1;
      b[SEQ_SB.GROOVES + 1] = (val & 0x0F) || 1;
      break;
    }
    case 2: {                           // B: wave bank (SRCN = 56 + bank)
      W(t * 16 + 4, 56 + (val & 0x07));
      trk.instrActive = 0xFF;
      break;
    }
    case 20: seqSetTempo(seq, val); break;            // T
    case 5: {                           // E: the channel's EON MASK gate
      const h = SEQ_SB.HEADER + SEQ_SH.EON;
      if (val) b[h] |= 1 << t; else b[h] &= ~(1 << t);
      seqEonSync(seq);
      break;
    }
    case 25: {                          // Y: FIR preset -> song taps
      const p = SEQ_FIR_PRESETS[val & 0x07];
      b[SEQ_SB.HEADER + SEQ_SH.FIR] = val & 0x07;
      for (let i = 0; i < 8; i++) {
        b[SEQ_SB.HEADER + SEQ_SH.FIRTAPS + i] = p[i];
        W(0x0F + i * 16, p[i]);
      }
      break;
    }
    case 14: {                          // N: global noise clock
      seq.engNoise = val & 0x1F;
      W(0x6C, seq.engNoise);
      break;
    }
    case 3: trk.chord = val; break;     // C
    case 9: {                           // I: play-count mask
      if (!((val >> (trk.playcnt & 0x07)) & 1)) row.note = 0;
      break;
    }
    case 10: {                          // J xy: per-pass transpose
      if (row.note && row.note !== SEQ_NOTE_OFF &&
          ((val >> 4 >> (trk.playcnt & 0x03)) & 1)) {
        let y = val & 0x0F;
        if (y >= 8) y -= 16;
        const n = row.note + y;
        if (n > 0 && n <= SEQ_NOTE_MAX) row.note = n;
      }
      break;
    }
    case 13: {                          // M: master volume
      W(0x0C, val & 0x7F);
      W(0x1C, val & 0x7F);
      break;
    }
    case 6: trk.fine = i8(val); break;  // F
    case 19: {                          // S xy: sweep up (x) / down (y)
      trk.slNote = trk.note;
      if (val & 0xF0) { trk.slRate = val >> 4; trk.slT = 0x3FFF; }
      else { trk.slRate = val & 0x0F; trk.slT = 0x0000; }
      break;
    }
    case 17: {                          // Q xy: GAIN override
      if (trk.instr === 0xFF) break;
      const adsr1 = b[SEQ_SB.INSTR + trk.instr * 16 + 2];
      if (!(val & 0xF0)) {              // Q00: back to ADSR
        W(t * 16 + 5, adsr1 | 0x80);
        break;
      }
      const mode = val >> 4;
      const gain = mode === 1
        ? (val & 0x0F) << 3
        : 0x80 | (((mode - 2) & 0x03) << 5) | (val & 0x0F);
      W(t * 16 + 7, gain);
      W(t * 16 + 5, adsr1 & 0x7F);      // GAIN active
      trk.instrActive = 0xFF;
      break;
    }
    case 21: {                          // U xy: surround (phase invert)
      let l = Math.abs(trk.voll);
      if (val & 0xF0) l = -l;
      trk.voll = l;
      let r = Math.abs(trk.volr);
      if (val & 0x0F) r = -r;
      trk.volr = r;
      trk.instrActive = 0xFF;
      seqVolWrite(seq, t);
      break;
    }
    case 26: {                          // Z: pitch-mod by the left neighbour
      if (val) seq.engPmon |= 1 << t; else seq.engPmon &= ~(1 << t);
      W(0x2D, seq.engPmon);
      break;
    }
    case 11: trk.killCnt = (val + 1) & 0xFF; break;   // K
    case 18: {                          // R: retrig
      trk.retPer = (val & 0x0F) || 1;
      trk.retCnt = trk.retPer;
      break;
    }
    case 4: {                           // D: delay the note
      if (row.note && row.note !== SEQ_NOTE_OFF && val) {
        trk.dlyCnt = val;
        trk.dlyNote = row.note;
        return true;
      }
      break;
    }
    case 12: {                          // L: slide to the note, legato
      if (!row.note || row.note === SEQ_NOTE_OFF) break;
      let n = (row.note + i8(trk.tsp) - 1) & 0xFF;
      if (n >= SEQ_NOTE_MAX) n = SEQ_NOTE_MAX - 1;
      trk.slNote = n;
      seq.trig.voice = t;
      seqTrackTuneLoad(seq, t);
      trk.slT = seqPitchCalc(seq, n);
      trk.slRate = val || 1;
      return true;
    }
  }
  return false;
}

function seqCmdPost(seq, t) {
  const trk = seq.tracks[t];
  switch (trk.cmd) {
    case 22: trk.vib = trk.cval; break;               // V: vibrato override
    case 24: {                                        // X: volume/accent
      trk.voll = trk.cval & 0x7F;
      trk.volr = trk.cval & 0x7F;
      seqVolWrite(seq, t);
      break;
    }
    case 16: {                                        // P: pan
      trk.voll = (255 - trk.cval) >> 1;
      trk.volr = trk.cval >> 1;
      seqVolWrite(seq, t);
      break;
    }
  }
}

// ---- track_row ------------------------------------------------------------------
function seqTrackRow(seq, t) {
  const trk = seq.tracks[t], b = seq.block;
  if (trk.phrase === 0xFF) return;
  let hopGuard = 4;
  if (trk.prow === 0xFF) trk.prow = 0;
  else {
    trk.prow = (trk.prow + 1) & 0x0F;
    if (trk.prow === 0) {
      trk.playcnt = (trk.playcnt + 1) & 0xFF;
      seqChainStep(seq, t);
      if (trk.phrase === 0xFF) return;
    }
  }
  if (trk.mute) return;                 // muted tracks advance, stay silent
  let o = SEQ_SB.PHRASES + trk.phrase * 64 + trk.prow * 4;
  // H hops NOW: this row tick plays row 0 of the next chain entry
  while (b[o + 2] === 8 && hopGuard > 0) {
    hopGuard--;
    seqChainStep(seq, t);
    if (trk.phrase === 0xFF) return;
    trk.prow = 0;
    o = SEQ_SB.PHRASES + trk.phrase * 64 + trk.prow * 4;
  }
  const row = { note: b[o], instr: b[o + 1] };
  trk.cmd = b[o + 2];
  trk.cval = b[o + 3];
  trk.dlyCnt = 0xFF;
  trk.arpPh = 0;
  trk.retPer = 0;
  if (row.instr !== 0xFF) trk.instr = row.instr;
  const consumed = seqCmdPre(seq, t, row);
  if (row.note) {
    if (row.note === SEQ_NOTE_OFF) seq.koffMask |= 1 << t;
    else if (!consumed) seqTriggerNote(seq, t, row.note);
  }
  seqCmdPost(seq, t);
}

// ---- per-tick fx (delay, kill, retrig, slide, arp, vibrato, tremolo) ---------
function seqTrackFx(seq, t) {
  const trk = seq.tracks[t];
  if (trk.phrase === 0xFF) return;
  if (trk.dlyCnt !== 0xFF) {
    trk.dlyCnt = (trk.dlyCnt - 1) & 0xFF;
    if (trk.dlyCnt === 0) {
      trk.dlyCnt = 0xFF;
      seqTriggerNote(seq, t, trk.dlyNote);
    }
  }
  if (trk.killCnt !== 0xFF) {
    trk.killCnt = (trk.killCnt - 1) & 0xFF;
    if (trk.killCnt === 0) {
      trk.killCnt = 0xFF;
      seq.koffMask |= 1 << t;
    }
  }
  if (trk.retPer && --trk.retCnt === 0) {
    trk.retCnt = trk.retPer;
    seq.konMask |= 1 << t;
  }
  if (trk.slRate) seqFxSlide(seq, t);
  if (trk.cmd === 1) seqFxArp(seq, t);
  else if (trk.vib) seqFxVib(seq, t);
  if (trk.trm) seqFxTrm(seq, t);
}

function seqFxSlide(seq, t) {
  const trk = seq.tracks[t];
  const step = trk.slRate * 4, target = trk.slT;
  let p = trk.pitch;
  if (p === target) { trk.slRate = 0; return; }
  if (p > target) {
    p -= step;
    if (p < target) p = target;
  } else {
    p += step;
    if (p > target) p = target;
  }
  trk.pitch = p & 0xFFFF;
  if (p === target) {
    trk.slRate = 0;
    trk.note = trk.slNote;
  }
  seq.trig.voice = t;
  seqPitchWrite(seq, trk.pitch);
}

function seqFxArp(seq, t) {
  const trk = seq.tracks[t];
  trk.arpPh = trk.arpPh + 1 >= 3 ? 0 : trk.arpPh + 1;
  const ofs = trk.arpPh === 0 ? 0
    : trk.arpPh === 1 ? trk.cval >> 4 : trk.cval & 0x0F;
  let n = trk.note + ofs;
  if (n >= SEQ_NOTE_MAX) n = SEQ_NOTE_MAX - 1;
  seq.trig.voice = t;
  seqTrackTuneLoad(seq, t);
  seqPitchWrite(seq, seqPitchCalc(seq, n));
}

function seqFxVib(seq, t) {
  const trk = seq.tracks[t];
  trk.vibPh = (trk.vibPh + (trk.vib >> 4)) & 0xFF;
  let tri = trk.vibPh & 0x1F;
  if (tri >= 0x10) tri ^= 0x1F;
  const centred = tri - 8;
  const prod = Math.abs(centred) * (trk.vib & 0x0F);
  let p = trk.pitch + (centred < 0 ? -(prod << 2) : prod << 2);
  seq.trig.voice = t;
  seqPitchWrite(seq, p & 0xFFFF);
}

function seqFxTrm(seq, t) {
  const trk = seq.tracks[t];
  trk.trmPh = (trk.trmPh + (trk.trm >> 4)) & 0xFF;
  let tri = trk.trmPh & 0x1F;
  if (tri >= 0x10) tri ^= 0x1F;
  const dip = (tri * (trk.trm & 0x0F)) >> 1;
  const side = lvl => {
    if (lvl < 0) return -Math.max(0, -lvl - dip);
    return Math.max(0, lvl - dip);
  };
  dspWrite(seq.dsp, t * 16 + 0, side(trk.voll) & 0xFF);
  dspWrite(seq.dsp, t * 16 + 1, side(trk.volr) & 0xFF);
}

// ---- per-tick table step: V / TSP / one CMD (zero = no change) ---------------
function seqTrackTable(seq, t) {
  const trk = seq.tracks[t], b = seq.block;
  if (trk.tbl === 0xFF) return;
  if (trk.tblSpd === 0) {               // note-sync: pending steps only
    if (!trk.tblCnt) return;
    trk.tblCnt = 0;
  } else {
    if (--trk.tblCnt) return;
    trk.tblCnt = trk.tblSpd;
  }
  const o = SEQ_SB.TABLES + trk.tbl * 64 + trk.tblRow * 4;
  const v = b[o];
  if (v) {                              // V: retarget the live level, X-style
    trk.voll = v & 0x7F;
    trk.volr = v & 0x7F;
    seqVolWrite(seq, t);
  }
  const tsp = b[o + 1];
  if (tsp) {                            // TSP: semitones off the playing note
    let n = (trk.note + i8(tsp)) & 0xFF;
    if (n >= SEQ_NOTE_MAX) n = SEQ_NOTE_MAX - 1;
    seq.trig.voice = t;
    seqTrackTuneLoad(seq, t);
    const p = seqPitchCalc(seq, n);
    seqPitchWrite(seq, p);
    trk.pitch = p & 0xFFFF;             // the new base: vibrato rides it
  }
  seqTableExec(seq, t, b[o + 2], b[o + 3]);
  trk.tblRow = (trk.tblRow + 1) & 0x0F;
}

function seqTableExec(seq, t, cmd, val) {
  const trk = seq.tracks[t];
  if (!cmd || cmd === 4 || cmd === 9 || cmd === 10) return;  // D/I/J inert
  if (cmd === 8) {                      // H hops the table itself
    trk.tblRow = (val - 1) & 0x0F;
    return;
  }
  const savedCmd = trk.cmd, savedVal = trk.cval;
  trk.cmd = cmd;
  trk.cval = val;
  seqCmdPre(seq, t, { note: 0, instr: 0xFF });
  seqCmdPost(seq, t);
  trk.cmd = savedCmd;
  trk.cval = savedVal;
}

// ---- one engine tick -------------------------------------------------------------
function seqTick(seq) {
  seq.konMask = 0;
  seq.koffMask = 0;
  if (seq.tickwait) seq.tickwait--;
  else {
    const g = seq.block[SEQ_SB.GROOVES + (seq.gpos & 1)] || 6;
    seq.tickwait = g - 1;
    seq.gpos ^= 1;
    for (let t = 0; t < 8; t++) seqTrackRow(seq, t);
    seq.row = seq.tracks[0].prow;
  }
  for (let t = 0; t < 8; t++) {
    seqTrackFx(seq, t);
    seqTrackTable(seq, t);
  }
  seq.halted = seq.tracks.every(trk => trk.phrase === 0xFF);
}

// tick + render its samples. The KOF latch is held for two DSP samples
// before dropping (the driver serialises key events the same way).
function seqTickRun(seq) {
  seqTick(seq);
  const d = seq.dsp;
  const n = seq.samplesPerTick;
  const outL = new Int16Array(n), outR = new Int16Array(n);
  let o = 0;
  if (seq.koffMask) {
    dspWrite(d, 0x5C, seq.koffMask);
    const pre = dspRun(d, 2);
    outL.set(pre.l, 0);
    outR.set(pre.r, 0);
    o = 2;
    dspWrite(d, 0x5C, 0);
  }
  if (seq.konMask) {
    dspWrite(d, 0x4C, seq.konMask);
    seq.konCount++;
  }
  const g = dspRun(d, n - o);
  outL.set(g.l, o);
  outR.set(g.r, o);
  return { l: outL, r: outR };
}

// offline render: seconds of audio (stops early only if every track halts)
function seqRender(block, pool, seconds, opts) {
  const seq = seqNew(block, pool, opts);
  const total = Math.round(seconds * 32000);
  const l = new Int16Array(total), r = new Int16Array(total);
  let o = 0;
  while (o < total) {
    const g = seqTickRun(seq);
    const n = Math.min(g.l.length, total - o);
    l.set(g.l.subarray(0, n), o);
    r.set(g.r.subarray(0, n), o);
    o += n;
    if (seq.halted) break;
  }
  return { l: l.subarray(0, o), r: r.subarray(0, o), rate: 32000 };
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
  const assertThrows = (fn, text, m) => {
    try { fn(); } catch (e) {
      assert(!text || e.message.includes(text), m + ' error message');
      return;
    }
    assert(false, m + ' did not throw');
  };
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
  assertThrows(() => poolParse(pool.slice(0, 20)), 'truncated', 'truncated pool');
  assertThrows(() => poolBuild([{ name: 'BAD', loopBlock: 2,
    brr: new Uint8Array(9) }]), 'loop', 'bad pool loop');

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
  const damaged = srm.slice();
  damaged[0x11] = 0xFF; damaged[0x12] = 0x7F;
  assert(!srmParse(damaged).slots[0].ok, 'srm out-of-range slot rejected');
  assertThrows(() => srmErase(damaged, 0), 'corrupt', 'corrupt srm rewrite');
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
  assertThrows(() => rleUnpack(Uint8Array.of(0x7F), 8), 'RLE', 'truncated RLE');
  const exactAram = aramBudget([{ brr: new Uint8Array(0xFF00 - 0x1209) }]);
  assert(exactAram.maxEdl === 0 && exactAram.overBy === 0,
    'exact ARAM capacity fits EDL 0');
  assert(findMarker(Uint8Array.from([0, 1, 83, 78, 68, 74]), 'SNDJ') === 6,
    'marker ending at final byte');
  // tuning matches the ROM tables
  assert(pitchForNote(48) === 0x0800, 'C-4 pitch');
  assert(pitchForNote(52) === 0x0A14, 'E-4 pitch');
  assert(pitchForNote(60) === 0x1000, 'C-5 pitch');
  // A root-keyed A4 sample prepared for native console C-5 must land on
  // standard C5 (523.251 Hz), including BRR-block loop rounding residual.
  const sfLoopLen = 3200;
  const sfPcm = Array.from({ length: sfLoopLen }, (_, i) =>
    Math.round(Math.sin(2 * Math.PI * 440 * i / 32000) * 20000));
  const sfPrep = sf2Melodic({ name: 'A4 fixture', pcm: sfPcm, rate: 32000,
    root: 69, corr: 0, loop: [0, sfLoopLen] }, 0);
  const sfFactor = (sfPrep.pcm.length - sfPrep.loopBlock * 16) / sfLoopLen;
  const sfTune = sfPrep.tuneSemis + sfPrep.tuneFine / 256;
  const sfHz = 440 / sfFactor * Math.pow(2, sfTune / 12);
  assert(Math.abs(1200 * Math.log2(sfHz / 523.2511306)) < 1,
    'SF2 root bakes to C-5 (' + sfHz.toFixed(3) + ' Hz)');
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

  // ---- reference sequencer ----
  // a minimal song: track 0 -> chain 0 -> phrase 0; C-4 on instrument 0
  // at row 0, X accent at row 4, OFF at row 8, T tempo at row 12
  const sblk = new Uint8Array(BLOCK_SZ);
  sblk.fill(0xFF, 0, 0x0400);                    // song grid empty
  for (let i = 0x1700; i < 0x2300; i += 2) sblk[i] = 0xFF;
  for (let i = 0x2301; i < 0x5300; i += 4) sblk[i] = 0xFF;
  sblk[0x1000] = 6; sblk[0x1001] = 6;            // groove 6/6
  sblk[0x1600 + 2] = 0xD7;                       // header magic
  sblk[0x1600 + 18] = 150;                       // TMPO
  sblk[0x1600 + 7] = 0xFF;                       // EON mask open
  sblk[0x1600 + 19] = 0x7F;                      // FLAT room
  sblk[0x0400] = 0x00;                           // instr 0: SMP, sample 0
  sblk[0x0401] = 0x00;
  sblk[0x0402] = 0x2F; sblk[0x0403] = 0xCA;      // factory ADSR
  sblk[0x0404] = 0x50; sblk[0x0405] = 0x50;
  sblk[0x040C] = 0xFF; sblk[0x040D] = 0x01;      // no table
  sblk[0x0000] = 0x00;                           // track 0 row 0 -> chain 0
  sblk[0x1700] = 0x00;                           // chain 0 step 0 -> phrase 0
  const ph = 0x2300;
  sblk[ph] = 49; sblk[ph + 1] = 0;               // row 0: C-4, instr 0
  sblk[ph + 16] = 0; sblk[ph + 17] = 0xFF;       // row 4: X 40 (no note)
  sblk[ph + 18] = 24; sblk[ph + 19] = 0x40;
  sblk[ph + 32] = 97;                            // row 8: OFF
  sblk[ph + 50] = 20; sblk[ph + 51] = 200;       // row 12: T 200
  const spool = [{ name: 'PAD', loopBlock: 0, tuneSemis: 0, tuneFine: 0, brr }];
  const seq = seqNew(sblk, spool);
  assert(seq.poolMap[0] === 1, 'seq residency mapped sample 0 to slot 1');
  assert(seq.aram[0x1004] === 0x09 && seq.aram[0x1005] === 0x12,
    'seq directory entry 1 starts at $1209');
  assert((seq.aram[0x1209 + brr.length - 9] & 0x02) === 0x02,
    'seq forced LOOP on the END block');
  assert(seq.samplesPerTick === 532, 'seq tempo 150 -> 532 samples/tick');
  seqTick(seq);                                  // tick 1 = phrase row 0
  assert(seq.konMask === 0x01, 'seq row 0 KONs voice 0');
  assert(seq.dsp.regs[0x04] === 1 && seq.dsp.regs[0x02] === 0x00 &&
    seq.dsp.regs[0x03] === 0x08, 'seq C-4 pitch $0800 on SRCN 1');
  assert(seq.dsp.regs[0x05] === 0xAF && seq.dsp.regs[0x00] === 0x50,
    'seq instrument env + volume applied');
  for (let k = 0; k < 24; k++) seqTick(seq);     // through row 4 (tick 25)
  assert(seq.row === 4 && seq.dsp.regs[0x00] === 0x40,
    'seq X accent retargeted the live level at row 4');
  let sawKoff = false;
  for (let k = 0; k < 24; k++) {                 // through row 8
    seqTick(seq);
    if (seq.koffMask & 1) sawKoff = true;
  }
  assert(sawKoff && seq.row === 8, 'seq OFF row keyed voice 0 off');
  for (let k = 0; k < 24; k++) seqTick(seq);     // through row 12
  assert(seq.samplesPerTick === 400, 'seq T 200 -> 400 samples/tick');
  // audio end-to-end: the first half second must actually sound
  const ren = seqRender(sblk, spool, 0.5);
  assert(ren.l.length === 16000, 'seq render length');
  let rpeak = 0;
  for (let i = 0; i < 6000; i++) rpeak = Math.max(rpeak, Math.abs(ren.l[i]));
  assert(rpeak > 2000, 'seq render is audible (' + rpeak + ')');
  let rtail = 0;                                 // OFF row 8 lands ~0.45 s in
  for (let i = 15000; i < 16000; i++) {
    rtail = Math.max(rtail, Math.abs(ren.l[i]));
  }
  assert(rtail < rpeak, 'seq OFF released the voice (' + rtail + ')');
  assert(karpEntry(48, 1).pitch > 0x0100 && karpEntry(48, 2).i0 <= 6,
    'karp tuning entries sane');

  console.log('sndj.js selftest: OK (BRR SNR ' + snr.toFixed(1) + ' dB, ' +
    'empty song ' + packed.length + ' bytes, dsp voice peak ' + peak +
    ', seq peak ' + rpeak + ')');
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
  seqNew, seqTick, seqTickRun, seqRender, seqAramBuild, karpEntry,
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = SNDJ;
  if (process.argv.includes('--selftest') || require.main === module) selftest();
} else if (typeof window !== 'undefined') {
  window.SNDJ = SNDJ;
}
