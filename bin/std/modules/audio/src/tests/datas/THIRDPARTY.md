# Audio fixture sources and licences

`aac-lc-stereo-44100.aac` is a one-second stereo AAC-LC stream generated for this repository.
Its input is a mathematically generated 440 Hz left-channel sine and 660 Hz right-channel sine,
both with a 512-sample attack, so it contains no third-party recording. It was encoded at
128 kbit/s with glint commit `77738f3ed9b15f627196cc5bbd7f6406814ba2fb`.

- SHA-256: `e002c74b334f68808367d2a0881afa9928efed09f1433a6ead214e452d117b8f`
- License: same as this repository.

`aac-lc-5.1-48000.aac`, `ac3-5.1-48000.ac3`, and `eac3-5.1-48000.eac3` are half-second 48 kHz
5.1 streams generated for this repository with FFmpeg
`N-126262-g1019f8f036-20260824`. Their six synthetic inputs are 300, 400, 500, 600, 700, and
800 Hz sine waves at amplitude 0.18, assigned to FL, FR, FC, LFE, BL, and BR. They contain no
third-party recording. AAC uses 192 kbit/s; AC-3 and E-AC-3 use 384 kbit/s. FFmpeg generated only
the fixtures and is not a build or runtime dependency.

- `aac-lc-5.1-48000.aac` SHA-256: `3bc938af79954ea01409ea092325bdb48abdf945fb8e987818dc03f1360d7b16`
- `ac3-5.1-48000.ac3` SHA-256: `62398152fe980bbcb9dc149e4ad31aaceb13dd7bc0462c1ce3eeb48a8d54b685`
- `eac3-5.1-48000.eac3` SHA-256: `828691e88bdacef3ce7ea18147463a7dfb4b5b6f52b6a7234d4ca5aa6e7fe21d`
- License: same as this repository.

`eac3-stereo-48000.eac3` is a half-second 128 kbit/s E-AC-3 stream made by the same FFmpeg
build from synthetic 440 Hz left and 660 Hz right sine waves. Its encoder output uses standard
coupling and rematrixing, complementing the multichannel fixture.

- SHA-256: `4b5cfef8680e681e82745a30abe5166fbfc316908b504f13b8e487da8e78ef4c`
- License: same as this repository.

`flac-stereo-44100.flac` and `flac-5.1-48000.flac` are FLAC streams generated for this repository
with PyAV 17.1 from mathematically generated sine waves, so they contain no third-party recording.
The stereo file is one second of a 440 Hz left and 660 Hz right sine at 44.1 kHz; the multichannel
one is the same half-second six-tone 5.1 input as the fixtures above. The encoder chose 4,608
sample frames per FLAC frame.

`flac-stereo-44100.pcm` and `flac-5.1-48000.pcm` are the interleaved 16-bit inputs those two files
were encoded from. FLAC is lossless, so they are what a correct decode must produce, byte for byte,
and they were not produced by this module.

- `flac-stereo-44100.flac` SHA-256: `079c942489f90df0093df3f80eae4dafdd796a536a21b1d50169d615c1c49f53`
- `flac-stereo-44100.pcm` SHA-256: `39c52cb32e0e8ca25d7f4af7565e37f7794bdd8dba7adc16890645a0a5c3073c`
- `flac-5.1-48000.flac` SHA-256: `c6bf538b517d18795cccd5317f44f1c0b996da783ce12f9ee93cde122a98d3a2`
- `flac-5.1-48000.pcm` SHA-256: `e2038b86051b34518ae4b5ce35db8d7d23cdcade1c846e066a0c19fe499e63e6`
- License: same as this repository.
