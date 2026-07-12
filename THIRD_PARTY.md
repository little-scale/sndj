# Third-party material

sndj does not distribute third-party sample recordings or SoundFonts.

The default ROM uses a small deterministic placeholder sample pool generated
by `tools/sndj_pool.py` from mathematical waveforms and seeded noise. It exists
to keep clean checkouts buildable and the audio/test paths exercised; it is not
intended to be the final musical factory library.

Users may place their own material under `samples/`, `soundfonts/`, or export a
`factory/factory.sndjfact` with the browser patcher. Those paths are ignored by
Git. Users are responsible for ensuring that they have permission to use and
redistribute any material they add to ROMs or factory packs.

Project code, documentation, generated placeholder audio, and original artwork
are provided under the repository's MIT license unless a file states otherwise.
