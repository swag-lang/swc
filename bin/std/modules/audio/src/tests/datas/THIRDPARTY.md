# Audio fixture sources and licences

`aac-lc-stereo-44100.aac` is a one-second stereo AAC-LC stream generated for this repository.
Its input is a mathematically generated 440 Hz left-channel sine and 660 Hz right-channel sine,
both with a 512-sample attack, so it contains no third-party recording. It was encoded at
128 kbit/s with glint commit `77738f3ed9b15f627196cc5bbd7f6406814ba2fb`.

- SHA-256: `e002c74b334f68808367d2a0881afa9928efed09f1433a6ead214e452d117b8f`
- License: same as this repository.

`dts-5.1-48000.dts` is a half-second 1,509 kbit/s DTS Core stream generated for this repository
with dcaenc commit `68ed0d6d370268f04c22cadc9c8fc54a479958ab`. Its six synthetic inputs are
300, 400, 500, 60, 700, and 800 Hz sine waves at amplitude 12,000 in signed 16-bit PCM, assigned
to FL, FR, FC, LFE, BL, and BR. It contains no third-party recording. dcaenc generated only the
fixture and is not a build or runtime dependency.

- SHA-256: `6de5bc7205bd12bb36948215f8bc61cc8230a183670e5389b6b532bb1a04754e`
- License: same as this repository.

`dts-5.1-48000-14be.dts` contains the same coded frames repacked into the format's 14-bit
big-endian transport representation. The repacking changes no coded audio and introduces no
additional source material.

- SHA-256: `8e49755616815440387693f74fbd354fba0561ba97312ee7519426527a4d5757`
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

The ten `mp3-*.mp3` files are MPEG Layer III streams generated for this repository with
libmp3lame through PyAV 17.1, from mathematically generated inputs, so they contain no third-party
recording. There is one per sampling frequency of the three MPEG versions, because each frequency
selects a different scalefactor band table and a wrong one is silent about itself:
`mp3-stereo-44100` (joint stereo, 128 kbit/s, with an ID3v2 prologue, an encoder information
frame, and a stated encoder delay) and `mp3-mono-48000`, `mp3-mono-32000` for MPEG-1;
`mp3-mono-22050`, `mp3-mono-24000`, `mp3-mono-16000` for MPEG-2; and `mp3-mono-12000`,
`mp3-mono-11025`, `mp3-mono-8000` for MPEG-2.5. All but the first carry no tag of any kind.

`mp3-transient-44100.mp3` is half a second of clicks over a noise floor with two sweeping tones,
encoded at 320 kbit/s. Its content is what makes an encoder switch to short and mixed blocks and
fill the escape-coded Huffman tables with values above fifteen; a steady tone reaches neither.

The matching `.pcm` files are those streams decoded by FFmpeg to interleaved 16-bit samples, which
is what the tests compare against. Layer III is lossy, so the comparison is a bounded root mean
square difference rather than an equality.

- `mp3-stereo-44100.mp3` SHA-256: `c09ea20f1d875695c574a01de984b1c727798099280e6d4130add367cf3d9f45`
- `mp3-mono-48000.mp3` SHA-256: `08359a63d96e8e941ad3bda36b4fa2f66dfa8cf8916a339c1f8d16592a239749`
- `mp3-mono-32000.mp3` SHA-256: `7252de654fc40982e3fccbcdceefc49546f9e8516453f114ebaf8abc3f691805`
- `mp3-mono-24000.mp3` SHA-256: `94c606972a80b3153b8e20aa71007e8dec12dd8c77b10d196b5ee18a0316043b`
- `mp3-mono-22050.mp3` SHA-256: `4bee25151393130c8eace7060123be26c6768f7ab758b924ba14fdf38755ac99`
- `mp3-mono-16000.mp3` SHA-256: `a834631631d8e8cbeb9a548fe33651ac52f0f5b0febb96c3463fecf13a6510bf`
- `mp3-mono-12000.mp3` SHA-256: `8ee0fcbf9b51406c0c0a94772735f6c4c4999cdba66a798fb2b9406340ef4ffe`
- `mp3-mono-11025.mp3` SHA-256: `ba3e6ba30c1315fe022108a74902e409d2da9a285a85912328a13bd538c2999a`
- `mp3-mono-8000.mp3` SHA-256: `54793986597864888120dfa127f9c7251052a754b75fae7d0405a8e8b076c145`
- `mp3-transient-44100.mp3` SHA-256: `3346c3b37db162740577ecec40b350e4df34c351789e79fb407b7cd3d8571e12`
- License: same as this repository.
