# Y4M writer comparison

This Linux workload converts the same bottom-up RGB8 pictures with Swag's in-memory
`Video.Writer` and the FFmpeg libswscale BT.601 limited-range conversion. The Swag
runs also use equivalent BGRA8 input. Both timers include conversion and appending
converted planes to memory. The harness writes the files after timing. It verifies
file hashes for two Swag revisions and compares raw samples with the native reference.

Build a Release Swag compiler and install the libswscale and libavutil development
headers, Python 3.11 or later and NumPy. Generate the RGB input using the [H.264 fixture
generator](../h264/README.md).

```sh
cc -O2 bench/workloads/y4m/y4m_native.c -o /tmp/y4m_native \
    $(pkg-config --cflags --libs libavutil libswscale)
taskset -c 0 python3 bench/workloads/y4m/compare.py \
    --compiler /absolute/build/release/swc --native /tmp/y4m_native \
    --width 640 --height 360 --frames 30 --output /tmp/y4m-comparison \
    /tmp/h264-input/street.rgb
```

`--baseline-bin` adds the `bin` tree from a preserved Swag source revision. `--layout`
selects one or more of 411, 420, 422 and 444. With no layout option the comparison runs
all four. libswscale uses area chroma resampling. Y4M stores the same uncompressed
payload size at each resolution and layout regardless of color-conversion arithmetic.
