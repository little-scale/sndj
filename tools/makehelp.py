#!/usr/bin/env python3
"""help.txt -> build/help.inc — the sndj HELP screen, built from data
not code (the genmddj makehelp.py model).

Data the renderer (src/helpscr.asm) expects, all in bank 6:
  HELP_PAGES        .DEFINE — page count
  help_pgtab:       .DW per-page offsets into help_data
  help_data:        byte stream per page:
                      $FF        end of page
                      $00        blank row
                      $01        the live @VERSION stamp row
                      $02 s.. 0  plain line (NUL-terminated)
                      $03 s.. 0  title line (inverted; source had ':')

Rules enforced (build fails, never clips): UPPERCASE only, <= 30
chars/line, <= 22 rows/page. @COMMANDS1 / @COMMANDS2 insert the
command reference from tools/commands.csv (A-M / N-Z).
"""
import csv
import sys

WIDTH = 30
ROWS = 20


def command_lines(half):
    rows = {}
    with open('tools/commands.csv') as f:
        for r in csv.DictReader(f):
            rows[r['letter'].strip()] = (r['name'].strip(), r['short'].strip())
    out = []
    for c in sorted(rows):
        if (half == 1) == (c <= 'M'):
            name, short = rows[c]
            out.append(f"{c}  {name:<7}{short}")
    return out


def main(src, dst):
    pages = [[]]
    for raw in open(src):
        line = raw.rstrip('\n')
        if line.startswith('#'):
            continue
        if line.strip() == '---':
            pages.append([])
            continue
        if line.strip() == '@COMMANDS1':
            pages[-1].extend(command_lines(1))
            continue
        if line.strip() == '@COMMANDS2':
            pages[-1].extend(command_lines(2))
            continue
        pages[-1].append(line.rstrip())
    # trim leading/trailing blank rows per page
    for p in pages:
        while p and not p[0]:
            p.pop(0)
        while p and not p[-1]:
            p.pop()
    pages = [p for p in pages if p]
    lines = ["; generated from help.txt — do not edit",
             f".DEFINE HELP_PAGES {len(pages)}",
             "help_pgtab:"]
    offsets, blob = [], []
    for p in pages:
        if len(p) > ROWS:
            sys.exit(f"makehelp: page has {len(p)} rows (max {ROWS})")
        offsets.append(len(blob))
        for ln in p:
            if not ln:
                blob.append(0x00)
                continue
            if ln.strip() == '@VERSION':
                blob.append(0x01)
                continue
            if len(ln) > WIDTH:
                sys.exit(f"makehelp: line too wide ({len(ln)}): {ln!r}")
            if ln != ln.upper():
                sys.exit(f"makehelp: lowercase in: {ln!r}")
            if '"' in ln:
                sys.exit(f"makehelp: quote in: {ln!r}")
            blob.append(0x03 if ':' in ln else 0x02)
            blob.extend(ord(c) for c in ln)
            blob.append(0)
        blob.append(0xFF)
    for o in offsets:
        lines.append(f"    .DW {o}")
    lines.append("help_data:")
    for i in range(0, len(blob), 16):
        lines.append("    .DB " + ", ".join(f"${b:02X}" for b in blob[i:i + 16]))
    lines.append("")
    open(dst, 'w').write("\n".join(lines))
    print(f"makehelp: {len(pages)} pages, {len(blob)} bytes")


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
