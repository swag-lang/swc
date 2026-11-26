# Single-lane video decoding against FFmpeg

`compare.py` compares planar H.264, HEVC, MPEG-4 Part 2 and RealVideo 4.0 through
`Video.Reader` in Release.
It needs the built Swag compiler and its runtime, Python 3.11 or newer with NumPy, and FFmpeg
and ffprobe. Timing also needs a C compiler, pkg-config and the FFmpeg development libraries
`libavformat`, `libavcodec` and `libavutil`. Use `--quality-only` for the picture comparison
alone or `--reference` to use an independently built `ffmpeg_native` from this workload.

For comparable timings, generate single-slice MP4 clips on the same FFmpeg installation and
pin the benchmark to one otherwise idle logical CPU.

```sh
clips=/tmp/swag-video-fixtures
mkdir -p "$clips"

for profile in baseline high; do
    ffmpeg -v error -f lavfi -i testsrc2=size=1920x1080:rate=30 -frames:v 180 \
        -an -c:v libx264 -threads 1 -preset fast -profile:v "$profile" -crf 20 \
        -x264-params slices=1:keyint=60:scenecut=0 "$clips/avc-$profile.mp4"
done

hevc_options=pools=none:frame-threads=1:wpp=0:keyint=60:scenecut=0:log-level=error
ffmpeg -v error -filter_threads 1 -f lavfi -i testsrc2=size=1920x1080:rate=30 \
    -frames:v 180 -an -c:v libx265 -threads 1 -preset fast -pix_fmt yuv420p10le -crf 22 \
    -x265-params "$hevc_options" "$clips/hevc-main10.mp4"
ffmpeg -v error -filter_threads 1 -f lavfi -i testsrc2=size=3840x2076:rate=24 \
    -frames:v 90 -an -c:v libx265 -threads 1 -preset fast -pix_fmt yuv420p10le -crf 22 \
    -x265-params "$hevc_options" "$clips/hevc-main10-4k.mp4"

taskset -c 4 python3 bench/workloads/videodecode/compare.py \
    --compiler /absolute/build/release/swc \
    --baseline-bin /absolute/baseline-source/bin \
    --output /tmp/swag-video-results "$clips"/*.mp4
```

`--baseline-bin` selects a preserved standard-module source tree and is optional.
Both Swag variants use the same compiler and runtime. The output directory must be new and
outside the source trees. It receives the picture hashes, timing samples, FFmpeg version,
reference timestamps and individual run logs.

Generate additional inputs with `generate.py`. The corpus covers gradient fades for weighted
AVC prediction, temporal texture for CAVLC, AVC High 4:4:4, HEVC Main with WPP, and Main10
intra-only and textured inter pictures. The MPEG-4 inputs include Simple Profile at 720p,
textured intra pictures, and both P and B pictures with MPEG quantization matrices.
The manifest records each command and input hash.

```sh
python3 bench/workloads/videodecode/generate.py --output /tmp/swag-video-expanded
python3 bench/workloads/videodecode/compare.py \
    --compiler /absolute/build/release/swc --quality-only \
    --output /tmp/swag-video-expanded-quality /tmp/swag-video-expanded/*.mp4

taskset -c 4 python3 bench/workloads/videodecode/compare.py \
    --compiler /absolute/build/release/swc --mpeg4-max-sample-difference 4 \
    --output /tmp/swag-video-mpeg4 /tmp/swag-video-expanded/*.avi
```

The quality pass uses FFmpeg's best-effort presentation timestamps relative to the earliest
video packet PTS. This is the same origin as the sample timeline in `Reader`, so coded
pictures omitted by FFmpeg can be skipped even at the start of the file. The Swag driver
opens the input in memory to index the complete timeline and looks up each corresponding
display rank. Unique timestamps within half a microsecond are
required. The driver writes visible Y, Cb and Cr planes. The comparison counts changed samples
and reports the maximum difference and PSNR. For Main10 the reference is first decoded to
native ten-bit samples, then rounded and saturated to the same eight-bit presentation
layout that `Reader` exposes. The module's separate HEVC conformance tests check the native
Main10 picture digests.

By default every codec requires exact sample equality. MPEG-4 Part 2 implementations
use different inverse transforms, so its comparison accepts an explicit
`--mpeg4-max-sample-difference` in eight-bit sample levels. The report always includes
the observed sample differences, PSNR and Swag plane hash.

Timed inputs need one picture per display rank. The quality pass verifies this using the
complete index. The timed pass uses that validated count for formats such as Matroska whose
file-backed reader indexes lazily. Each pass opens the file, decodes the first 30 pictures
by default, and decodes the remaining pictures sequentially. Use `--warmup` for shorter
clips. A separate untimed pass warms the process and file cache. The timer excludes
startup, compilation, opening the container, the warmup pictures and output serialization.
The Python runner rotates Swag and FFmpeg runs between repetitions and reports the median
wall time per picture. Each implementation has one decode lane. FFmpeg uses its decoded
native frames, while Swag's public reader writes to reusable eight-bit planes. The FFmpeg
run with CPU flags cleared is diagnostic. Native FFmpeg is the performance reference.

This fixture starts with four HEVC samples that FFmpeg never emits as pictures. The comparison
still matches all 30 displayed pictures by presentation time.

```sh
python3 bench/workloads/videodecode/compare.py --compiler /absolute/build/release/swc \
    --quality-only --output /tmp/swag-video-edited \
    bin/std/modules/video/src/tests/datas/edited-open-group-start.mkv
```

Time the short RealVideo inputs with two warm-up pictures and a freshly built
`ffmpeg_native`.

```sh
taskset -c 4 python3 bench/workloads/videodecode/compare.py \
    --compiler /absolute/build/release/swc --warmup 2 --repetitions 9 \
    --output /tmp/swag-video-rv40 \
    bin/std/modules/video/src/tests/datas/rv40-{intra,ipb,adaptive,slices}.mkv
```

For a longer timing window, repeat the checked-in RealVideo I/P/B clip in Matroska.
The script preserves the codec configuration and copies the encoded packets.

```sh
python3 bench/workloads/videodecode/repeat-rv40.py --output /tmp/swag-rv40-repeat.mkv
taskset -c 4 python3 bench/workloads/videodecode/compare.py \
    --compiler /absolute/build/release/swc --output /tmp/swag-rv40-repeat-results \
    /tmp/swag-rv40-repeat.mkv
```
