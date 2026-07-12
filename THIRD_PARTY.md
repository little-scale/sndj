# Third-party material

sndj does not distribute third-party sample recordings or SoundFonts.

`factory/factory.sndjfact` is the copyright-free project factory authored by
little-scale and released under the repository's MIT license. It contains
eight lean original sounds plus blank expansion slots.

If that factory is absent, `tools/sndj_pool.py` generates a fallback from
mathematical waveforms and seeded noise so incomplete source packages remain
buildable and the audio/test paths stay exercised.

Users may place their own material under `samples/`, `soundfonts/`, or export
another factory with the browser patcher. Raw source paths are ignored by Git;
the canonical factory is the sole exception. Users are responsible for ensuring
that they have permission to use and redistribute material they add to ROMs or
personal factory packs.

Project code, documentation, generated placeholder audio, and original artwork
are provided under the repository's MIT license unless a file states otherwise.
