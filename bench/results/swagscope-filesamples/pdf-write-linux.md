# PDF writing on Linux

The [writer workload](../../workloads/pdfwrite/README.md) measures
`Document.encode` and `Document.save` after constructing the document.
For existing PDFs, loading happens before the measurement.

## Shared image resources

A document writes an image object and its soft mask once for each
distinct pixel buffer, channel layout, alpha mode and dimensions. A CRC
selects candidate references, followed by an exact comparison. Opaque
images skip soft-mask streams. The writer reuses the Deflate state for
page content, image samples and masks.

The medians below use seven interleaved Release runs on one AMD EPYC
7763 logical CPU, with `116f2dd213` as the baseline. The size column
shows emitted bytes. PDFium 159.0.8149.0 renders each saved PDF to
check that every page matches its baseline.
[Raw samples, encode times, and checksums](pdf-write-linux-shared-images.json)

| Input | Save before, ms | Save after, ms | Bytes before | Bytes after |
| --- | ---: | ---: | ---: | ---: |
| `repeated` | 1409.78 | 196.66 | 9,813,685 | 1,226,661 |
| `opaque` | 178.84 | 156.38 | 1,226,990 | 1,224,670 |
| `alpha` | 164.92 | 163.96 | 1,237,844 | 1,237,844 |
| `rgb` | 152.21 | 146.96 | 1,233,855 | 1,233,855 |
| `gray` | 76.46 | 64.68 | 229,384 | 227,064 |
| `vectors` | 143.24 | 150.19 | 123,459 | 123,459 |
| `pdfbox-jpeg.pdf` | 26.74 | 13.29 | 318,582 | 159,599 |
| `pdfbox-scan.pdf` | 3.56 | 3.70 | 4,223 | 4,223 |

The eight saved scenarios render identically in PDFium. In the
repeated-image document the in-memory encode also drops from 1,394 to
171 ms. The PDFBox JPEG page places the same photo twice. The GUI
Release suite passes 1,263 tests, including cross-page references and
the streaming print writer.


## Writing fixed-point coordinates directly

The writer appends coordinates, text matrices and color values directly
to the page's content buffer. Ordinary finite coordinates use a stack
buffer and the same four decimal places, ties to even, and removal of
trailing zeroes. This avoids a temporary formatted string for each value
and each path instruction.

Thirteen interleaved Release runs on one AMD EPYC 7763 logical CPU use
`7d19843433` as the baseline. Both builds use the same compiler and Core
at `3f81024a37`. The 12-page vector document has 9,600 marks.
[Timings, sizes, and checksums](pdf-write-linux-fixed-points.json)

| Operation | Before, ms | After, ms | Output bytes |
| --- | ---: | ---: | ---: |
| `encode` | 145.11 | 45.86 | 123,459 |
| `save` | 149.60 | 45.50 | 123,459 |

The vector, opaque-image, and PDFBox JPEG outputs all retain their byte
counts and CRC-32, with the same PDFium rasters. The 134 PDF tests
include positive and negative half-way coordinates.


## Packing bilevel image streams

Black-and-white gray samples are packed most-significant bit first in
each row. Deflate processes one eighth of the original sample bytes
before row padding. The writer keeps a separate eight-bit soft mask
when the source has partial alpha. Native Gray8 and GrayAlpha8 images
write their luminance channel directly.

Seven interleaved Release runs on one AMD EPYC 7763 logical CPU use
`7d19843433` as the baseline. The two builds use Core at `3f81024a37`.
[Raw samples, image sizes, and raster comparisons](pdf-write-linux-bilevel.json)

| Input | Save before, ms | Save after, ms | Bytes before | Bytes after |
| --- | ---: | ---: | ---: | ---: |
| `pdfbox-scan.pdf` | 3.94 | 1.80 | 4,223 | 3,660 |
| `perf_images_scan_bilevel.pdf` | 125.36 | 50.50 | 112,377 | 35,466 |

All six saved scenarios keep their PDFium rasters. The 135 PDF tests
include odd-width rows, asymmetric samples and a partial alpha channel.


## Predicting large, smooth image streams

The writer estimates the residual size on a small grid of pixels. Large,
smooth eight-bit gray, RGB and alpha planes use the shared PNG Sub
kernel before a short greedy Deflate search. The differences are
reversible. A bilevel stream retains its packed row layout.

Nine interleaved Release runs on one AMD EPYC 7763 logical CPU use
`3e33c0033e` as the baseline.
[Raw samples, output sizes, and raster comparisons](pdf-write-linux-predictors.json)

| Input | Save before, ms | Save after, ms | Bytes before | Bytes after |
| --- | ---: | ---: | ---: | ---: |
| `opaque` | 154.55 | 80.51 | 1,224,670 | 629,050 |
| `alpha` | 156.48 | 84.30 | 1,237,844 | 634,398 |
| `rgb` | 135.19 | 65.21 | 1,233,855 | 630,515 |
| `gray` | 65.72 | 25.00 | 227,064 | 136,007 |
| `pdfbox-jpeg.pdf` | 14.03 | 13.25 | 159,599 | 159,599 |
| `pdfbox-scan.pdf` | 1.80 | 1.90 | 3,660 | 3,660 |
| `perf_images_scan_bilevel.pdf` | 52.87 | 56.51 | 35,466 | 35,466 |

Every saved raster matches its baseline in PDFium. The 136 PDF tests
include a 513 by 513 GrayAlpha8 image with one predictor per plane.
The 52 PNG tests pass and the public row filter appears in the
generated Pixel documentation.


## Retaining original RGB JPEG streams

An editable document can keep the compressed bytes of an unmasked,
eight-bit DeviceRGB JPEG with matching dimensions and default decoding
parameters. The writer emits those bytes as DCT data and shares identical
streams. A pixel edit releases the stored stream for that image.

Nine interleaved Release runs on one AMD EPYC 7763 logical CPU compare
the shared-image implementation based on `5d769d9d98` before and after
JPEG retention. These times cover `Document.save` after loading the
source. The native tests use the same compiler and Core snapshot.
[Timings, source-raster comparisons, and checksums](pdf-write-linux-retained-jpeg.json)

| Input | Save before, ms | Save after, ms | Bytes before | Bytes after |
| --- | ---: | ---: | ---: | ---: |
| `pdfbox-jpeg.pdf` | 12.230 | 0.069 | 159,599 | 41,140 |
| `perf_images_jpeg_large.pdf` | 587.920 | 0.579 | 11,946,563 | 1,431,623 |
| `pdfbox-scan.pdf` | 1.904 | 1.818 | 3,660 | 3,660 |

PDFium renders both retained JPEG files exactly as the original PDFs
at one pixel per point. The existing Flate save had a mean RGB delta
of 0.420 and 0.029 respectively. The 43 supported raster cases keep
their Swag checksums, and the 139 PDF tests cover compressed-byte
equality, explicit decoding parameters and an independent pixel edit.

## Retaining original grayscale JPEG streams

The same save path retains a one-component DeviceGray JPEG with default
decoding parameters and no mask. The output keeps its grayscale color
space. Nine alternating Release runs use one AMD EPYC 7763 logical CPU
and baseline `5c169b416c`. The timings cover `Document.save` after loading.
[Timings, output sizes, and PDFium raster checksums](pdf-write-linux-retained-gray-jpeg.json)

| Input | Save before, ms | Save after, ms | Bytes before | Bytes after |
| --- | ---: | ---: | ---: | ---: |
| `perf_codecs_jpeg_gray_progressive.pdf` | 123.532 | 0.966 | 2,775,608 | 980,922 |

At one pixel per point, PDFium renders the new output identically to the
source PDF. The earlier Flate output has a different raster checksum.
The RGB JPEG and scan controls keep their saved PDF checksums. The 142
PDF tests include a generated one-component JPEG with the grayscale
dictionary and compressed samples checked after a round trip.
