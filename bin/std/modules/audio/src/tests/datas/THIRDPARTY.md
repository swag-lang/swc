# Audio fixture sources and licences

The MP3 mono 48 kHz, Opus stereo 48 kHz and Vorbis stereo 44.1 kHz PCM references
are stored with the Audio tests. Video keeps its own copies.

`aac-lc-stereo-44100.aac` is a one-second stereo AAC-LC stream generated for this repository.
Its input is a mathematically generated 440 Hz left-channel sine and 660 Hz right-channel sine,
both with a 512-sample attack, so it contains no third-party recording. It was encoded at
128 kbit/s with glint commit `77738f3ed9b15f627196cc5bbd7f6406814ba2fb`.

- SHA-256: `e002c74b334f68808367d2a0881afa9928efed09f1433a6ead214e452d117b8f`
- License: same as this repository.

`aac-lc-mono-44100-fdk.aac` and `aac-lc-stereo-44100-transients.aac` are ADTS AAC-LC streams
generated from 26,460 synthetic sample frames at 44.1 kHz. No random seed or recording is used.
For mono, with `t = frame / 44100` and `p = 2*pi*(260*t + 150*t*t)`, round
`(0.8 + 0.2*sin(6*pi*t)) * (5700*sin(p) + 800*sin(3*p) + 200*sin(12*p))` to PCM16.
FDK AAC 2.0.3 encodes this signal at 64 kbit/s with afterburner enabled.

For stereo channel `c` (0 left, 1 right), add sine waves at `440 + 220*c` and `2240 + 370*c`
Hz with amplitudes 1,700 and 260. With `d = (frame - 3551 - 793*c) mod 5011`, add
`A * ((96-d)/96)^2` when `d < 96`, where `A` is 10,500 on the left and -8,800 on the right,
then round to PCM16. FFmpeg 9.1 encodes it at 128 kbit/s with `aac_coder=twoloop`,
`aac_pns=0` and `aac_is=0`, exercising all four window sequences.

The matching `.pcm` files are interleaved little-endian PCM16 from FFmpeg 9.1, including
encoder priming and end padding. The encoders are used only to generate test data.

- `aac-lc-mono-44100-fdk.aac` SHA-256: `e9f16073e30bf47c9c59727d5c5a0de23ce38a4811d0615aff39f1937a87110f`
- `aac-lc-mono-44100-fdk.pcm` SHA-256: `f941af40b2c7204eedae6e33c9d3f361613a8b87b243c4b94b502cfa1df96ee8`
- `aac-lc-stereo-44100-transients.aac` SHA-256: `aadaec3d8bb944401ccaa9af305e335da2437a064729cdb9946dd60fea7f14f6`
- `aac-lc-stereo-44100-transients.pcm` SHA-256: `5dce9cc2164bf7be8464f48e6a917030b0f4cb8e66b5c1610dac96c12726f0a5`
- License: same as this repository.

`aac-lc-stereo-44100-intensity.aac` uses the same synthetic stereo input, FFmpeg 9.1 encoder,
and ADTS settings as the transients fixture above, with intensity stereo enabled (`aac_is=1`).
The `.pcm` file is the matching FFmpeg 9.1 decode to interleaved little-endian PCM16.

- `aac-lc-stereo-44100-intensity.aac` SHA-256: `26d0b2f2ad30f31038db6571cb85d8645de05952c086c083a4ce68f12c9760ac`
- `aac-lc-stereo-44100-intensity.pcm` SHA-256: `9b0f40f4edc4db74b2f07fba3fb2ae2ebe6ae621e1170590a9ab9e1c215a9227`
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

The reduced-rate `ac3-mono-12000`, `ac3-mono-24000`, and `ac3-stereo-22050` fixtures
hold four synthetic sinusoidal frames each. FFmpeg 9.1's AC-3 encoder was adapted
for fixture generation to write legacy bitstream IDs 9 and 10 and use their
corresponding bit allocation at half or quarter rate. The unmodified FFmpeg 9.1
decoder generated the interleaved PCM16 references and verified the frame CRCs.

- `ac3-mono-12000.ac3` SHA-256: `77f3aa7caf3c0aca8c2b6dca7f42bff0194f9f970ca257a1225f3f4ae742920d`
- `ac3-mono-12000.pcm` SHA-256: `46a783e73783466df5ab082b18ad462558ad7f9463a51c3ba22dc3e6593031bb`
- `ac3-mono-24000.ac3` SHA-256: `5d38ff0a5bde4517e83735fa92fc3e859f27598546b2b70adda842cac5a97136`
- `ac3-mono-24000.pcm` SHA-256: `90ceee21a6d6dda8e07e407b011434a2f37617e5bfd8991f566be5d30c3644eb`
- `ac3-stereo-22050.ac3` SHA-256: `8b01ceb286166510420acda07e20dfc0741a7740927ff2564af78738ffeae7c9`
- `ac3-stereo-22050.pcm` SHA-256: `caa63a6ca91c8e8c1410302adf51a84d52c049e0cfedd7d9ea678b53e0d2c5a9`
- License: same as this repository.

`eac3-stereo-48000.eac3` is a half-second 128 kbit/s E-AC-3 stream made by the same FFmpeg
build from synthetic 440 Hz left and 660 Hz right sine waves. Its encoder output uses standard
coupling and rematrixing, complementing the multichannel fixture.

- SHA-256: `4b5cfef8680e681e82745a30abe5166fbfc316908b504f13b8e487da8e78ef4c`
- License: same as this repository.

`eac3-mono-32000.eac3` contains three independent mono frames encoded by FFmpeg 7.1.5
at 96 kbit/s, with a synthetic mix of 337 Hz and 1,219 Hz sine waves at amplitudes
0.16 and 0.05, plus a 2,993 Hz cosine at amplitude 0.03. The `.pcm` reference is
interleaved PCM16 from FFmpeg 9.1.

`eac3-mono-24000.eac3` uses the first three frames of a mono FFmpeg 7.1.5 stream
encoded at 48 kHz and 128 kbit/s, with amplitudes 0.18, 0.07, and 0.03 for the same
tones. Set `fscod=3` and `fscod2=0` to signal 24 kHz with six blocks per frame and
recompute the trailing CRC-16 (polynomial 0x8005). The resulting first tone is
168.5 Hz. Swag checks the reduced-rate geometry and tone. FFmpeg 9.1 does not
decode this sample-rate mode.

- `eac3-mono-32000.eac3` SHA-256: `54a220d56152b3e1ac5b55e7bd13941853a5b2d04a61092c29424261fb1ebbf1`
- `eac3-mono-32000.pcm` SHA-256: `29afb98d5bc0b3a18861c8e7f23f027a00a3805786e96a01f0a56a4d46f4089e`
- `eac3-mono-24000.eac3` SHA-256: `7e3b73b727097dfc5d8a2c59c03e4b1f0960a6d16137a909b62a6b28352386eb`
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

The FLAC sample-width fixtures contain deterministic integer ramps generated for this repository.
libFLAC 1.5.0 encodes 69 frames at compression level 8 with 32-frame blocks and streamable subset
disabled. The expected little-endian PCM16 is calculated from the source ramps by shifting each
sample to 16 bits. FFmpeg 9.1 produces the same interleaved samples.

For each zero-based frame and channel, the ramp combines `(channel + 3) * 1447 * frame` with
`(frame + phase) >> 2` using XOR, shifts the result left by `max(0, bits - 13)`, and wraps it to
the signed source width. Phases for the 4-, 8-, 12-, 20-, 31-, and 32-bit multichannel files are
0, 1, 2, 3, 3, and 2. If `(frame + channel) % 37 == 0`, the sample is the signed minimum.
Otherwise, if `(frame + 2 * channel) % 107 == 0`, it is the signed maximum. At other positions
where `(phase + channel) % 2 == 1`, the ramp clears up to four low bits, leaving the sign bit.
For the 32-bit mid/side file, the left channel starts at signed maximum and follows
`INT32_MAX - frame * (140801 << 7) + 43 * frame * frame`. The right channel is its negation
plus `frame % 11 - 5`, with signed wrapping. Frame zero uses the signed maximum and minimum.
libFLAC uses mid/side on its first frame and the side needs all 33 bits.

| Fixture | FLAC SHA-256 | PCM16 SHA-256 |
| --- | --- | --- |
| `flac-mono-4bit-11025` | `2ae70d410e1e0a85bd66f37f809c827cade79b1f665959aa96fb19e989789d15` | `a2f14e7b71a998d43da4151eded5209ff0cecf7f6c26d344f35db75c26ceff98` |
| `flac-stereo-8bit-12345` | `e5c06ed6e6db4649296e14b67d478d7f296e5da531ce22cea727e6b420c2f49e` | `d0f4bc00fe347a2f6ed87b8277d360f9ecbc2daf8a1d34d802532e2ed12b0cf1` |
| `flac-3ch-12bit-192000` | `1b705c13766ec5791028483e7a96110e69534961ef5d00ddde073bd8d7915e8c` | `0b59ead089673fe0a8167f608857e5525de9af6d27eab50db6670dd5d4b44e7c` |
| `flac-quad-20bit-250000` | `fb19e607831a2825611182fc56779798c7dba28a78ac7176f961596086b9db43` | `e00da588df1335a1d14e347cd43eabbd029149784c4e3084d0ff78c7707b45e3` |
| `flac-6.1-31bit-44100` | `ed7bd4df6a3c9c3aa74ae3a489d6703005297c0590cd34752fefc71b97d7faca` | `11e8a333dcdb8b74e9057a0203dc1c066f4a4d5678e41999908603f3ad9b8f30` |
| `flac-7.1-32bit-48000` | `d22bcca9cc61edbf96dec76c90d26a47a79373b864771707735c560258fcc4fe` | `2f88c61ee0ffe5af3e3e1a57ec7c085986466742b0087eac2d95dc482ae58094` |
| `flac-mid-side-32bit-48000` | `d749398195aceec184e6f95253949a88df4ed12df9c139c7c2611fac91a9a235` | `7f69cec8d1fd516ca12083bb04285cd39fabe9fe2853e2c80e875f013c6042f0` |

The fixtures share the repository license.

`flac-4.0-20bit-250000.flac` has the same coded frames as `flac-quad-20bit-250000.flac`. Its
Vorbis comment replaces the empty comment list with `TITLE=Deterministic four-channel ramp`
and `waveformatextensible_channel_mask=0x0107`, keeping the original vendor string. The
explicit layout uses front left, front right, front center, and back center. Its PCM16 bytes
match the untagged quad fixture. FFmpeg 9.1 reports masks `0x0107` and `0x0033`, respectively.

- SHA-256 `ad5dcba225ce70e8ecd967caf98dc7eaaab19e2af9fc5438ceea15e7a8258397`
- License is the same as this repository.

`flac-quad-20bit-250000.oga` and `flac-4.0-20bit-250000.oga` wrap the respective native
FLAC fixture’s STREAMINFO, Vorbis comment, and three coded frames in an Ogg FLAC 1.0 stream.
The Ogg serial number is `0x464C4143`. Both use a dedicated identification page and a final audio
page whose granule position is 69. The tagged fixture adds a description field with 270 `x`
characters before its other Vorbis comment fields, so its speaker mask is on the continuation
page. Both files decode to the same PCM16 as the native fixtures in FFmpeg 9.1.

- `flac-4.0-20bit-250000.oga` SHA-256 `eefbaf212e34f9429ce6cdd66f9d566861d2b3fe082adfd1dbeb9bcfac5576d3`
- `flac-quad-20bit-250000.oga` SHA-256 `21937830c7845730fbbb262051666c0eb681d1ca50ee03478e42e70639ad4335`
- License is the same as this repository.

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

`adpcm-ms-stereo-22050.wav`, `adpcm-ms-mono-8000.wav`, `adpcm-ima-stereo-44100.wav`, and
`adpcm-ima-mono-11025.wav` are one-second ADPCM WAVE files generated for this repository with the
FFmpeg libraries bundled by PyAV 17.1.0 (libavformat 62.12). The stereo inputs are synthetic 440 Hz
left and 660 Hz right sine waves, the mono inputs a 300 Hz sine wave, all at amplitude 0.18 with a
512-sample attack, so they contain no third-party recording. The `.pcm` file beside each one is the
interleaved 16-bit PCM FFmpeg decodes from it, block padding included. FFmpeg generated only the
fixtures and is not a build or runtime dependency.
- `adpcm-ms-stereo-22050.wav` SHA-256: `73a0ff666e44bcb5f219e951ed2fec59c5e2ceb612e96415131456dfedf5625a`
- `adpcm-ms-mono-8000.wav` SHA-256: `841dad9e3f14bd578e4107bbcf4136bbc366dde53c1e2c567402879ae3fe4bcb`
- `adpcm-ima-stereo-44100.wav` SHA-256: `00d370166e7d30bab7e405335724348eee24f2c36a2c6dd5d7f4e7f9d119ceb8`
- `adpcm-ima-mono-11025.wav` SHA-256: `b1d255f10ec34b383493891d6843c6e9bf3d5eacbc38f206574914363deb2bbe`
- License: same as this repository.

The `wav-g711-*` files are synthetic stereo 8 kHz WAVE files with 256 frames. At frame
`i` the channels carry the G.711 code bytes `i` and `255 - i`. The classic headers use
tags `0x0006` (A-law) and `0x0007` (mu-law). The extensible headers use the corresponding
subtype UUID and stereo mask `0x3`. Each `fact` chunk declares 256 frames. FFmpeg 9.1
and 7.1.5 decode both headers to the same 1,024-byte interleaved PCM16 reference.

- `wav-g711-alaw-extensible.wav` SHA-256: `4dc28fe778b1b51c73da84c2ce7ff51f0108dc1f2766e33eb900b1a8d37fe2c1`
- `wav-g711-alaw.pcm` SHA-256: `7967cc01ed1d28560003f4b91de960ce72c2d960c863233d1d20d55d83fbacc7`
- `wav-g711-alaw.wav` SHA-256: `34477e0e7f8993481f62c2099e5d2de6ec05eb3dd715777826bbc0a26860e3e5`
- `wav-g711-mulaw-extensible.wav` SHA-256: `8fe141897fb4148d4568cc41bbc3464b10052a1041c759c74620f173199cc499`
- `wav-g711-mulaw.pcm` SHA-256: `8ceb8b3749bf4a8d5bc598cf4de62e082b7681183c710425e8dbd806ebfa512f`
- `wav-g711-mulaw.wav` SHA-256: `609eddd60c9b91cf9d84755365af26551ef6b5555a3d07b7abdd21376281e7d6`
- License: same as this repository.

`flac-stereo-44100.oga` is the same synthetic lossless track as the shared
`flac-stereo-44100.flac`, remuxed into Ogg without re-encoding by PyAV 17.1.0
and libavformat 62.12.101. It carries the same licence as the original fixture.

`vorbis-stereo-44100.ogg` and `vorbis-transient-44100.ogg` are one-second Ogg Vorbis files generated
for this repository with the FFmpeg libraries bundled by PyAV 17.1.0 (libavformat 62.12, native
`vorbis` encoder). The first input is a synthetic 440 Hz left and 660 Hz right sine pair at amplitude
0.18 with a 512-sample attack; the second is seeded noise with eight clicks a second, which makes the
encoder use every window shape. `vorbis-mono-48000.ogg`, `vorbis-5.1-48000.ogg`, and
`vorbis-8ch-48000.ogg` are half-second streams generated with FFmpeg 7.1.5 and its `libvorbis`
encoder. The mono input is a 440 Hz sine; the multichannel inputs use distinct 300, 400, 500, 600,
700, 800, 900, and 1000 Hz sine waves at amplitude 0.18, in WAVE speaker order for each layout.
These files contain no third-party recording. The `.pcm` file beside each one is interleaved 16-bit
PCM decoded by libvorbis 1.3.7, the reference implementation of the format. The 5.1 and 8-channel
references are reordered from Vorbis channel order into WAVE order. FFmpeg's native decoder disagrees
with libvorbis on the coupled channel of the stereo streams. FFmpeg and libvorbis generated only the
fixtures and are not build or runtime dependencies.
- `vorbis-stereo-44100.ogg` SHA-256: `a2c28fe27f60c5e899d269f6ff9641cb05f8d7b4e92c8f0201abd29463f9a63f`
- `vorbis-transient-44100.ogg` SHA-256: `8605a8cdd727f53faf993add7c7f45c1d2acb499506f9186b5123ed75b422c5f`
- `vorbis-5.1-48000.ogg` SHA-256: `1e4143ac14529a9d8fc14a82f09ef6726ef7441f63384536a6d1663cd47dfa20`
- `vorbis-5.1-48000.pcm` SHA-256: `258a0fb4803027aca04df2e3eddb66972403fc8eebefa5303decc85895163f00`
- `vorbis-mono-48000.ogg` SHA-256: `79c54e4841c6435c637dc2d0fa5ac02d71774da4db5963ea624edf8310abb48f`
- `vorbis-mono-48000.pcm` SHA-256: `b13c8faa41ee4613693560aeee8f8d25b9c192ebf1d786408462a1e4a555841f`
- `vorbis-8ch-48000.ogg` SHA-256: `43294b77936f660cf900e7602b4b44e2030e23483b7b3a6806f7546c5f567292`
- `vorbis-8ch-48000.pcm` SHA-256: `bf5fa675368e9731efbb088b827ab0ea417ff13c45638187df72d2d369769729`
- License: same as this repository.


`vorbis-6.1-continued-48000.ogg` contains 16,003 frames of synthetic, distinct speaker tones
with short seeded noise bursts in 6.1 WAVE order. FFmpeg 7.1.5 and its `libvorbis` encoder
produced the stream at quality 6. The first audio packet was then split across two Ogg
pages without changing its data. The packet windows include short blocks and all four
long-block window shapes. The accompanying `.pcm` stores 16-bit samples decoded by
libvorbis 1.3.7 and reordered into WAVE speaker order.
- `vorbis-6.1-continued-48000.ogg` SHA-256: `e3210b2183debc9d8f65f3c75463c30a766e72541e30f3bacd02fb4e68ae7a1d`
- `vorbis-6.1-continued-48000.pcm` SHA-256: `bb99ddbd3fb2a6421e75ba8cbb14c209627bfb7f77d3751347c31be0b35bf05f`
- License: same as this repository.


`vorbis-floor0-5.1-48000.ogg` was generated for this repository from the Vorbis I packet
definitions. It contains 3,405 synthetic 5.1 frames with odd and even Floor 0 LSP orders,
short and long blocks, distinct channel amplitudes and intermittent silence.
The `.pcm` reference is interleaved signed 16-bit PCM decoded by libvorbis 1.3.7
and reordered into WAVE speaker order.
- `vorbis-floor0-5.1-48000.ogg` SHA-256: `fae0f16091c3eb753668bfbbf81c11ff40d67d8720b946cebc0a661a34e981b3`
- `vorbis-floor0-5.1-48000.pcm` SHA-256: `144f3eceae443ce661c69bee900bf3f57a6daf8849535cb2c1d68392b2b414d7`
- License: same as this repository.


`opus-stereo-48000.opus`, `opus-mono-silk.opus`, `opus-stereo-hybrid.opus`, and
`opus-transient-48000.opus` are one-second Ogg Opus files generated for this repository with the
FFmpeg libraries bundled by PyAV 17.1.0 (libavformat 62.12, `libopus` encoder). The first is the
synthetic 440 Hz left and 660 Hz right sine pair at 96 kb/s, which the encoder codes as CELT; the
second is a 300 Hz mono tone at 12 kb/s in the voice application, which it codes as SILK; the third
is the sine pair at 32 kb/s in the voice application, which it codes as hybrid frames that switch
to CELT and back; the fourth is the seeded noise with eight clicks a second in 10 ms frames at
128 kb/s. They contain no third-party recording. The `.pcm` file beside each one is the interleaved
16-bit PCM libopus 1.5.x decodes from it through FFmpeg, the reference implementation of the
format. FFmpeg and libopus generated only the fixtures and are not build or runtime dependencies.
- `opus-stereo-48000.opus` SHA-256: `e8b0d77b92526228bea7d76ddfd67b46e8f67ad13c21598210d9d550f82ebf69`
- `opus-mono-silk.opus` SHA-256: `1da049c423881c70df30ef93c5388429f951663d74640ec690f7b05fdbebd723`
- `opus-stereo-hybrid.opus` SHA-256: `46a38b2e33b943ad20f313d2cdc331c6026da67f49da537d90495c9a1c183cf1`
- `opus-transient-48000.opus` SHA-256: `330464417a632d26350ab67648ebf86a7672c8b1ed6a3a5c0e470936d7806e9e`
- License: same as this repository.

## IEEE Float64 WAVE

`wav-float64.wav` and `wav-float64-extensible.wav` are synthetic 48 kHz stereo files containing
8 frames. Both files use the same finite values on the PCM16 quantization grid, including
signed zero and samples that saturate. The extensible header uses the standard IEEE float
subformat and the stereo speaker mask 0x3. FFmpeg 9.1 (source `74e4393595cf2b5857f0da925c4e0dd74ea306e5`)
produces the same interleaved S16LE reference from both headers.

`wav-float64-edge-values.wav` is an 11-frame stereo fixture. It exercises truncation on either
side of the first nonzero PCM16 value, saturation of finite extremes and infinities, quiet and
signaling NaNs, and the smallest positive and negative subnormals. Its expected PCM is defined
in the Float64 conversion test.

- `wav-float64-edge-values.wav` SHA-256: `e376de0ed1a95e290fe729ad23c5c56b3a46e226c2122f38913ffeb8eaa94c1b`
- `wav-float64-extensible.wav` SHA-256: `084ef6a006b6ce561239e0052eabbe70f9826b487a709bda8c2a5794cb0c75bc`
- `wav-float64.pcm` SHA-256: `793427fdcc86fb43aa4f6caa6864828cac2f93726f2f3c48c357747d153d1756`
- `wav-float64.wav` SHA-256: `42c62c2e82642e26fdc5d573ae3d2a67504cf5bddde65a961b2d9b9eb718c0fd`
