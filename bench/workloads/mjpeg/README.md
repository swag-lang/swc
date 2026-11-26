# Motion JPEG encoder comparison

This Linux workload times the JPEG encoder used for Swag's AVI and MP4 video frames,
FFmpeg's Motion JPEG encoder, and libjpeg-turbo. They read the same bottom-up, tightly
packed RGB8 pictures and produce full-range, baseline 4:4:4 JPEG packets. The timers
include color conversion and in-memory packet creation. The harness writes the packets
as concatenated JPEG images after the timer and decodes them with FFmpeg.

Build a Release Swag compiler with its runtime. The reference helper needs libavcodec,
libavutil, libswscale and libjpeg-turbo development headers. Generate the RGB corpus with
the [H.264 workload's generator](../h264/README.md).

```sh
cc -O2 bench/workloads/mjpeg/mjpeg_native.c -o /tmp/mjpeg_native \
    $(pkg-config --cflags --libs libavcodec libavutil libswscale libjpeg)
taskset -c 0 python3 bench/workloads/mjpeg/compare.py \
    --compiler /absolute/build/release/swc --reference /tmp/mjpeg_native \
    --width 640 --height 360 --frames 30 --repetitions 5 --output /tmp/mjpeg-comparison \
    /tmp/h264-input/{desktop,gradient,testsrc,street}.rgb
```

The runner rotates encoder order on each repetition and checks the packet hashes.
PSNR and SSIM use decoded raw RGB in frame order. A lossless shifted-timestamp control
checks the RGB orientation and metric agreement. JPEG quality and FFmpeg QP use different
scales. Compare packet bytes at shared measured RGB PSNR instead of matching settings.
`--library-bin` selects the library source snapshot used to build the Swag driver.

## Motion JPEG decoding

Use the [video RGB workload](../videodecode/README.md) to compare decoding and conversion
to RGB24. `decode_native.c` reads the same AVI or MP4 packets through libavformat and
uses libjpeg-turbo with nearest-neighbour chroma sampling and a reused RGB24 buffer.

```sh
cc -O2 bench/workloads/mjpeg/decode_native.c -o /tmp/jpeg_turbo_decode \
    $(pkg-config --cflags --libs libavformat libavcodec libavutil libjpeg)
python3 bench/workloads/videodecode/generate.py --rgb --output /tmp/video-rgb
taskset -c 0 python3 bench/workloads/videodecode/compare.py --rgb --warmup 6 \
    --compiler /absolute/build/release/swc --jpeg-reference /tmp/jpeg_turbo_decode \
    --output /tmp/mjpeg-decode-results /tmp/video-rgb/mjpeg-*.avi
```
