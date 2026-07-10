# Releasing

Cutting a release. The first release is **v0.1**; versions increment by
**0.01** (v0.1 → v0.11 → v0.12 → …). The build stamps the version + git
hash into the ROM (boot splash), so the released binary, the git tag,
and the on-screen stamp must all agree.

## Steps

1. **Bump the version** in `src/main.asm`:

   ```
   .DEFINE VERSION "0.12"      ; +0.01
   ```

   The `Makefile` derives every filename from it (`sndj-0.12-<hash>.sfc`
   dev copies, `make dist` → `sndj-0.12.sfc`), so nothing else needs
   editing.

2. **Add a `CHANGELOG.md` section** for the new version (newest on top).
   Summarise from `git log <prev-tag>..HEAD --oneline`.

3. **Commit _and push_** — both, before creating the release:

   ```
   git add -A && git commit -m "release: bump to v0.12 + changelog"
   git push origin main
   ```

   ⚠ **Push first.** `gh release create --target main` tags the *remote*
   branch tip; if you haven't pushed, the tag lands on the stale HEAD
   and won't match the ROM stamp.

4. **Build clean** (tree must be clean → no `+` on the stamp), and run
   the full gate:

   ```
   rm -rf build && make && make test && make check && make shot-diff
   make dist                   # -> build/sndj-0.12.sfc
   ```

   Sanity-check the stamp matches `git rev-parse --short=7 HEAD`.

5. **Write release notes** (highlights + a link to `CHANGELOG.md`), then:

   ```
   gh release create v0.12 build/sndj-0.12.sfc \
     --title "sndj v0.12" --notes-file notes.md --target main
   ```

6. **Verify** the tag matches HEAD:

   ```
   git rev-parse HEAD
   git ls-remote --tags origin v0.12
   ```

   If they differ, you forgot step 3's push —
   `gh release delete v0.12 --cleanup-tag --yes`, push, re-create.

## Notes

- The **release asset** uses the clean name `sndj-0.12.sfc`; the hash
  lives inside the ROM, not the filename (a stable name keeps emulator
  `.srm` battery files portable across builds).
- The README Releases callout points at `/releases/latest` — no
  per-release edit needed.
- Don't rewrite a published tag/ROM to include later fixes — cut a new
  0.01 instead, so a given version always means one exact binary.
- Hardware items still awaiting bring-up (sync/MIDI rigs, FXPak SRAM
  matrix — CLAUDE.md §4.4) should be called out in the notes until
  they're verified.
