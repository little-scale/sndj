# factory/

`factory.sndjfact` is **the** factory: the sample pool, drum kits, boot
instruments, FIR presets and palettes every `make` bakes into the ROM
(and what a fresh song's NEW seeds from).

To change it: open `user-tools/patcher.html`, drop a built `sndj.sfc`,
edit (POOL / BOOT / KITS tabs), **export factory**, and replace this
file with the download. `make` picks it up; `make check` must stay
green (a few checks assert factory facts — pitch references, the
boot-resident set — and say so when the content moves under them).

Format: `SNDJFACT` v4 — pool image + 16 kits (1 KB) + 8 boot
instruments (24 B) + FIR presets (64 B) + palettes (128 B).
