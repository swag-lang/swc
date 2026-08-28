# Video fixture sources and licences

Every decoding test of this module reads a file from this directory. None of them is produced by
this module's own encoders: a codec that only reads back what it wrote proves nothing about the
files people actually have.

The corpus has three origins, and each file states which one it has.

## Written by someone else

| Local file | Origin | What it exercises | Size | SHA-256 |
| --- | --- | --- | --- | --- |
| `cogliati-turning-pages.avi` | [Josh Cogliati](http://jjc.freeshell.org/turning_pages.html), unmodified | A Canon camera recording: 160x120 4:2:2 Motion JPEG, 233 frames, 15 s, restart intervals, frames with no Huffman table of their own, an interleaved PCM audio stream, an `IDIT` chunk in the header list, and a rate stated as `1000000/66666` | 1 798 620 | `1948b50bb9195bdd2007e3362d77f2c5f39df09dc314dc8b7c9d126621581f06` |
| `rav1e-c420jpeg.y4m` | [rav1e `tests/small_input.y4m`](https://github.com/xiph/rav1e/blob/6a8dbbe966744a98090337fc642839234a315fbe/tests/small_input.y4m), unmodified | 64x64 8-bit `C420jpeg`, progressive, 5 frames | 30 807 | `c21278d4d829764b3bb4d1b3285ce660d1b0d0abc19c6f174a6d52ef5b853a70` |
| `xiph-claire-qcif.y4m` | [`claire_qcif-5.994Hz.y4m`](https://media.xiph.org/video/derf/y4m/claire_qcif-5.994Hz.y4m), unmodified | 176x144, 30 frames, no chroma tag so the implicit 4:2:0 default applies, `F6000:1001`, non-square pixel aspect | 1 140 703 | `c60601ce09c8470921d1a217f4f1326c6d40efb08c3cce6c9b71209a42c149c6` |
| `xiph-bus-qcif-15fps.y4m` | [`bus_qcif_15fps.y4m`](https://media.xiph.org/video/derf/y4m/bus_qcif_15fps.y4m), unmodified | 176x144, 75 frames, 5 s, same implicit default, read from its last frame backwards | 2 851 688 | `868fc3446d37d0c6959a48b68906486bd64788b2e795f0e29613cbb1fa73480e` |
| `hevc-ipred-a-docomo-2.bit` | JCT-VC `IPRED_A_docomo_2`, unmodified | Every H.265 intra prediction mode at every transform size, 20 pictures | 335 377 | `db440d8ce43ba3706a42b7c42095464dace247dbc4651d37c9787e5eb4aa3875` |
| `hevc-merge-a-ti-3.bit` | JCT-VC `MERGE_A_TI_3`, unmodified | Merge candidate derivation at every permitted candidate count, 8 pictures | 16 374 | `0a84103e548cf8944851cc33c7826ea5213245fd94517fd1071895740abce749` |
| `hevc-tmvp-a-ms-3.bit` | JCT-VC `TMVP_A_MS_3`, unmodified | Temporal motion vector prediction, which reads motion a reference picture exported, 17 pictures | 17 238 | `33556aa42355ba43575a6e6f1b579420a9217f576fc0ae07ee57fa2750a38d52` |
| `hevc-sao-a-mediatek-4.bit` | JCT-VC `SAO_A_MediaTek_4`, unmodified | Sample adaptive offset with random merge decisions, over intra and predicted pictures, 60 pictures | 52 606 | `88f693ac4aec4dea03cb4bc0cb9d8c98a4023a015905369bb62688064fb58944` |
| `hevc-wpp-a-ericsson-main10-2.bit` | JCT-VC `WPP_A_ericsson_MAIN10_2`, unmodified | Ten-bit samples through wavefront parallel processing, with independent and dependent slice segments, 48 pictures | 67 071 | `3b0d7323bf81d64d3c1443c9cebb8df6a42e0719ed422e64125e03971999b956` |

The five `hevc-*.bit` files are H.265 conformance bitstreams of the Joint Collaborative Team on
Video Coding, distributed from the JCT-VC bitstream exchange under
`https://www.itu.int/wftp3/av-arch/jctvc-site/bitstream_exchange/draft_conformance/` and published
there for the express purpose of testing decoders against Rec. ITU-T H.265. Each carries the digest
of every picture it decodes to inside the stream, so it is its own reference and no separate
expectation is stored for it. They are redistributed unmodified, under their name in that
collection, and are used here for exactly what they were published for.

`cogliati-turning-pages.avi` is granted to the public domain by its author, on the page linked
above. `rav1e-c420jpeg.y4m` is BSD 2-Clause; see the BSD 2-Clause text below. The two `xiph-`
sequences come from the Xiph.org video test media collection, which states that its sequences
"were available at one time on publicly accessible servers or were given to us explicitly to host
here, and are believed to be freely redistributable".

## Written by ffmpeg

One clip, encoded nine ways by ffmpeg 7.1. Its picture is synthetic and generated for this
repository: three quadrants of fixed colour, which prove a frame was not turned over or
transposed, and a fourth neutral quadrant whose level is `20 + 20 * index`, which identifies the
frame so that a seek landing on the wrong one cannot pass. The `.avi` clips are 64x48 for the
compressed variants and 32x24 for the uncompressed ones; the `.y4m` clips are 32x24.

| Local file | ffmpeg arguments | What it exercises |
| --- | --- | --- |
| `ffmpeg-mjpeg-420.avi` | `-c:v mjpeg -pix_fmt yuvj420p -q:v 3` | Motion JPEG, 10 frames, `MJPG` in both the stream and bitmap headers |
| `ffmpeg-mjpeg-422.avi` | `-c:v mjpeg -pix_fmt yuvj422p -q:v 3` | Two chroma blocks per minimum coded unit, which the Pixel JPEG decoder does not read yet |
| `ffmpeg-mjpeg-444.avi` | `-c:v mjpeg -pix_fmt yuvj444p -q:v 3` | The same, at full chroma resolution |
| `ffmpeg-mjpeg-ntsc.avi` | `-c:v mjpeg -pix_fmt yuvj420p -q:v 3 -r 30000/1001` | A broadcast rate the stream header carries as a ratio |
| `ffmpeg-mjpeg.mp4` | `-i ffmpeg-mjpeg-420.avi -map 0:v:0 -c:v copy -an -movflags +faststart` | ISO-BMFF with `moov` before `mdat`, one chunk holding ten samples, and an `mp4v` entry whose `esds` descriptor names JPEG object type `0x6c` |
| `ffmpeg-rawvideo-bgr24.avi` | `-c:v rawvideo -pix_fmt bgr24` | Uncompressed 24-bit frames, `biCompression` zero, negative bitmap height, `00dc` chunks |
| `ffmpeg-rawvideo-bgra.avi` | `-c:v rawvideo -pix_fmt bgra` | Uncompressed 32-bit frames, whose alpha byte is dropped |
| `ffmpeg-rawvideo-odd.avi` | `-c:v rawvideo -pix_fmt bgr24`, 33x25 | A row of 99 bytes padded to 100, which is the bitmap rule |
| `ffmpeg-c422.y4m` | `-pix_fmt yuv422p` | 4:2:2 planes |
| `ffmpeg-c444.y4m` | `-pix_fmt yuv444p` | 4:4:4 planes |
| `ffmpeg-mono.y4m` | `-pix_fmt gray` | Luma alone, with the `XCOLORRANGE=FULL` tag |
| `ffmpeg-ntsc-c420.y4m` | `-pix_fmt yuv420p -r 30000/1001` | 4:2:0 planes at a broadcast rate |

## Written by ffmpeg, then edited

The AVI container carries shapes no single writer produces. Each of these is
`ffmpeg-rawvideo-bgr24.avi` with one shape injected into it, so that the file under test differs
from a real one in exactly that respect and in nothing else. Every one of them still decodes to
the same six pictures.

| Local file | Edit |
| --- | --- |
| `edited-bottom-up.avi` | The bitmap height is negated and the rows reversed, so the frames are stored bottom-up, as most writers other than ffmpeg store them |
| `edited-no-index.avi` | The `idx1` table is removed and `AVIF_HASINDEX` cleared, as in a recording interrupted before its index was written |
| `edited-absolute-index.avi` | The index offsets are counted from the start of the file rather than from the frame list, which some writers do and nothing in the format distinguishes |
| `edited-record-groups.avi` | Every frame is wrapped in a `rec ` list and the index removed, as an OpenDML file groups its frames |
| `edited-dropped-frames.avi` | The payloads of frames 3 and 4 are emptied and the index updated, which is how the container says a frame repeats the picture before it |

`edited-truncated-tail.mkv` is `ffmpeg-h264-two-aac.mkv` with everything from its second cluster
onward replaced by zeros, which is what a write that stopped part way leaves behind, and what two
files of a real library turned out to hold. The first cluster and every element before it are
untouched, so the pictures it did write still decode; the cue table it never wrote does not.

- SHA-256: `88964b22b9d771197b8ca4493f32230d13cf0f72c5bebb39da1368c70d6252c4`
- License: same as `ffmpeg-h264-two-aac.mkv`.

`edited-header-stripped.mkv` is `ffmpeg-h264-two-aac.mkv` rewritten with the leading zero byte
taken off every video frame and stated once in a ContentEncoding, which is what mkvmerge does by
default to several codecs and what one file of a real library carries. Its seek head and cue table
are dropped because every offset in them moves; nothing else about the file changes.

- SHA-256: `292b613741335cbced6daca10ec62bdc3fe7283840380db2f3f8445dddbd5b22`
- License: same as `ffmpeg-h264-two-aac.mkv`.

`edited-open-group-start.mkv` is the first twenty-six access units of `ffmpeg-hevc-main.mp4`
dropped and the rest copied into Matroska, so it begins at a clean random access point whose four
leading pictures predict from what came before it. `edited-open-group-start.yuv` is FFmpeg's decode
of it, thirty pictures rather than thirty-four: the four the standard says not to show are absent.

- SHA-256: `c3b58963cc5f276b63c7d2b28388e7788e914e799d765397b95e28f6e138b485` and
  `6865d4101605c287efb2a14eae6eca0379c6488ab607d25cfd91cab9db17e49e`.
- License: same as `ffmpeg-hevc-main.mp4`.

`edited-mid-group-start.mkv` is the first five access units of `ffmpeg-h264-pyramid.mp4` dropped and
the rest copied into Matroska, which cuts away the picture its next slices refer back to. A file
clipped that way begins in the middle of a group: nothing before its first marked sample can be
reconstructed, and one file of a real library begins exactly so. `edited-mid-group-start.yuv` is
FFmpeg's decode of it, forty-four pictures rather than fifty-five.

- SHA-256: `b8dd76e9e4ae6dfdd09baddbb524662d9bf8fbc8ef2af0c5dbee931a58af395d` and
  `1822c0be6c417f5710cc636d7d0fb4b7d28b1c60d024a932ea2b765998f89942`.
- License: same as `ffmpeg-h264-pyramid.mp4`.

`glint-aac-drift.mp4` is `glint-aac-mjpeg.mp4` with the sound track's time-to-sample table rewritten
from one entry of nineteen samples at 1024 into three entries of 1023, 1024 and 1025. The total is
unchanged and so is every byte of media; only the table stops stating one number, which is what
several real files carry. The movie box sits after the media data there, so growing it left every
chunk offset where it was.

- SHA-256: `85418e5dae5ad937490fc6def9b091c47655ec49ec7747766b7f8adac140eeea`
- License: same as `glint-aac-mjpeg.mp4`.

## Generated for this repository

`ffmpeg-h264-subtitle.mkv` stream-copies `ffmpeg-h264-baseline.mp4` and muxes the repository's
`subtitle-sample.srt` as a default French SubRip track through FFmpeg 7.1. It exercises Matroska
subtitle discovery, metadata, packet timestamps, durations, and cue decoding without introducing
new third-party content.

- FFmpeg arguments: `-map 0:v:0 -map 1:0 -c:v copy -c:s srt -metadata:s:s:0 language=fra -metadata:s:s:0 title=French -disposition:s:0 default`
- SHA-256: `c0f84c38da71f22199cc783aa3195ab05f701dc05f89646b723b7b5a9d67763a`
- License: same as this repository and `ffmpeg-h264-baseline.mp4`.

`ffmpeg-h264-two-aac.mkv` stream-copies `ffmpeg-h264-baseline.mp4` and the AAC-LC track of
`glint-aac-mjpeg.mp4` through FFmpeg 9.0.1. The sound stream is mapped twice, with the first copy
marked as the default track, so one small file exercises Matroska AVC blocks, AAC packet indexing,
multiple-track ordering, and independent sound cursors without introducing new encoded content.

- FFmpeg arguments: `-map 0:v:0 -map 1:a:0 -map 1:a:0 -c copy -disposition:a:0 default -disposition:a:1 0`
- SHA-256: `36c7ad0fdee8156478589265ad51a3025d8c7822904fd504c82e7dd50bfd2c5d`
- License: same as this repository and its two generated source fixtures.

`ffmpeg-h264-two-aac-10min.mkv` repeats that complete Matroska fixture 750 times through FFmpeg
9.0.1. Its 15,000 pictures and 28,500 audio packets exercise accumulated timestamps, compact index
growth, and random seeks near the end of a file without adding different encoded content.

- FFmpeg arguments: `-stream_loop 749 -i ffmpeg-h264-two-aac.mkv -t 600 -map 0:v:0 -map 0:a:0 -map 0:a:1 -c copy`
- SHA-256: `03c0948040a70ce37684557ea355d6b15b722171135692d65f534c9c893d61e6`
- License: same as this repository and `ffmpeg-h264-two-aac.mkv`.

`glint-aac-mjpeg.mp4` combines the ten synthetic pictures from `ffmpeg-mjpeg.mp4` with the
mathematically generated stereo sine stream documented by std/audio's
`aac-lc-stereo-44100.aac`. The tracks were stream-copied into MP4 through PyAV 17.1; no
third-party recording is present. It exercises a version-0 `mp4a` entry, `esds`
AudioSpecificConfig, independent audio chunking, and concurrent file cursors.

- SHA-256: `3414695932df3598a24212796c46183a3cce46d7c81dba7b60eef6886047ab63`
- License: same as this repository; the glint encoder is MIT licensed.

`bars-scroll-c420.y4m` is the long stream the streaming tests read: 400 frames of 128x72 at 25
frames per second, 8-bit `C420jpeg`, progressive.

- Eight BT.601 limited-range colour bars, 16 pixels wide — white, yellow, cyan, green, magenta,
  red, blue, black — scrolling by exactly one bar per frame, so the bar covering a given column
  is a known function of the frame index. Bar edges fall on even coordinates, so 4:2:0 chroma
  carries them exactly.
- A 16 by 16 block in the top-left corner whose luma is `16 + index % 220` and whose chroma is
  neutral. It identifies the frame: a seek that lands on the wrong frame, or a stream walked from
  the wrong offset, cannot produce the expected value.

- SHA-256: `ee715b25c78937abe7c9b66a45260fdfbeff3b0951e5e72c224cd768a59a2570`
- License: same as this repository, as for every generated and edited file above.

`ffmpeg-h264-pyramid.mp4` and `ffmpeg-h264-temporal.mp4` are 96x64, 60-frame clips of moving
blocks over a scrolling gradient with one noise band, generated for this repository and encoded
with libx264 through PyAV. They exist because a codec bug that only shows on real encoder output
needs real encoder output to be caught:

- `ffmpeg-h264-pyramid.mp4`: `preset=medium g=30` — High profile at x264 defaults: CABAC, intra
  8x8 prediction modes, a reference-B pyramid, weighted P prediction, and multi-partition B
  macroblocks whose motion feeds the entropy contexts across partitions.
- `ffmpeg-h264-temporal.mp4`: `profile=main preset=slow g=30` plus
  `x264-params=direct=temporal:slices=3` — temporal direct modes, several references, and three
  CABAC slices per picture, so contexts restart and neighbor availability stops at slice
  boundaries.

The matching `.yuv` files are the same streams decoded by FFmpeg, which is what the tests demand
byte for byte.

`ffmpeg-h264-aac-5.1.mkv`, `ffmpeg-h264-ac3-5.1.mkv`, and
`ffmpeg-h264-eac3-5.1.mkv` combine the repository's synthetic H.264 fixture with the corresponding
six-tone audio fixtures documented by std/audio. FFmpeg `N-126262-g1019f8f036-20260824`
stream-copied the H.264 access units and muxed each audio stream into Matroska; it is a fixture
generator, not a build or runtime dependency.

- `ffmpeg-h264-aac-5.1.mkv` SHA-256: `c31573d33584b7e9b10efd651570eb67f148a0020dfd261c7a8a8ca69a11e854`
- `ffmpeg-h264-ac3-5.1.mkv` SHA-256: `84b5a44e6e0962d51f4dcd18fe1b5088c44dd3a31f2632099c8915f52748d861`
- `ffmpeg-h264-eac3-5.1.mkv` SHA-256: `6b5fcb7458b0b234165164d3b36f81862e6bc4ef3e087743f364e2c811842f0a`
- License: same as this repository.

`mkv-aac-codec-delay.mkv` is `ffmpeg-h264-two-aac.mkv` with track 1's Matroska `CodecDelay` set
to 23,219,954 ns by MKVToolNix. At 44.1 kHz this removes exactly 1,024 decoded AAC priming frames.

- SHA-256: `f015d034f3226285f969b6c3f15bd0f79b7985494f07ecb56c6c810940b3f560`
- License: same as `ffmpeg-h264-two-aac.mkv`.

`ffmpeg-hevc-main.mp4`, `ffmpeg-hevc-inband.mp4`, and `ffmpeg-hevc-main.mkv` re-encode the source
pictures of `ffmpeg-h264-pyramid.yuv` with x265 through PyAV 17.1, so the H.264 and H.265 fixtures
carry the same 96x64, 60-frame content and a difference between them is the codec alone.

- `ffmpeg-hevc-main.mp4`: `preset=medium keyint=30 bframes=4 b-pyramid=1`, written with an `hvc1`
  sample entry, whose parameter sets live only in the sample description. SHA-256:
  `4176a643fec7f415cba4a0d73129efba39f88a9e96929cccc05cfe1ae7b6fae5`.
- `ffmpeg-hevc-inband.mp4`: `preset=slow keyint=30 bframes=3 b-pyramid=1 slices=3 repeat-headers=1`,
  written with an `hev1` sample entry, so every access unit repeats the parameter sets and three
  slices divide each picture. `preset=slow` is what turns on rectangular prediction partitions, and
  those are what the transform tree of an inter unit reads differently. SHA-256:
  `8562b02e9736fdc377e44317f3f29f43bf1a97a5d0d39d67b80567a6b16780c2`.
- `ffmpeg-hevc-main.mkv` is a stream copy of the first into Matroska, so the two decode to the same
  pictures and only the container reader differs. SHA-256:
  `6a2bcffbac7d879dd3a7051e367abeec4278eee4af51fc4c6563d33a6d1a5670`.
- `ffmpeg-hevc-main.yuv` and `ffmpeg-hevc-inband.yuv` are those streams decoded by FFmpeg, which is
  what the tests demand byte for byte. SHA-256:
  `2ffedc6334a2514efed9367ba8b699317849b7152f5ea4b1ff362d7a1e33b021` and
  `c62100124f47f6ce646d22e1c6c710c231281d36a5525a1a865ae9594592cfb6`.
- License: same as this repository.

`ffmpeg-h264-flac-5.1.mkv` stream-copies the H.264 access units of `ffmpeg-h264-baseline.mp4` and
the FLAC track documented by std/audio's `flac-5.1-48000.flac` into Matroska through PyAV 17.1. Its
audio frames carry 4,608 samples each, which is what a FLAC frame states in its own header rather
than something the container knows.

- SHA-256: `dd3b3c5d0eb5a0c72e4f3cadf4023d40a0002f8880e2c39e8b0f6e55dccefab8`
- License: same as this repository.

`ffmpeg-mpeg4-simple.mkv` and `ffmpeg-mpeg4-bvop.mkv` re-encode the source pictures of
`ffmpeg-h264-pyramid.yuv` with FFmpeg's MPEG-4 Part 2 encoder through PyAV 17.1, so they carry the
same 96x64, 60-frame content as the H.264 and H.265 fixtures and a difference is the codec alone.

- `ffmpeg-mpeg4-simple.mkv`: no bidirectional planes, the H.263 quantiser, and four motion vectors
  where the encoder chose them, which is Simple Profile as an encoder of that era wrote it. SHA-256:
  `d007e84e10e1593aa91f33444c481e8abde596dd9643e5dc9032334977c0d4f5`.
- `ffmpeg-mpeg4-bvop.mkv`: `max_b_frames=2 mpeg_quant=1`, so bidirectional planes and the MPEG
  quantiser are both exercised and the display order is not the decoding order. SHA-256:
  `8f5f712d015d24729495365cdfd6f853937ff2c9d02a1e2821498e20b36ced32`.
- `ffmpeg-mpeg4-packed.avi`: the same 60 pictures with `max_b_frames=2`, muxed into AVI, which is
  the container this codec mostly lived in. AVI states no decoding order, so the stream carries its
  own setup headers, a bidirectional plane is stored behind the plane it refers forward to, and a
  plane that codes nothing pads the frame it would have taken. SHA-256:
  `4db4b1ccb5aaa544fe4f6333fba6798a76896eeb551fbf5cfd224a21d6c3f537`.
- `ffmpeg-mpeg4-simple.yuv`, `ffmpeg-mpeg4-bvop.yuv`, and `ffmpeg-mpeg4-packed.yuv` are those
  streams decoded by FFmpeg, which is what the tests measure against. SHA-256:
  `5a5ace6350c62eafc6bb2d38e823b1f489d1c28184a2301733a188b9b55382e5`,
  `75cdee3b18cb7b056be4265a91fcc9defbd0b45c59ac1620786549a0455c56f5`, and
  `d099ba62af714cff4f93034a03a0ff8887853616091cccfe3182e3195d19b9e1`.
- License: same as this repository.

## Expected values

The colours the tests assert were read by decoding the same file with ffmpeg, not with this
module. A change here therefore cannot move an expectation along with it.

## rav1e BSD 2-Clause licence

BSD 2-Clause License

Copyright (c) 2017-2020, the rav1e contributors
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


`ffmpeg-h264-opus.mkv` and `ffmpeg-h264-vorbis.mkv` stream-copy the H.264 access units of
`ffmpeg-h264-baseline.mp4` and, respectively, the Opus track of std/audio's
`opus-stereo-48000.opus` and the Vorbis track of `vorbis-stereo-44100.ogg` into Matroska through
PyAV 17.1. The muxer states the Opus pre-skip as the track's codec delay and trims the final
block with a discard padding; the Vorbis headers travel Xiph-laced in the codec private data.
`opus-stereo-48000.pcm` and `vorbis-stereo-44100.pcm` are copies of the reference decodes
documented beside those sources, so the container tests compare against the same samples.

- `ffmpeg-h264-opus.mkv` SHA-256: `25ebe972d6bdf54aedb315c408775b78bade1f20f181c9aab552f4549202960e`
- `ffmpeg-h264-vorbis.mkv` SHA-256: `c2c591838668e4aab3376c2f2890887c68b90fd33606105a143893cd5d8224e5`
- License: same as this repository.
