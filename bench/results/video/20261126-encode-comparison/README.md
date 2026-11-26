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
