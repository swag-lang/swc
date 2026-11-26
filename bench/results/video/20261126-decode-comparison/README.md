# H.264 and HEVC decode comparison

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
