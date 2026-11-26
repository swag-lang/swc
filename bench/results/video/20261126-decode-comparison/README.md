# Video decode comparison

Release Swag and FFmpeg 7.1.5 ran under Linux x86-64 on an AMD EPYC 9V74 host.
Each comparison series was pinned to one logical CPU. The Swag baseline is `6ba8702c7b`. Both Swag variants used the same
Release compiler, runtime and one decoder lane. The timed window starts after 30 pictures
and continues forward to the end of the file. Each table value is a median in milliseconds
per picture. Each AVC clip and the 1080p Main10 clip use five repetitions. The 4K
and camera clips use three. The per-run observations and input and picture hashes are in
[measurements.json](measurements.json).

| Stream | Swag before | Swag after | FFmpeg | FFmpeg, CPU flags cleared | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| H.264 Baseline, 1080p | 6.21 | 5.41 | 2.25 | 4.74 | -12.9% | 2.40× |
| H.264 High, 1080p | 7.62 | 7.79 | 4.65 | 7.77 | +2.3% | 1.68× |
| H.265 Main10, 1080p | 18.85 | 16.40 | 9.91 | 17.12 | -13.0% | 1.65× |
| H.265 Main10, 3840×2076 | 70.80 | 55.34 | 33.90 | 64.70 | -21.8% | 1.63× |
| H.265 Main10, camera clip | 7.71 | 7.25 | 4.59 | 13.99 | -6.0% | 1.58× |

FFmpeg receives native decoded frames from libavcodec. Swag's `Video.Reader` also copies or
reduces the visible planes into a reusable eight-bit buffer. Startup, opening the file,
RGB conversion and raw picture writes are outside both timers. The measurements describe
software decoding for these streams on this host. Timing varied between logical CPUs.
Additional series in the JSON include a run with no 1080p Main10 gain and a larger AVC High
slowdown. The FFmpeg runs with CPU feature flags cleared serve as a diagnostic comparison.

## Picture comparison

Swag and FFmpeg decoded identical Y, Cb and Cr planes on all 1,337 compared pictures from
18 inputs. There were zero differing samples and the PSNR was infinite. The corpus covers
H.264 Baseline, Main, High and High 4:4:4 with CAVLC or CABAC, H.265 Main and Main10, cropping,
multiple slices, B-picture reordering and Matroska entries before the first displayed
picture. Main10 FFmpeg samples were rounded and saturated to match the eight-bit
`Video.Reader` planes. The separate HEVC conformance suite matched all 153 embedded
picture digests, including 48 before conversion from ten bits.

The native Release selection passed all 109 tests from the H.264, HEVC, HEVC conformance,
MP4 and Matroska test files. The AVC lookup test verifies every 16-bit lookahead against
each normative coefficient token table. The differential workload detected one
deliberately changed luma sample.

## Profile and changes

A baseline profile sampled the caller and each dedicated decode thread by its own CPU clock.
The active decode lane carried most samples. The CAVLC residual routine and VLC search
accounted for about 21% of samples on AVC Baseline. On HEVC Main10, residual decoding
accounted for 32%, and the runtime copy function for 14%.

The AVC decoder now resolves CAVLC fields through bounded prefix lookups, skips short
unary level prefixes in one step, and clears coefficients with fixed-size stores. The HEVC decoder tracks significant coefficient positions
in a bit mask, uses packed CABAC context transitions, and copies consecutive blocks with
no sample-adaptive offset as one span per row. The measured AVC High trial that unrolled
integer prediction copies was dropped after the timings failed to show an improvement.
A trial that recorded AVC CABAC coefficient positions as a bit mask also regressed and was dropped.

## Prediction and SAO follow-up

The follow-up compares against `12536022be` with the same Release compiler and timing
protocol. The AVC and grayscale clips use five repetitions. The 4K and camera clips use
three. Each value is a median in milliseconds per picture. FFmpeg dispatches native SIMD.

| Stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| H.264 High, 1080p | 9.00 | 8.39 | 5.73 | -6.8% | 1.47× |
| H.264 Baseline, 1080p | 5.40 | 5.13 | 2.26 | -4.9% | 2.27× |
| H.265 Main10, 3840×2076 | 56.81 | 52.72 | 36.22 | -7.2% | 1.46× |
| H.265 Main10, camera clip | 6.23 | 6.57 | 3.98 | +5.4% | 1.65× |
| H.265 Main10, grayscale 1080p | 13.23 | 12.94 | 8.20 | -2.2% | 1.58× |

The quality check matched all Y, Cb and Cr samples on 803 pictures. All 109 targeted
Release tests passed, including the 153 HEVC conformance picture digests.

Of 359 samples inside the generic copy on the previous 4K decoder, 224 came from integer
prediction and 126 from SAO. The new decoder copies the common integer prediction widths
with fixed-size loads and stores and keeps planes without SAO offsets in place. The AVC
decoder broadcasts the prediction weight and rounding once per block and selects its row
store by width outside the loop.

The camera clip was 5.4% slower in the final series and 6.0% faster in the earlier combined
trial. Its sample ranges overlap. An earlier variant updated the SAO plane mask while
parsing coding tree units. The grayscale series regressed by 8.1% with that variant. The
final variant derives the active planes from the stored SAO parameters before filtering.
[Follow-up measurements and profile counts](followup.json).

Reproduce the grayscale input by adding `-vf hue=s=0` to the 1080p Main10 generation
command and setting `-frames:v 120`.

## Y4M and Motion JPEG to RGB24

The [RGB workload](../../../workloads/videodecode/README.md) times sequential decoding with
colour conversion to a reusable RGB24 buffer. Release Swag at `591e02ef05` is the baseline.
Both Swag variants and FFmpeg 7.1.5 with libswscale ran on one logical CPU. Each median uses
nine rotated repetitions and excludes the first six pictures and the RGB serialization.
The generator commands, fixture hashes and individual observations are in
[rgb-fixtures.json](rgb-fixtures.json) and [rgb-decode.json](rgb-decode.json).

| Stream | Before, ms/picture | After, ms/picture | FFmpeg, ms/picture | Swag time change | RGB PSNR vs FFmpeg | Maximum RGB difference |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Y4M 4:1:1, 652×370 | 1.275 | 0.249 | 0.737 | -80.5% | 46.12 dB | 3 |
| Y4M 4:2:0 full range, 651×371 | 1.237 | 0.325 | 0.989 | -73.7% | 24.82 dB | 255 |
| Y4M 4:2:0 limited range, 1080p | 11.239 | 2.644 | 1.146 | -76.5% | 48.24 dB | 3 |
| Y4M 4:2:2, 720p | 5.668 | 1.355 | 0.604 | -76.1% | 48.27 dB | 3 |
| Y4M 4:4:4, 720p | 5.315 | 1.337 | 4.806 | -74.8% | 57.86 dB | 1 |
| Y4M monochrome, 650×370 | 1.041 | 0.157 | 0.285 | -84.9% | Exact | 0 |
| Motion JPEG 4:2:0, 1080p | 2.320 | 2.321 | 3.310 | +0.0% | 55.14 dB | 4 |
| Motion JPEG 4:2:2 texture, 720p | 3.348 | 3.304 | 2.900 | -1.3% | 51.05 dB | 4 |
| Motion JPEG 4:4:4, 720p | 1.846 | 1.832 | 7.095 | -0.7% | 70.32 dB | 3 |

The Y4M decoder converts four pixels at a time and packs exactly twelve output bytes. It
selects the sample layout and quantization range once per frame and uses the same integer
matrix on the last one to three pixels of a row. All 216 Y4M pictures matched the scalar
Swag baseline byte for byte. The full-range odd-size clip differs from libswscale at chroma
transitions. An independent calculation from FFmpeg's raw YUV planes reproduced the first
Swag picture exactly using `row / 2`, `column / 2` chroma indices and the BT.601 coefficients.
No Motion JPEG decoder code changed in this pass. Its 216 pictures also matched between the
two Swag builds. The 19 Y4M Release tests passed, and the planar workload still matched FFmpeg
on 69 AVC and RealVideo pictures.

### Motion JPEG direct RGB output

AVI and MP4 now decode JPEG scanlines into the reader's reusable RGB buffer. The packed
colour kernels select the component order before writing, and subsampled JPEG uses one
eight-lane chroma correction for each sixteen-pixel span. The three AVI fixtures kept
identical RGB throughout all 216 pictures. The focused native Release run passed 44 Pixel
and 51 Video tests, covering grayscale, progressive, CMYK/YCCK, unusual sampling factors,
dimension validation and overlapping input and output storage.

The following single-CPU medians use nine rotated runs. FFmpeg 9.1 and libjpeg-turbo
3.2.1 use the same libavformat and both produce nearest-neighbour RGB24. FFmpeg 7.1.5
was the independent picture reference. [Timing samples](mjpeg-direct-rgb.json)

| Stream | Before, ms/picture | Direct RGB, ms/picture | Paired time change | FFmpeg 9.1 | libjpeg-turbo 3.2.1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4:2:0, 1080p | 2.584 | 1.982 | −18.5% | 3.552 | 2.815 |
| 4:2:2 texture, 720p | 3.363 | 3.054 | −6.4% | 3.174 | 2.659 |
| 4:4:4, 720p | 1.818 | 1.704 | −4.6% | 8.233 | 1.865 |

### Motion JPEG six-byte entropy refill

Both the baseline register reader and the progressive reader accept six entropy
bytes at once when eight bytes are readable and the first six contain no marker
prefix. The short path still handles stuffed bytes, markers and the end of the
input window. All 216 AVI pictures and 24 MP4 pictures match the previous Swag
reader byte for byte. The MP4 clips use baseline and progressive 4:4:4 JPEG with
a restart marker every five MCUs. The maximum RGB differences from FFmpeg 9.1
are four sample values in AVI and three in MP4. The native Release selection
passed 47 Pixel and 51 Video tests.

Seven rotating single-CPU runs give the medians below. The confirmation uses
three passes per Swag AVI observation and eleven per MP4 observation. Textured
4:2:2 was faster in the initial pass and roughly flat in the confirmation.
[Pictures and timing samples](mjpeg-entropy-refill.json)

| Stream | Before, ms/picture | Six-byte refill, ms/picture | Paired time change | FFmpeg 9.1 | libjpeg-turbo 3.2.1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4:2:0, 1080p AVI | 1.852 | 1.781 | −3.8% | 3.410 | 2.905 |
| 4:2:2 texture, 720p AVI | 2.580 | 2.609 | +0.5% | 2.945 | 2.521 |
| 4:4:4, 720p AVI | 1.421 | 1.397 | −3.9% | 6.466 | 1.785 |
| Baseline with restarts, 640×360 MP4 | 0.712 | 0.713 | +0.1% | 1.672 | 0.784 |
| Progressive with restarts, 640×360 MP4 | 2.070 | 1.945 | −8.3% | 2.296 | 2.219 |

### Y4M shared chroma correction

The subsampled path computes a colour correction for eight pixels at a time and reuses
it for both luma rows in 4:2:0. It packs 24 RGB bytes and handles the last column or row
with the same matrix. The final source matched all 216 RGB pictures from the preceding
Swag decoder. The 20 native Release tests include a 9×3 frame with a distinct chroma row
and a one-pixel tail.

The single-CPU results use nine rotated runs and FFmpeg 9.1 with libswscale.
[Timing samples](y4m-shared-chroma.json)

| Stream | Before, ms/picture | Shared chroma, ms/picture | Paired time change | FFmpeg 9.1, ms/picture |
| --- | ---: | ---: | ---: | ---: |
| 4:2:0 full range, 651×371 | 0.344 | 0.184 | −46.5% | 0.984 |
| 4:2:0 limited range, 1080p | 2.768 | 1.798 | −35.3% | 1.192 |
| 4:2:2 limited range, 720p | 1.345 | 0.980 | −27.6% | 0.634 |
| 4:4:4, 720p control | 1.698 | 1.355 | −2.9% | 5.008 |

### Y4M 16-bit colour arithmetic

The 4:2:0 and 4:2:2 converters keep eight luma samples in sixteen-bit lanes. Limited-range
conversion splits the luma and chroma terms at 256 and adds the low-byte carry before
clamping. This preserves the original rounding. An exhaustive arithmetic check covered
the 16,777,216 eight-bit Y, Cb and Cr combinations in each range. All 216 fixture pictures
and all 20 native Release tests passed. [Timing samples](y4m-narrow-matrix.json)

| Stream | Before, ms/picture | Sixteen-bit lanes, ms/picture | Paired time change | FFmpeg 9.1, ms/picture |
| --- | ---: | ---: | ---: | ---: |
| 4:2:0 full range, 651×371 | 0.187 | 0.150 | −22.4% | 1.035 |
| 4:2:0 limited range, 1080p | 1.771 | 1.713 | −5.9% | 1.196 |
| 4:2:2 limited range, 720p | 0.925 | 0.914 | −0.3% | 0.582 |

### AVC CABAC slice initialization

The AVC decoder copies precomputed initial CABAC contexts for the slice's QP and
initialization table. The static table occupies 208 KiB. The arithmetic engine and
adaptation continue to use the slice's own context storage.

Nine rotated runs used one logical CPU and FFmpeg 9.1. All 336 pictures matched the
original Swag decoder and FFmpeg exactly. The focused native Release selection passed
70 AVC, MP4 and Matroska tests. [Timing samples](avc-slice-contexts.json)

| Stream | Before, ms/picture | Cached contexts, ms/picture | Paired time change | FFmpeg 9.1, ms/picture |
| --- | ---: | ---: | ---: | ---: |
| One slice, 1080p | 6.884 | 6.960 | −1.8% | 4.061 |
| Eight slices, 1080p | 7.007 | 6.713 | −5.2% | 3.872 |
| 32 slices, 1080p | 8.322 | 6.608 | −12.2% | 4.239 |
| Six slices, 4K | 35.237 | 34.175 | −3.0% | 19.525 |

Generate the 1080p cases with `generate.py --avc-slices`. For the 4K case, retain the
first 48 pictures of the default generator's six-slice clip with FFmpeg stream copy.

### AVC CAVLC nonzero coefficient stores

The CAVLC reader skips coefficient storage when the transform block is empty.
On nonempty blocks, two vectors identify the nonzero positions. The decoder
walks those bits and applies the existing scan order and inverse quantization.
All 396 pictures matched FFmpeg 9.1 exactly, and the native Release selection
passed 81 H.264, MP4 and Matroska tests.

Seven rotating runs used one CPU and a 16-picture warm-up. The High stream
uses CABAC and serves as the timing control.
[Timing samples](avc-cavlc-coefficient-mask.json)

| Stream | Before, ms/picture | Mask, ms/picture | Paired time change | FFmpeg 9.1 |
| --- | ---: | ---: | ---: | ---: |
| Baseline, 1080p | 6.403 | 5.397 | −5.3% | 2.210 |
| Baseline with texture, 960×540 | 5.592 | 4.569 | −19.0% | 2.004 |
| High, eight slices, 1080p | 6.790 | 7.045 | −1.8% | 3.732 |

## FFmpeg 9.1 reference

The current reference uses FFmpeg `n9.1` (`74e4393`), built on Linux x86-64 with runtime
CPU selection and NASM 2.16.03. Both `ffprobe`/`ffmpeg` picture validation and the native
libavcodec timing program use this release. The seven-run medians start after eight
warm-up pictures. The one-lane runs use CPU 4. The four-lane runs use CPUs 0–3 and include
the AVC slice-context cache. Picture digests and all observations are in
[ffmpeg-9-1.json](ffmpeg-9-1.json).

| Stream | Swag, one lane | FFmpeg, one lane | Swag, four lanes | FFmpeg, four lanes | Maximum difference |
| --- | ---: | ---: | ---: | ---: | ---: |
| AVC Baseline, 1080p | 5.392 ms | 2.158 ms | | | 0 |
| AVC High, 1080p | 7.909 ms | 4.744 ms | 4.561 ms | 1.616 ms | 0 |
| HEVC Main10, 1080p | 14.435 ms | 8.210 ms | | | 0 |
| HEVC Main WPP, 720p | 5.865 ms | 2.968 ms | 3.440 ms | 1.388 ms | 0 |
| AVC High, six slices, 4K | 29.212 ms | 15.790 ms | 12.341 ms | 4.958 ms | 0 |
| HEVC Main10, 3840×2076 | 51.902 ms | 30.256 ms | 29.460 ms | 9.524 ms | 0 |
| MPEG-4 Part 2 Simple, 720p | 1.504 ms | 0.572 ms | | | 3 |
| MPEG-4 Part 2 MPEG quantization, 720p | 1.220 ms | 0.514 ms | | | 4 |
| RealVideo 4.0 I/P/B, 96×64 | 0.129 ms | 0.044 ms | | | 0 |

Times are per decoded picture. Of the 1,680 pictures in the one-lane comparison, all
1,440 AVC, HEVC and RealVideo pictures match exactly. The MPEG-4 Part 2 clips have 68.67
and 68.72 dB PSNR. All 360 pictures in the four-lane comparison match exactly, with
the same hashes as the one-lane output. FFmpeg Main10 is rounded to Swag's eight-bit
public plane format for this comparison.

Build the native helper against FFmpeg 9.1 and put that release's `ffmpeg` and `ffprobe`
on `PATH`. The fixture definitions are in this report and `generate.py`. Repeat the
checked-in RealVideo clip with `repeat-rv40.py`. Use stream copy to retain 48 pictures
of the AVC 4K clip and 42 of the Main10 4K clip. Time with `--warmup 8 --repetitions 7`
and use `--mpeg4-max-sample-difference 4` for the MPEG-4 fixtures.

### RealVideo bounded VLC look-ahead

The decoder resolves an eight-bit prefix from the selected VLC root. A short code
supplies its coefficient and exact bit length in one lookup. Long codes resume in the
existing tree. Bounded reads load up to one native word, and the final bytes of each
slice keep a separate short read path. All 762 pictures matched both the previous Swag
decoder and FFmpeg 9.1 exactly. The 48 native Release tests cover unaligned 32-bit reads,
the last valid bit of a slice and multi-packet Matroska playback.

| Stream | Before, ms/picture | VLC look-ahead, ms/picture | Paired time change | FFmpeg 9.1, ms/picture |
| --- | ---: | ---: | ---: | ---: |
| Repeated I/P/B, 720 pictures | 0.146 | 0.135 | −6.7% | 0.038 |
| Intra | 0.147 | 0.118 | −20.4% | 0.062 |
| I/P/B | 0.105 | 0.094 | −9.3% | 0.039 |
| Adaptive dimensions | 0.142 | 0.117 | −24.4% | 0.040 |
| Multiple slices | 0.104 | 0.099 | −10.9% | 0.038 |

Nine rotated runs were pinned to one logical CPU with two warm-up pictures.
[Timing samples](rv40-vlc-look-ahead.json)

### Uncompressed AVI to RGB24

All 96 pictures matched FFmpeg 9.1 byte for byte, including RGB555 channel expansion
and the odd BGRA geometry. Seven one-CPU runs cover container reads and conversion
to reusable RGB24 buffers. [Fixture commands](raw-avi-fixtures.json) · [Timing samples](raw-avi-decode.json)

| Input | Swag, ms/picture | FFmpeg 9.1, ms/picture | FFmpeg / Swag time |
| --- | ---: | ---: | ---: |
| BGR24, 1280×720 | 0.630 | 0.783 | 1.24× |
| BGRA, 653×371 | 0.190 | 0.364 | 1.91× |
| RGB555, 960×540 | 0.340 | 1.002 | 2.95× |

### Uncompressed AVI eight-pixel conversion

The RGB555 converter expands eight packed pixels in sixteen-bit lanes and stores
exactly 24 RGB bytes. BGR24 and BGRA now convert two four-pixel groups per
iteration. The tail uses the same scalar conversion. An exhaustive check compared
all 65,536 RGB555 input words against the scalar expansion, including the unused
high bit. All 96 AVI pictures still match FFmpeg 9.1 byte for byte. The AVI and
MP4 native Release selection passed 51 tests.

Eleven rotating single-CPU runs use the same fixtures, with a three-picture warm-up.
[Timing and picture hashes](raw-avi-eight-pixels.json)

| Input | Before, ms/picture | After, ms/picture | Paired time change | FFmpeg 9.1 | FFmpeg / Swag time |
| --- | ---: | ---: | ---: | ---: | ---: |
| BGR24, 1280×720 | 0.368 | 0.362 | −1.8% | 0.486 | 1.35× |
| BGRA, 653×371 | 0.160 | 0.145 | −4.8% | 0.302 | 2.08× |
| RGB555, 960×540 | 0.270 | 0.225 | −14.1% | 0.855 | 3.79× |

## HEVC CABAC look-ahead

The CABAC decoder now shifts the arithmetic offset and the next 32 input bits together.
A marker tracks how many bits remain and triggers a four-byte refill. The reader pads
at the current substream boundary, including WPP row boundaries. Focused tests cover
short refills, overrun detection and reserved initial offsets.

The baseline is `85189292c3`. The initial three-run series found a 3.1% reduction on
4K Main10, a 2.0% reduction on all-intra Main10 and a 7.5% reduction on Main WPP.
Grayscale changed by +0.2% and the camera clip by +1.5%. The first texture measurement
varied from 5.78 to 9.18 ms per picture with the new decoder.

For the WPP and texture clips, five paired repetitions alternated which build ran
first on the same logical CPU. Each invocation used one warm pass followed by four
timed passes. Wall time is the median across the 20 timed observations per build.
Process CPU time is the median across invocations, including warm-up.

| HEVC stream | Before (ms/picture) | After (ms/picture) | Wall time change | Process CPU time change |
| --- | ---: | ---: | ---: | ---: |
| Main10 texture | 5.21 | 4.91 | -5.7% | -3.2% |
| Main 720p WPP | 5.22 | 4.88 | -6.6% | -2.6% |

All 1,073 compared pictures matched FFmpeg across nine inputs. The six new generated
inputs contribute 630 pictures and cover AVC Baseline, High, High 4:4:4 and HEVC WPP,
Main10 all-intra and Main10 texture. The targeted native Release selection passed
111 tests. The first 16-bit look-ahead trial regressed WPP and was dropped.
[Raw observations, quality hashes and fixture commands](cabac.json).

## MPEG-4 Part 2 coefficient decoding and reconstruction

The profile of Simple Profile at 720p assigned 35% of samples to the inverse transform
and 21% to thread-local lookups on the fallible coefficient path. The short coefficient
lookup now returns the run, signed level and final flag directly. Long codes, escapes
and short input tails use the fallible path. Reconstruction rounds, clips and writes
eight samples at a time. Thread-local lookups dropped to 2% of the follow-up profile.

The timings are medians of seven repetitions pinned to one logical CPU, in milliseconds
per picture against baseline `e01b764115`.

| MPEG-4 Part 2 stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Simple Profile 720p | 3.77 | 1.96 | 0.55 | -48.1% | 3.59× |
| Textured intra 640×360 | 3.62 | 2.50 | 0.65 | -31.1% | 3.86× |

Across 420 MPEG-4 pictures, the maximum difference from FFmpeg is three eight-bit
levels and PSNR ranges from 59.94 to 71.95 dB. Those bounds are the same as baseline.
The new Swag build changes 19 of 268,081,920 samples by one level. The Release
compiler fuses an additional multiply-add in the vertical inverse transform after
packing the rounding and changing register allocation.

The same comparison also matched all 42 RealVideo 4.0 pictures from four inputs and
180 AVC and HEVC pictures. The focused native Release selection passed 94 tests.
[Raw timings, picture quality, profile counts and fixture commands](mpeg4.json).

## MPEG-4 Part 2 inverse quantization

Inverse quantization now scales four coefficients at a time for H.263 and for MPEG
with a five-bit quantizer. MPEG restores signs after division, preserves intra DC,
and folds the inter-block mismatch parity across the packed coefficients. The
focused native Release selection passed 82 tests, including a scalar reference
for rounding, clipping and parity.

The medians of five repetitions on one logical CPU compare against `9a5108a037`.
Times are in milliseconds per picture.

| MPEG-4 Part 2 stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Simple Profile 720p | 1.927 | 1.572 | 0.538 | -18.4% | 2.92× |
| Textured intra 640×360 | 2.467 | 2.241 | 0.653 | -9.2% | 3.43× |
| B pictures with MPEG matrices | 1.078 | 0.897 | 0.358 | -16.8% | 2.50× |
| P pictures with MPEG matrices, 720p | 1.682 | 1.403 | 0.548 | -16.6% | 2.56× |

All 420 pictures were byte-exact against the previous Swag build. The maximum sample
difference from FFmpeg was three on Simple Profile, one on textured intra, two on
the B-picture clip and four on the new 720p matrix fixture.
[Raw observations and fixture command](quantization.json).

## MPEG-4 Part 2 single-bit reads

The bit reader now inlines bounded single-bit reads in the variable-length code tree,
escape parsing and macroblock flags. The wider reader uses the same bounded primitive.
An earlier word-read trial regressed the textured intra clip and was dropped.

The medians of seven repetitions on one CPU compare against `44f1e36f64`, in
milliseconds per picture. The runner builds each variant once and launches its
executable directly for the quality and timing passes.

| MPEG-4 Part 2 stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Simple Profile 720p | 1.709 | 1.535 | 0.555 | -10.2% | 2.77× |
| Textured intra 640×360 | 2.539 | 2.250 | 0.628 | -11.4% | 3.58× |
| B pictures with MPEG matrices | 0.953 | 0.903 | 0.377 | -5.2% | 2.39× |
| P pictures with MPEG matrices, 720p | 1.486 | 1.412 | 0.570 | -4.9% | 2.48× |

All 420 pictures were byte-exact against the previous Swag build and 82 native Release
tests passed. The earlier matrix B-picture series was flat. Alternating the two
executables on that clip found 4.2% lower median process CPU time.
[Raw observations and quality hashes](mpeg4-bitreader.json).

## MPEG-4 Part 2 sparse inverse transform

Each row now uses a packed comparison to find its nonzero coefficients. The transform
skips empty rows and consumes the marked frequencies in ascending order. The
butterfly trial that split even and odd frequencies changed sample hashes and gave
smaller gains on three of the four streams in the compared series.

The table gives nine-run medians on one logical CPU, in milliseconds per picture
against `2276babc39`. Both executables use the Release compiler from that revision.

| MPEG-4 Part 2 stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Simple Profile 720p | 1.702 | 1.289 | 0.529 | -24.2% | 2.44× |
| Textured intra 640×360 | 2.175 | 2.008 | 0.639 | -7.6% | 3.14× |
| B pictures with MPEG matrices | 0.889 | 0.811 | 0.353 | -8.8% | 2.30× |
| P pictures with MPEG matrices, 720p | 1.455 | 1.242 | 0.559 | -14.6% | 2.22× |

All 420 pictures were byte-exact against the previous Swag build and all 82 native
Release tests passed. The earlier matched-source run measured gains from 3.6% to
20.7%. [Raw observations and the transform trial](mpeg4-sparse-idct.json).

## Matroska timing coverage

The picture check established a dense display timeline before timing the file-backed
reader. RealVideo uses two warm-up pictures and nine repetitions. MPEG-4 uses the
standard 30 warm-up pictures and five repetitions. The table gives the median in
milliseconds per picture.

| Matroska stream | Swag | FFmpeg | Swag / FFmpeg | Compared pictures |
| --- | ---: | ---: | ---: | ---: |
| RealVideo intra | 0.164 | 0.066 | 2.49× | 11 |
| RealVideo I/P/B | 0.262 | 0.041 | 6.39× | 9 |
| RealVideo adaptive | 0.326 | 0.031 | 10.58× | 9 |
| RealVideo multi-slice | 0.339 | 0.038 | 8.87× | 13 |
| MPEG-4 B pictures with MPEG matrices | 1.377 | 0.380 | 3.62× | 90 |

All RealVideo pictures were byte-exact. The MPEG-4 file differed by at most two levels.
The short RealVideo timings include incremental indexing and describe these small
fixtures. In the I/P/B profile, nearly half the samples fell in motion compensation
and its pixel loads. [Raw timings, quality and profile counts](matroska.json).

## RealVideo motion partitions

RealVideo now prepares motion vectors once per partition. Luma that needs a vertical
filter reuses clipped horizontal-filter rows. Chroma and the special luma diagonal
case reuse their interpolation weights, and bidirectional prediction blends whole
partitions. The new regression test covers visible edges, an entirely out-of-picture
vector, the chroma diagonal phase and destination stride.

The medians of seven repetitions compare against `44f1e36f64` with the Release
compiler built from that revision. Both variants use one logical CPU. Times are in
milliseconds per picture.

| RealVideo stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Repeated I/P/B, 720 pictures | 0.338 | 0.157 | 0.038 | -53.5% | 4.09× |
| Intra | 0.175 | 0.170 | 0.066 | -2.9% | 2.57× |
| I/P/B | 0.264 | 0.128 | 0.042 | -51.7% | 3.02× |
| Adaptive | 0.332 | 0.136 | 0.035 | -59.0% | 3.91× |
| Multiple slices | 0.348 | 0.131 | 0.039 | -62.3% | 3.38× |

The 720-picture stream and the four original clips match FFmpeg byte for byte.
The targeted native Release selection passed 45 tests. A paired check with the earlier
compiler confirmed 43–54% lower process CPU time on the three clips using motion.
The intra-only result was within a few percent in both series.
[Raw timings, hashes and repeat command](realvideo-motion.json).

## RealVideo packed filters and reconstruction

The luma motion filter operates on eight samples per row through its two passes.
The inverse transform applies four column transforms together and transposes the
packed values between passes. Four residuals are added to their prediction bytes
and clipped together. A focused test covers both transform modes, mixed signs
and the coefficient limits.

The medians compare against `dc11f27d57` with one logical CPU. The long I/P/B
stream uses seven repetitions, and the short clips use nine. Times are in
milliseconds per picture.

| RealVideo stream | Before | After | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Repeated I/P/B, 720 pictures | 0.156 | 0.132 | 0.040 | -15.0% | 3.34× |
| Intra | 0.163 | 0.156 | 0.064 | -4.5% | 2.42× |
| I/P/B | 0.137 | 0.110 | 0.042 | -19.6% | 2.65× |
| Adaptive | 0.141 | 0.112 | 0.031 | -20.1% | 3.60× |
| Multiple slices | 0.130 | 0.108 | 0.038 | -16.9% | 2.86× |

All 762 pictures still matched FFmpeg, and 46 native Release tests passed.
In the new I/P/B profile, deblocking accounted for 111 of 492 samples.
[Raw timings, quality and isolated trials](realvideo-simd.json).

## Decoder thread budgets

Swag and FFmpeg were run with budgets of one and four threads on the same four
logical CPUs. The table gives the median of three runs in milliseconds per picture.
The AVC fixture has six H.264 slices in its first picture. The HEVC WPP fixture
has wavefront entry points, and the HEVC 4K Main10 fixture uses a single substream.

| Video stream | Swag 1 | Swag 4 | Swag speedup | FFmpeg 1 | FFmpeg 4 | FFmpeg speedup | Swag / FFmpeg at budget 4 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AVC High, 3840×2160, six slices | 31.42 | 22.98 | 1.37× | 19.15 | 5.68 | 3.37× | 4.05× |
| HEVC Main 720p WPP | 4.84 | 3.08 | 1.58× | 2.95 | 1.68 | 1.75× | 1.83× |
| HEVC Main10, 3840×2076 | 51.49 | 33.50 | 1.54× | 38.45 | 11.34 | 3.39× | 2.96× |

Each budget produced the same 285 pictures as FFmpeg. The serial budgets in this
experiment allowed the same four-core affinity mask as the parallel budgets.
The separate single-core comparisons above used one logical CPU.
[Raw timings, picture hashes and fixture command](thread-budgets.json).

## AVC multi-slice frame lanes

The stream publishes validated slice headers and reference lists before the frame lane
starts entropy decoding. The lane owns each unescaped slice buffer until it finishes.
It decodes the slices in their original order and publishes reference metadata when they
are complete. Single-slice row-by-row reconstruction retains its direct path.

Seven rotating runs per fixture compare against the preceding decoder. Times are median
milliseconds per picture. The 4K fixture uses six slices, and both controls use one slice.

| AVC input and thread budget | Swag before | Swag after | FFmpeg | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: |
| 4K six slices, four threads | 18.48 | 13.92 | 5.22 | 2.67× |
| 1080p High, four threads | 5.02 | 4.31 | 1.61 | 2.67× |
| 960×540 Baseline, four threads | 2.51 | 2.43 | 0.69 | 3.54× |
| 4K six slices, one thread | 30.17 | 29.71 | 17.34 | 1.71× |
| 1080p High, one thread | 7.57 | 7.81 | 5.04 | 1.55× |
| 960×540 Baseline, one thread | 4.99 | 4.73 | 2.00 | 2.36× |

The 4K multi-slice change reduced four-thread wall time by 24.7%. A separate five-run
trial of the deferred path measured 33.6%. The single-thread 1080p control had overlapping
run ranges and a 3.2% higher group median, while five of its seven paired observations
were faster. All 405 pictures matched FFmpeg byte for byte at both budgets. The H.264,
MP4 and Matroska Release selection passed 104 tests. [Raw timings and hashes](avc-deferred-slices.json)

## RealVideo reference buffers and DC-only reconstruction

The decoder recycles the old reference and the caller's released output planes. A block
with no coded residual keeps its prediction. A luma block with only a DC coefficient
adds the exact constant left by both transform passes. A new test checks signed rounding,
clipping and row padding against the complete transform.

The medians are milliseconds per picture on one logical CPU with nine rotating runs.
The long stream warms up for 30 pictures and the short streams warm up for two.

| RV40 input | Swag before | Swag after | FFmpeg | Swag time change | Swag after / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| Repeated I/P/B, 720 pictures | 0.135 | 0.118 | 0.037 | −12.2% | 3.21× |
| Intra | 0.154 | 0.136 | 0.062 | −11.5% | 2.21× |
| I/P/B | 0.120 | 0.100 | 0.043 | −16.5% | 2.31× |
| Adaptive | 0.109 | 0.097 | 0.033 | −11.1% | 2.91× |
| Multiple slices | 0.109 | 0.097 | 0.039 | −11.2% | 2.48× |

All 762 pictures match FFmpeg byte for byte. The RealVideo and Matroska selection passed
47 native Release tests. [Individual timings and decoded hashes](realvideo-reference-reuse.json)

## Reproduce

The [workload](../../../workloads/videodecode/README.md) contains the benchmark and generation
commands for the four synthetic inputs. To build the before variant with the same compiler,
extract `bin/std` from commit `6ba8702c7b` with `git archive` and pass the extracted `bin`
directory as `--baseline-bin`. The fifth input is a Main10 transcode of the repository's
public-domain camera recording.

```sh
ffmpeg -v error -threads 1 -filter_threads 1 \
    -i bin/std/modules/video/src/tests/datas/cogliati-turning-pages.avi -vf scale=960:720 \
    -an -c:v libx265 -threads 1 -preset fast -pix_fmt yuv420p10le -crf 22 \
    -x265-params pools=none:frame-threads=1:wpp=0:keyint=60:scenecut=0:log-level=error \
    /tmp/swag-video-fixtures/hevc-turning-pages.mp4
```
