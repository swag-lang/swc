# PDF writer performance

The workload measures `Pdf.Document.encode` and `Pdf.Document.save` on one
Linux CPU. It constructs vector and image documents and can open existing
PDFs before timing. It records encoded size and CRC-32. PDFium renders saved
baseline and candidate files at one pixel per point to check raster equality.

Build the driver against each standard library with the corresponding
`SWAG_PATH`. An externally built Linux compiler needs the runtime beside it.
See the [Linux compiler guide](../../../tools/README.md#linux-compiler-build).

```sh
swc build -d bench/workloads/pdfwrite/src \
  --module-file bench/workloads/pdfwrite/module.swg -bc release \
  -n pdfwrite --out-dir /tmp/pdfwrite/out --work-dir /tmp/pdfwrite/work

python3 -m pip install pypdfium2==5.15.2
python3 bench/workloads/pdfwrite/run.py \
  --baseline /tmp/pdfwrite-before/out/pdfwrite --candidate /tmp/pdfwrite/out/pdfwrite \
  --cpu 2 --case vectors --case opaque --case repeated --output /tmp/pdfwrite/results.json
```

The generated cases are `vectors` (12 pages with text and paths), `rgb` (an
RGB8 image), `opaque` (a BGRA8 image with constant alpha), `alpha` (a BGRA8
image with varying alpha), `gray` (opaque grayscale content in BGRA8), and
`repeated` (one opaque image on eight pages). Each generated bitmap is
1,801 × 1,199 pixels. Paths ending in `.pdf` use the existing PDF as input.
The [raster corpus](../pdfraster/README.md) supplies the public PDFBox files.

The runner alternates baseline and candidate, warming each process once.
Document construction, loading, output checksums, and the PDFium raster
check are outside the timed interval. Save time includes the file write
and close using the system's normal buffering.
