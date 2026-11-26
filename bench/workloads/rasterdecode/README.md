# Raster decode comparison

Build the same benchmark source against each standard library you want to compare. Use an
external output and work directory for each build. An externally built Linux compiler needs
the runtime beside it and `SWAG_PATH` pointing to the intended `bin` directory. See the
[Linux compiler guide](../../../tools/README.md#linux-compiler-build).

```sh
swc build -d bench/workloads/rasterdecode/src \
  --module-file bench/workloads/rasterdecode/module.swg -bc release \
  -n rasterdecode --out-dir /tmp/rasterdecode/out --work-dir /tmp/rasterdecode/work

python3 bench/workloads/rasterdecode/make_corpus.py \
  --photo /path/to/sample.png --output /tmp/rasterdecode/corpus

python3 bench/workloads/rasterdecode/run.py \
  --candidate /tmp/rasterdecode/out/rasterdecode \
  --baseline /path/to/baseline/rasterdecode \
  --magick-wand libMagickWand-7.Q16HDRI.so.10 --libwebp libwebp.so.7 \
  --output /tmp/rasterdecode/results.json /tmp/rasterdecode/corpus/*
```

Use Python 3.11 or later and ImageMagick 7. Set `MAGICK_CODER_MODULE_PATH` and
`MAGICK_CONFIGURE_PATH` if your shared library uses modules outside its normal search path.
Select an HDRI build to compare floating-point images without clamping the reference samples.
The generator makes odd-sized images, sampled and progressive JPEGs, palette and Adam7 PNGs,
LZW and PackBits TIFFs, lossy and lossless WebP, and a transparent still and animated GIF.
You can pass additional raster files directly to the runner. Use a shared encoder version when
regenerating a corpus, and verify the reported SHA-256 digests before comparing separate runs.

The tool alternates the warmed implementations. Swag measures `Image.load` with one worker.
MagickWand reads the first image and exports its pixels with one thread. The export has the same
channel count and integer precision as Swag. Floating-point export uses binary32, including when
Swag stores with binary16. A GIF or other multi-image file measures the first image only. Swag
returns its representative canvas while ImageMagick selects its first image. The runner checks
that dimensions match. With `--libwebp`, the still WebP comparison also times a file read and
`WebPDecodeRGBAInto` with the library's default conversion.

Checksums, allocations of reference output buffers, and process startup are outside the measured
interval. The runner verifies identical checksums and formats across Swag builds, records raw
samples, and prints medians. ImageMagick and libwebp use their own color conversion and export
conventions. Use `taskset` on Linux to pin CPU affinity for a comparative run.
