# Video encoding comparison — 2026-11-26

## H.264 at a common CPU budget

Swag Release and libx264 from FFmpeg 7.1.5 encoded the same BT.709 NV12 samples on an
AMD EPYC 9V74. Four 640×360 clips cover scrolling desktop text, changing color tiles, the
`testsrc2` motion pattern and a camera clip from the Video test data. Each clip has 30 pictures
at 30 fps. The encoders use four slices, a 120-picture GOP and a nominal three-thread budget.
The x264 build is core 164 r3108 (`31e19f9`). Its Baseline QP mode uses frame threads, while
Swag works on slices within a picture. The x264 timer includes its delayed frames at drain.
Both timers exclude source conversion, the container and decoding.

The sweep covers QP or CRF 21, 25, 29 and 33 for each implementation. Every Swag output was
decoded independently by Swag and FFmpeg. All 480 reconstructed pictures matched byte for byte
between the decoders. A tagged lossless FFV1 control with shifted timestamps scored infinite
PSNR and SSIM 1. [Raw results and source hashes](measurements.json)

### Packet size at equal luminance PSNR

Each reference column uses the midpoint of its shared measured PSNR range with Swag.
Packet sizes are interpolated linearly in log space between adjacent points. The comparisons
use measured luma PSNR, and the JSON also provides the chroma PSNR and SSIM measurements.

| Input | Swag vs x264 Baseline veryfast QP | Swag vs x264 High veryfast CRF | Swag vs x264 Baseline ultrafast CRF |
| --- | ---: | ---: | ---: |
| Scrolling desktop | −20.5% at 40.07 dB | +10.6% at 38.11 dB | −29.9% at 40.59 dB |
| Changing tiles | −6.7% at 44.76 dB | No shared range | +90.6% at 44.76 dB |
| Animated test pattern | +13.4% at 46.22 dB | +21.9% at 42.38 dB | −4.7% at 46.26 dB |
| Camera | +4.9% at 40.76 dB | +24.2% at 39.83 dB | −54.9% at 39.10 dB |

On the changing tiles, x264 High at CRF 33 reaches 50.85 dB with 43,422 packet bytes.
The highest measured Swag quality there is 47.00 dB at QP 21, with 131,497 bytes.
The benchmark measures a software encoder's throughput on short clips. Its anchors do
not measure hardware encoders, capture cadence or 4K60.

### Encode wall time

Each QP/CRF 25 point is the median of seven runs on the same three CPUs. The run order
alternated between Swag-first and x264-first. These are fixed-setting throughput measurements.
The equal-PSNR table uses separate interpolated points and should be used for rate comparisons.

| Input | Swag QP 25 | x264 Baseline veryfast QP 25 | x264 High veryfast CRF 25 | x264 Baseline ultrafast CRF 25 |
| --- | ---: | ---: | ---: | ---: |
| Scrolling desktop | 48.19 ms | 21.79 ms | 45.52 ms | 15.78 ms |
| Changing tiles | 111.39 ms | 45.70 ms | 65.16 ms | 16.72 ms |
| Animated test pattern | 56.66 ms | 21.71 ms | 52.05 ms | 15.03 ms |
| Camera | 158.75 ms | 65.52 ms | 105.57 ms | 22.59 ms |

At the shared Baseline profile and fixed QP, x264 veryfast was 2.21–2.61× as fast
across the clips. The JSON includes individual timing samples and x264 process CPU times.

### SIMD motion profiles and transform scores

Swag now keeps the 16×16 Hadamard score in vector lanes until its final reduction and
sums and compares the motion estimator's column profiles in packed groups. Every scoring
operation keeps the original integer result and vector tie-breaking. Seven rotating runs
at QP 25, four slices and three CPUs each encoded six independent 30-picture sequences.
The changes were measured together and individually.

| Input | Baseline wall, 180 pictures | SIMD wall, 180 pictures | Median paired wall change | Median paired process CPU change |
| --- | ---: | ---: | ---: | ---: |
| Scrolling desktop | 290.87 ms | 233.93 ms | −16.4% | −11.5% |
| Changing tiles | 696.32 ms | 632.70 ms | −11.8% | −13.1% |
| Animated test pattern | 329.72 ms | 257.09 ms | −20.2% | −19.6% |
| Camera | 954.27 ms | 833.41 ms | −11.3% | −9.9% |

The four-clip sweep at QPs 21, 25, 29 and 33 produced identical MP4 files. A 650×370 clip
with partial edge macroblocks did so at QPs 1, 25 and 51 with one and eight slices. The resulting 552 pictures
matched FFmpeg's independent decoded planes byte for byte, and
23 focused native Release tests passed. [Individual timings and equality checks](h264-simd.json)

### SIMD 4×4 quantization

The AVC encoder quantizes and inverse-scales four coefficients at a time, packs the
zigzag levels and transposes the reconstruction coefficients in vector lanes. Repeating
the same four-slice QP 25 CPU experiment gives the following results against the motion
profile optimization above.

| Input | Median paired wall change | Median paired process CPU change |
| --- | ---: | ---: |
| Scrolling desktop | −9.2% | −12.7% |
| Changing tiles | −10.8% | −4.6% |
| Animated test pattern | −6.8% | −6.9% |
| Camera | −10.9% | −11.4% |

The 552-picture corpus again retains byte-identical MP4 output, including QP 1 and 51
and partial macroblocks with one and eight slices. All decoded sample planes match
FFmpeg. The targeted Release selection passed 23 tests. [Measurements](h264-quantize-simd.json)

### SIMD whole-sample motion scoring

The encoder accumulates wide SAD lanes, checks the first row separately for a cheap
rejection, reduces the remaining rows in pairs and compares vertical motion profiles in
packed groups. A separate packed loop splits the NV12 chroma row into Cb and Cr and
keeps a scalar tail for cropped macroblocks. Motion scores below the rejection bound
and tie-breaking retain their original values.

Seven rotated repetitions used one CPU and one slice at QP 25. Each timed run encoded
six independent sequences of 30 pictures. The baseline uses the encoder from `f754ca61c6`.

| Input | Median paired wall change | Median paired process CPU change |
| --- | ---: | ---: |
| Scrolling desktop | −11.8% | −11.8% |
| Changing tiles | −15.9% | −14.9% |
| Animated test pattern | −15.0% | −16.3% |
| Camera | −7.7% | −8.3% |

The four-clip QP sweep and the 650×370 one- and eight-slice cases produced the same MP4
bytes on all 552 pictures. Their independently decoded planes match FFmpeg. All 23
focused native Release tests passed. [Measurements](h264-motion-sad.json)

### Reproduction

Build the Linux Release compiler and the native x264 reference using the [workload
instructions](../../../workloads/h264/README.md). The Swag encoder and compiler snapshots in
this run are from `2276babc39`.

```sh
python3 bench/workloads/h264/generate.py --output /tmp/h264-input \
    --font /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf \
    --camera bin/std/modules/video/src/tests/datas/cogliati-turning-pages.avi
taskset -c 0-2 python3 bench/workloads/h264/compare.py \
    --compiler /absolute/build/release/swc --x264-native /tmp/x264_native \
    --input /tmp/h264-input/{desktop,gradient,testsrc,street}.rgb \
    --width 640 --height 360 --frames 30 --slices 4 --qp 21 25 29 33 \
    --output /tmp/h264-measurements
```

### H.264 at 1080p and 4K

Three additional clips use the same encode-only method and a three-CPU budget. The
camera clip scales the repository's camera sample to 1920×1080. The motion patterns
come from `testsrc2` at their native resolutions. The 1080p clips contain 12 pictures
and the 4K clip contains eight. The results include each clip's initial key picture.
All 96 Swag pictures match FFmpeg's independent decoded planes.

| Input | Swag QP 25 | Baseline veryfast QP 25 | High veryfast CRF 25 | Baseline ultrafast CRF 25 |
| --- | ---: | ---: | ---: | ---: |
| 1080p animated pattern | 12.43 ms | 4.93 ms | 12.45 ms | 3.44 ms |
| 1080p camera | 38.21 ms | 15.64 ms | 34.65 ms | 6.15 ms |
| 4K animated pattern | 53.85 ms | 19.00 ms | 46.53 ms | 12.14 ms |

Times are per picture, using the median of seven rotating encode runs. At the shared
Baseline profile and QP, x264 veryfast is 2.44–2.83× as fast. On the three-point
rate-quality curves, Swag needs 7.2% more packet bytes on the animated 1080p clip at
49.58 dB and 13.9% more on the camera at 46.34 dB than x264 Baseline veryfast.
On the 4K pattern Swag uses 1.6% fewer bytes at 49.68 dB. High veryfast uses fewer
bytes on the camera at equal luma PSNR, where Swag uses 51.2% more. The tested
High CRF points and Swag QP points on the animated patterns have no shared PSNR range.
[Raw results and source hashes](h264-hd-reference.json)

```sh
ffmpeg -v error -f lavfi -i 'testsrc2=size=1920x1080:rate=30' \
    -vf vflip -pix_fmt rgb24 -threads 1 -frames:v 12 -f rawvideo /tmp/testsrc1080p.rgb
ffmpeg -v error -ss 2 -i bin/std/modules/video/src/tests/datas/cogliati-turning-pages.avi \
    -vf scale=1920:1080,vflip -pix_fmt rgb24 -threads 1 -frames:v 12 -f rawvideo /tmp/camera1080p.rgb
ffmpeg -v error -f lavfi -i 'testsrc2=size=3840x2160:rate=30' \
    -vf vflip -pix_fmt rgb24 -threads 1 -frames:v 8 -f rawvideo /tmp/testsrc4k.rgb
```

Use QPs 21, 25 and 29 with `--discard-planes` in the H.264 workload to retain
the compressed files, decoded hashes and quality results with lower disk usage.

#### Current x264 timing

The same sources and settings were measured again with Swag's packed motion scoring
and x264 `c24e06c` linked through FFmpeg 9.1. All 96 Swag pictures match the independent
FFmpeg decoder, and the rate-distortion points are unchanged at the displayed precision.
Each timing is the median of seven rotated runs with three CPUs.
[Current reference measurements](h264-hd-current-x264.json)

| Input | Swag QP 25 | Baseline veryfast QP 25 | High veryfast CRF 25 | Baseline ultrafast CRF 25 |
| --- | ---: | ---: | ---: | ---: |
| 1080p animated pattern | 11.52 ms | 5.78 ms | 14.66 ms | 3.70 ms |
| 1080p camera | 35.60 ms | 17.77 ms | 38.23 ms | 6.98 ms |
| 4K animated pattern | 53.04 ms | 20.26 ms | 48.78 ms | 13.80 ms |

The matched Baseline settings put the 1080p clips at about twice x264's time and the
4K clip at 2.62 times. These batches include the first key picture.

### H.264 adaptive bitrate across scene changes

The [adaptive-rate workload](../../../workloads/h264/README.md#adaptive-bitrate) joins 240
640×360 frames of scrolling desktop, changing tiles, camera and a return to the desktop.
It compares the software recorder with x264 Baseline veryfast from FFmpeg 9.1, using
identical BT.709 NV12, four slices and two CPUs. Each encoder receives the same requested
bitrate and a half-second buffer budget. The quality pass validates all packet timestamps,
then compares decoded luma samples in display order. [Packet and QP traces](h264-adaptive-rate.json)

| Target | Swag actual | x264 actual | Swag luma PSNR | x264 luma PSNR |
| --- | ---: | ---: | ---: | ---: |
| 0.8 Mbit/s | 0.832 Mbit/s | 0.769 Mbit/s | 40.78 dB | 40.45 dB |
| 1.5 Mbit/s | 1.502 Mbit/s | 1.421 Mbit/s | 43.34 dB | 44.52 dB |
| 2.5 Mbit/s | 2.473 Mbit/s | 2.333 Mbit/s | 44.87 dB | 47.96 dB |

The biggest 2.5 Mbit/s quality difference is in the changing tiles. The camera segment
has similar luma PSNR. The measurements include achieved bitrate because the two
controllers spend different numbers of bits at the same requested rate.

## Motion JPEG 4:4:4

The same four RGB clips were encoded with the JPEG codec used by Swag's AVI and MP4
writers, FFmpeg MJPEG with its default optimal Huffman tables, and libjpeg-turbo 2.1.5.
All three use baseline 4:4:4 sampling. One pinned CPU encoded each clip at four settings,
with five repetitions in rotating order. The timers include RGB conversion and packet
creation. The lossless RGB control had infinite PSNR and SSIM 1. All 1,440 pictures
decoded in FFmpeg and packet hashes were stable between repetitions.

Each column below compares packet bytes and total process CPU time at the midpoint of
its shared measured RGB PSNR range with Swag. The interpolation is logarithmic for bytes
and linear for median CPU time.

| Input | Swag vs libjpeg-turbo bytes | Swag / libjpeg-turbo CPU | Swag vs FFmpeg bytes | Swag / FFmpeg CPU |
| --- | ---: | ---: | ---: | ---: |
| Scrolling desktop | +0.4% at 35.39 dB | 2.90× | +19.1% at 33.55 dB | 1.35× |
| Animated test pattern | +2.9% at 42.31 dB | 2.92× | +33.8% at 40.33 dB | 1.60× |
| Camera | +65.2% at 43.94 dB | 3.03× | +53.5% at 42.71 dB | 1.54× |

The changing tiles have no shared quality range at the sampled settings. Swag plateaus
at 46.56 dB from quality 60 through 95. libjpeg-turbo reaches 52.96 dB at quality 80, and
FFmpeg reaches 52.95 dB at QP 3 through 12. This clip isolates a conversion or reconstruction
floor that increasing the JPEG quality setting leaves unchanged.
[Measurements](mjpeg-baseline.json) · [Reproduction](../../../workloads/mjpeg/README.md)

### Motion JPEG color rounding

The encoder now rounds the fixed-point RGB dot products to the closest sample. Chroma
uses the JPEG half-step bias to stay in the signed sample range, and the rounded
chroma coefficients sum to zero for neutral colors.

| Input and Swag quality | RGB PSNR before | RGB PSNR after | Packet bytes change |
| --- | ---: | ---: | ---: |
| Scrolling desktop, 95 | 43.82 dB | 44.75 dB | +0.82% |
| Changing tiles, 60 | 46.56 dB | 52.96 dB | +0.01% |
| Animated test pattern, 95 | 49.08 dB | 52.48 dB | +0.04% |
| Camera, 95 | 44.99 dB | 49.56 dB | −0.60% |

All 16 measured points gain RGB PSNR. On the saturated test pattern at quality 95,
FFmpeg's RGB SSIM falls from 0.99384 to 0.94069. An independent uniform-window
SSIM calculation also falls, from 0.99887 to 0.99168. The maximum RGB error stays
at 12 levels. Of the source's 3.20 million zero-valued green samples, about 1.04
million decode to one after the rounding change, up from 48,296. The desktop,
changing tiles and camera have similar or higher SSIM. Packet size changes stay
below 0.83% across the sweep. The JPEG, AVI and MP4 Release selection passed 86 tests.
[Individual measurements and saturation check](mjpeg-rounding.json)

### Motion JPEG uniform blocks

An eight-by-eight block with identical RGB pixels now emits the three DC values
and end-of-block codes directly. A few spaced comparisons reject the shortcut
quickly in textured blocks. The full comparison covers all 64 pixels before
skipping color conversion and the transform.

Five rotating runs per quality used one logical CPU and the same four 30-frame clips.
Paired CPU time fell by 18–28% on the desktop, 78–79% on the changing tiles and
57–60% on the animated test pattern. The camera stayed within 1.8% in either
direction. All 480 encoded pictures and their FFmpeg decodes matched byte for byte.
The JPEG, AVI and MP4 Release selection passed 86 tests.
[Individual results](mjpeg-flat-blocks.json)

## Y4M planar output

Swag now writes luma and accumulates chroma while reading each RGB pixel once. It
keeps the original limited-range coefficients and averages the same rounded chroma
samples within each layout's footprint. RGB8 and BGRA8 produced identical Y4M files,
and the same files as the previous Swag writer.

Process CPU time is the median of seven rotating runs encoding a 30-picture 640×360
camera clip on one logical CPU. The libswscale comparison converts and copies planes
in memory. Swag's measurements also include its in-memory container writes.

| Chroma | Swag RGB8 before | Swag RGB8 after | FFmpeg RGB8 | Swag BGRA8 before | Swag BGRA8 after |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4:1:1 | 89.45 ms | 36.24 ms | 26.19 ms | 85.36 ms | 35.76 ms |
| 4:2:0 | 90.33 ms | 37.33 ms | 27.40 ms | 88.46 ms | 38.49 ms |
| 4:2:2 | 95.66 ms | 42.59 ms | 28.25 ms | 93.86 ms | 43.70 ms |
| 4:4:4 | 108.97 ms | 46.30 ms | 20.62 ms | 107.81 ms | 48.99 ms |

The optimized writer reduces CPU time by 53–60% on the camera clip. A second
652×370 input exercises the layout tails. Across both inputs and all RGB8 layouts,
every Swag sample differs from FFmpeg's conversion by at most one level. All 18
focused native Release tests passed.
[Timing samples and hashes](y4m-fused-conversion.json) · [Reproduction](../../../workloads/y4m/README.md)

### Packed Y4M conversion

Four source pixels share the channel unpacking and color arithmetic. Chroma sums
and rounds the same one, two or four samples as the fused scalar version. The
final scalar group also handles RGB24 rows with fewer than 16 readable bytes.
All four packed RGB input orders and varying alpha values agree in the focused test.

| Chroma | Scalar RGB8 | Packed RGB8 | FFmpeg RGB8 | Scalar BGRA8 | Packed BGRA8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 4:1:1 | 35.48 ms | 16.34 ms | 25.35 ms | 35.94 ms | 16.62 ms |
| 4:2:0 | 35.53 ms | 15.12 ms | 26.22 ms | 36.30 ms | 16.06 ms |
| 4:2:2 | 47.74 ms | 18.41 ms | 28.65 ms | 42.75 ms | 19.40 ms |
| 4:4:4 | 46.43 ms | 21.40 ms | 21.83 ms | 47.26 ms | 23.95 ms |

The medians from seven one-CPU runs on the same 30-picture camera clip show a
further 49–61% CPU reduction. The RGB8 4:1:1, 4:2:0 and 4:2:2 cases are 1.55–1.73×
as fast as the measured libswscale reference. The two 4:4:4 timings are close.
The 640×360 and 652×370 Y4M files are byte-identical to the scalar writer. The
19 focused Release tests passed. [Timing samples and hashes](y4m-packed-conversion.json)
