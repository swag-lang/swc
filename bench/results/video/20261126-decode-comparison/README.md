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
