# Video fixture sources

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

`cogliati-turning-pages.avi` is granted to the public domain by its author, on the page linked
above. `rav1e-c420jpeg.y4m` is BSD 2-Clause; see `LICENSE.bsd-2-clause.txt`. The two `xiph-`
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

## Generated for this repository

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

## Expected values

The colours the tests assert were read by decoding the same file with ffmpeg, not with this
module. A change here therefore cannot move an expectation along with it.
