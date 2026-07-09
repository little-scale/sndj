#!/usr/bin/env node
// test_sf2.js — the JS SF2 pipeline must produce byte-identical BRR
// (and identical loop/tune) to the python factory pipeline.
'use strict';
const fs = require('fs');
const path = require('path');
const S = require('./sndj.js');

const fixture = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const root = path.dirname(__dirname);
const fontDir = path.join(root, 'soundfonts');
const fonts = {};
for (const f of fs.readdirSync(fontDir).sort()) {
  if (!f.toLowerCase().endsWith('.sf2')) continue;
  for (const tag of ['mario_paint', 'super_mario_world']) {
    if (f.toLowerCase().includes(tag) && !fonts[tag]) {
      fonts[tag] = S.sf2Parse(new Uint8Array(fs.readFileSync(path.join(fontDir, f))));
    }
  }
}

let fails = 0;
for (const c of fixture) {
  const smp = fonts[c.tag];
  let s;
  if (c.kind === 'oneshot' && c.preset === 'orchestrahit') {
    s = smp.find(x => x.name === 'orchestrahit');
  } else if (c.kind === 'oneshot') {
    s = smp.find(x => x.preset === c.preset);
  } else {
    s = smp.find(x => x.loop && x.preset === c.preset);
  }
  const prep = c.kind === 'melodic' ? S.sf2Melodic(s, c.arg) : S.sf2Oneshot(s, c.arg);
  const brr = S.brrEncode(prep.pcm, prep.loopBlock);
  const want = Uint8Array.from(c.brr);
  let ok = prep.loopBlock === c.loopBlock &&
    prep.tuneSemis === c.tuneSemis && prep.tuneFine === c.tuneFine &&
    brr.length === want.length;
  if (ok) for (let i = 0; i < brr.length; i++) {
    if (brr[i] !== want[i]) { ok = false; break; }
  }
  console.log((ok ? 'PASS' : 'FAIL') + ' sf2 mirror: ' + c.tag + '/' +
    c.preset + ' (' + c.kind + ', ' + (c.brr.length) + ' B)');
  if (!ok) fails++;
}
if (fails) { console.error('test_sf2: ' + fails + ' mismatches'); process.exit(1); }
console.log('test_sf2: OK');
