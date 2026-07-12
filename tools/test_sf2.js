#!/usr/bin/env node
// test_sf2.js — the JS SF2 pipeline must produce byte-identical BRR
// (and identical loop/tune) to the python factory pipeline.
'use strict';
const fs = require('fs');
const S = require('../user-tools/sndj.js');

const fixture = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const samples = S.sf2Parse(new Uint8Array(fs.readFileSync(fixture.font)));

let fails = 0;
for (const c of fixture.cases) {
  const s = samples.find(x => x.name === c.sample);
  const prep = c.kind === 'melodic' ? S.sf2Melodic(s, c.arg) : S.sf2Oneshot(s, c.arg);
  const brr = S.brrEncode(prep.pcm, prep.loopBlock);
  const want = Uint8Array.from(c.brr);
  let ok = prep.loopBlock === c.loopBlock &&
    prep.tuneSemis === c.tuneSemis && prep.tuneFine === c.tuneFine &&
    brr.length === want.length;
  if (ok) for (let i = 0; i < brr.length; i++) {
    if (brr[i] !== want[i]) { ok = false; break; }
  }
  console.log((ok ? 'PASS' : 'FAIL') + ' sf2 mirror: ' + c.sample +
    ' (' + c.kind + ', ' + (c.brr.length) + ' B)');
  if (!ok) fails++;
}
if (fails) { console.error('test_sf2: ' + fails + ' mismatches'); process.exit(1); }
console.log('test_sf2: OK');
