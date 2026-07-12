# factory/

An optional local `factory.sndjfact` is **the** factory: the sample pool, drum
kits, boot instruments, FIR presets and palettes `make` bakes into the ROM
(and what a fresh song's NEW seeds from). Factory files are ignored by Git so
copyrighted or otherwise private audio cannot accidentally ship in the project.

Without a local factory file, the build uses a deterministic synthesized
placeholder pool and matching defaults. It keeps the ROM useful and the full
test path active, but is deliberately modest until a curated, redistributable
factory pack is ready.

To change it: open `user-tools/patcher.html`, drop a built `sndj.sfc`,
edit (POOL / BOOT / KITS tabs), **export factory**, and replace this
file with the download. `make` picks it up locally; `make check` must stay
green (a few checks assert factory facts — pitch references, the
boot-resident set — and say so when the content moves under them).

Format: `SNDJFACT` v4 — pool image + 16 kits (1 KB) + 8 boot
instruments (24 B) + FIR presets (64 B) + palettes (128 B).

Only distribute a factory pack when every included source has documented
redistribution and derivative-work permission. See `../THIRD_PARTY.md`.
