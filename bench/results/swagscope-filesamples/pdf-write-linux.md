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
