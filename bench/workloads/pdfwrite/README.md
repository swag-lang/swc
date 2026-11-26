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

To benchmark saves that include the same immutable JPEG on many pages,
generate the 64-page fixture from the pinned large JPEG in the raster
corpus. Each page makes eight placements of the shared image object.

```sh
python3 bench/workloads/pdfwrite/repeated_fixture.py \
  /tmp/pdfraster/perf_images_jpeg_large.pdf /tmp/pdfwrite/repeated-64.pdf
```

Pass the generated path as `--case` and select `--mode save`.

Use `--distinct 16` to write a 16-page control with a separate retained
JPEG stream per page. Each stream contains a different JPEG comment.

```sh
python3 bench/workloads/pdfwrite/repeated_fixture.py \
  /tmp/pdfraster/perf_images_jpeg_large.pdf /tmp/pdfwrite/many-jpeg-16.pdf --distinct 16
```

## Many empty pages

Use the same pypdfium2 installation as the benchmark to make the
2,000-page fixture. Pass its path to the runner as `--case`.

```sh
python3 - /tmp/pdfwrite/pdfium-blank-pages-2000.pdf <<'PYCODE'
import sys
from pypdfium2 import PdfDocument

with PdfDocument.new() as document:
    for _ in range(2000):
        document.new_page(10, 10).close()
    document.save(sys.argv[1])
PYCODE
```
