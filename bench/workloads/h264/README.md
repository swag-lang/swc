# H.264 recording quality

`compare.py` runs the portable Swag encoder and FFmpeg's x264 on identical input and retains
the files, decoded planes, commands, logs and a JSON report in a new external directory.
It needs a built Swag compiler with its runtime, Python 3, FFmpeg and ffprobe with libx264.

Input is a sequence of bottom-up, tightly packed RGB8 pictures at 30 frames per second. For
example, convert a representative recording, outside the checkout:

```sh
ffmpeg -i recording.mp4 -frames:v 30 -vf scale=640:360,vflip -pix_fmt rgb24 -f rawvideo /tmp/input.rgb
python3 bench/workloads/h264/compare.py --compiler /absolute/build/release/swc \
  --input /tmp/input.rgb --width 640 --height 360 --frames 30 --qp 18 26 28 \
  --output /tmp/h264-baseline
```

`generate.py --output /tmp/h264-input --font /absolute/monospace.ttf` makes three deterministic
640x360, 30-picture inputs: scrolling text under a moving window, changing coloured tiles, and
FFmpeg's `testsrc2`. It needs Pillow in addition to FFmpeg. An optional `--camera clip.avi` adds a
resized camera sequence. The manifest records input, font and camera hashes and FFmpeg commands.

Pass several paths after `--input` to process a corpus with the same dimensions and picture count.
All pictures and QPs run in one native invocation, with shared standard libraries staged by the
compiler's `run` command. This avoids recompiling the driver for every point.

`--quality-only` omits timing results and can
collect deterministic size, PSNR and SSIM while other builds are running: every input picture is
encoded, without wall-clock pacing or dropped slots. The Swag compiler, runtime and x264 use three
workers. The default four slices and 120-picture key interval are held constant for comparison;
they are experimental controls, not a claim to reproduce every capture tool's defaults.

The driver converts RGB to BT.709 NV12 once, before timing, and saves precisely those samples
for the external encoders and metrics. Allocation, conversion, container writes and decoding are
outside Swag's encode timer. x264's process duration includes startup, encoding and muxing and
must not be compared directly with that timer. Both packet bytes and container bytes are reported.
The driver decodes every Swag picture with `Video.Reader`; the helper fails if any byte differs
from FFmpeg's planar output. The helper unpacks the NV12 reference to planar YUV with byte
operations, then measures PSNR and SSIM on two raw planar sequences in picture order. This avoids
unintended colour conversion from metadata negotiation and timestamp alignment errors. A lossless
BT.709-tagged FFV1 picture with a shifted timestamp must first score infinite PSNR and SSIM 1.
Quality numbers at the same QP/CRF are not equivalent:
compare rate versus measured quality across multiple points and several types of content.

The x264 configurations deliberately distinguish codec restrictions from product choices:

| Configuration | Purpose |
| --- | --- |
| Baseline, veryfast, fixed QP | Same codec profile as Swag, without CABAC or B pictures |
| High, veryfast, CRF | Software recording profile described by [OBS](https://obsproject.com/kb/advanced-recording-settings-guide) |
| Baseline, ultrafast, CRF | Preset and quality mode in [ShareX's defaults](https://github.com/ShareX/ShareX/blob/develop/ShareX.ScreenCaptureLib/ScreenRecording/FFmpegOptions.cs) |

[Bandicam](https://www.bandicam.com/support/tips/hardware-acceleration/) also supports hardware
H.264, HEVC and AV1 through NVIDIA, Intel and AMD. These require a compatible device for a useful
measurement; software x264 timings cannot stand in for hardware throughput or efficiency.
This benchmark measures encoding, not screen acquisition, audio, the recorder queue or missed
capture slots. Test the real capture path separately before claiming a capture frame rate.

For a before/after comparison, keep the compiler, input, QPs, slice count and worker limit fixed.
Keep the compiler's runtime installation fixed as well. Rebuilding the compiler invalidates
previously built dependencies, even when its source version is unchanged.
Repeat with a new `--output` and `--skip-x264`. Compare the source hashes first. For a change
intended to preserve quality exactly, compare the decoded hashes as well as sizes. Repeated
measurements are needed before interpreting small timing differences.
`--library-bin` selects the `bin` tree of an external source snapshot for a preserved baseline.
