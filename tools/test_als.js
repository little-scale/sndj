#!/usr/bin/env node
// test_als.js — fixture tests for user-tools/als2sndj.html's conversion
// core (the DOM-free top half of its <script> block). Run from the repo
// root by `make test`.
'use strict';
const fs = require('fs');
const path = require('path');
const SNDJ = require(path.join(__dirname, '..', 'user-tools', 'sndj.js'));

const html = fs.readFileSync(
  path.join(__dirname, '..', 'user-tools', 'als2sndj.html'), 'utf8');
const m = html.match(/<script>([^]*?)<\/script>/);
if (!m) { console.error('test_als: no inline <script> in als2sndj.html'); process.exit(1); }
// document is undefined in this scope, so the UI half self-skips
const A = new Function('window', m[1] + '\nreturn ALS2SNDJ;')({ SNDJ });

const assert = (c, msg) => {
  if (!c) { console.error('test_als FAIL: ' + msg); process.exit(1); }
};
const OPT = { vel: true, offs: true };

// ---- blockNew: a NEW-song equivalent --------------------------------------
{
  const d = A.blockNew('My Song!', 128);
  assert(d.length === A.BLOCK_SZ, 'block size');
  assert(d[A.O_HEADER + 2] === 0xD7, 'header magic');
  assert(d[A.O_HEADER + A.SH_BPM] === 128, 'BPM written');
  assert(String.fromCharCode(...d.slice(A.O_HEADER + A.SH_NAME,
    A.O_HEADER + A.SH_NAME + 8)) === 'MY SONG ', 'name sanitised');
  assert(d[A.O_SONG] === 0xFF && d[A.O_SONG + 1023] === 0xFF, 'song grid empty');
  assert(d[A.O_CHAINS] === 0xFF && d[A.O_CHAINS + 1] === 0, 'chain empty pair');
  assert(d[A.O_PHRASES] === 0 && d[A.O_PHRASES + 1] === 0xFF, 'phrase row empty');
  assert(d[0x1000] === 6 && d[0x100F] === 6, 'groove 0 = 6 ticks');
  const i3 = A.O_INSTR + 3 * 16;
  assert(d[i3] === 0 && d[i3 + 1] === 3 && d[i3 + 2] === 0x2F &&
    d[i3 + 3] === 0xCA && d[i3 + 4] === 0x50 && d[i3 + 12] === 0xFF &&
    d[i3 + 13] === 1, 'instrument 3 = SMP on sample 3');
  assert(A.blockNew('X', 999)[A.O_HEADER + A.SH_BPM] === 255, 'BPM clamps high');
  assert(A.blockNew('X', 10)[A.O_HEADER + A.SH_BPM] === 80, 'BPM clamps low');
  assert(A.blockNew('X')[A.O_HEADER + A.SH_BPM] === 150, 'BPM defaults to 150');
}

// ---- MML -> block: notes, OFF, velocity, tempo, instrument -----------------
{
  const conv = A.convertMml('t140\nV1 o4 l4 c r8 v8 e8\nV2 o2 @9 c2', OPT);
  assert(conv.bpm === 140, 'MML tempo read');
  assert(conv.st.tracks === 2, 'MML two voices');
  const d = A.buildBlock(conv, 'MMLFIX');
  assert(d[A.O_HEADER + A.SH_BPM] === 140, 'MML tempo -> TMPO');
  assert(d[A.O_SONG + 0] === conv.trackChains[0][0], 'V1 grid row 0');
  assert(d[A.O_SONG + 128] === conv.trackChains[1][0], 'V2 grid row 0 (column-major)');
  const p0 = A.O_PHRASES + conv.chainList[conv.trackChains[0][0]][0] * 64;
  // V1: c4 (MIDI 60 -> note 49, 4 steps), OFF at row 4, rest 2 steps, e8 at row 6
  assert(d[p0] === 49, 'c4 note byte');
  assert(d[p0 + 1] === 0, 'V1 instrument column');
  assert(d[p0 + 2] === A.CMD_X && d[p0 + 3] === 127, 'v15 -> X 7F');
  assert(d[p0 + 4 * 4] === A.NOTE_OFF, 'OFF after c4 + r8');
  assert(d[p0 + 6 * 4] === 53 && d[p0 + 6 * 4 + 3] === Math.round(8 * 127 / 15),
    'e8 note + v8 velocity');
  const p1 = A.O_PHRASES + conv.chainList[conv.trackChains[1][0]][0] * 64;
  assert(d[p1] === 25 && d[p1 + 1] === 9, 'V2 o2 c + @9 instrument');
}

// ---- MML -> block -> MML -> block converges byte-identically ----------------
{
  // no trailing silence (export trims it), so one round trip is exact
  const src = 't120\nV1 o4 l8 c d e f g4 r4 v7 a2\nV2 o3 l4 c r8 g8 c2 & c4';
  const b1 = A.buildBlock(A.convertMml(src, OPT), 'RT');
  const mml = A.mmlFromBlock(b1, true);
  const b2 = A.buildBlock(A.convertMml(mml, OPT), 'RT');
  for (let i = 0; i < A.BLOCK_SZ; i++) {
    assert(b1[i] === b2[i],
      'MML round trip byte ' + i.toString(16) + ': ' + b1[i] + ' != ' + b2[i]);
  }
}
// trailing silence is trimmed on export (lossy once), then stable forever
{
  const src = 'V1 o5 c1 & c1\nV2 o3 l4 c g r2 r1';
  const b1 = A.buildBlock(A.convertMml(src, OPT), 'RT2');
  const b2 = A.buildBlock(A.convertMml(A.mmlFromBlock(b1, true), OPT), 'RT2');
  const b3 = A.buildBlock(A.convertMml(A.mmlFromBlock(b2, true), OPT), 'RT2');
  for (let i = 0; i < A.BLOCK_SZ; i++) {
    assert(b2[i] === b3[i],
      'MML idempotence byte ' + i.toString(16) + ': ' + b2[i] + ' != ' + b3[i]);
  }
}

// ---- MIDI (SMF type 0) -> block --------------------------------------------
{
  // div=4 ticks/quarter (1 tick = a 16th). ch0: C4 vel 100 for 1 beat,
  // then E4 vel 64 for half a beat; tempo meta 120 BPM.
  const trk = [
    0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,   // tempo 500000 us = 120 BPM
    0x00, 0x90, 60, 100,
    0x04, 0x80, 60, 0,
    0x00, 0x90, 64, 64,
    0x02, 0x80, 64, 0,
    0x00, 0xFF, 0x2F, 0x00,
  ];
  const smf = [
    0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 4,
    0x4D, 0x54, 0x72, 0x6B, 0, 0, 0, trk.length, ...trk,
  ];
  const conv = A.convertMidi(new Uint8Array(smf), OPT);
  assert(Math.round(conv.bpm) === 120, 'SMF tempo meta');
  const d = A.buildBlock(conv, 'MIDIFIX');
  const p = A.O_PHRASES + conv.chainList[conv.trackChains[0][0]][0] * 64;
  assert(d[p] === 49 && d[p + 2] === A.CMD_X && d[p + 3] === 100,
    'C4 + velocity 100');
  assert(d[p + 4 * 4] === 53 && d[p + 4 * 4 + 3] === 64, 'E4 at step 4');
  assert(d[p + 6 * 4] === A.NOTE_OFF, 'OFF ends E4 at step 6');
  assert(d[A.O_HEADER + A.SH_BPM] === 120, 'SMF tempo -> TMPO');
}

// ---- .sndj wrap round trip ---------------------------------------------------
{
  const conv = A.convertMml('V1 o4 c d e', OPT);
  const d = A.buildBlock(conv, 'WRAP');
  const file = A.makeSndjFile(d, 'WRAP');
  const back = A.blockFromSndj(file);
  assert(back.name === 'WRAP', '.sndj name');
  for (let i = 0; i < A.BLOCK_SZ; i++) {
    assert(back.block[i] === d[i], '.sndj byte ' + i.toString(16));
  }
}

// ---- pool-limit truncation flags -----------------------------------------
{
  // >192 distinct one-note phrases on one voice overflows the pool
  let mml = 'V1 l1 ';
  for (let i = 0; i < 240; i++) {
    mml += 'o' + (3 + i % 3) + ' v' + (i % 16) + ' ' + 'cdefgab'[i % 7] + ' ';
  }
  const conv = A.convertMml(mml, OPT);
  assert(conv.st.truncated, 'phrase overflow flagged');
  assert(conv.phraseList.length <= 192, 'phrase pool capped');
}

console.log('test_als: OK (blockNew, MML+MIDI import, OFF/velocity/tempo, ' +
  'MML round trip, .sndj wrap, truncation)');
