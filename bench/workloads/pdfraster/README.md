# CPU PDF raster comparison

The [fixture manifest](fixtures.json) pins public PDF.js and Apache PDFBox files by upstream
revision and SHA-256. It includes a research paper, dense vector paths, hairlines, fonts, photos,
scans, clipping, forms, and transparency. The three original FileSamples PDFs are optional.
The manifest selects pages explicitly, using one-based page numbers.

Prepare the corpus and build the driver in an external work directory. An externally built Linux
compiler needs the runtime beside it and `SWAG_PATH` pointing to the intended `bin` directory.
See the [Linux compiler guide](../../../tools/README.md#linux-compiler-build).

```sh
python3 bench/workloads/pdfraster/run.py prepare --corpus /tmp/pdfraster/corpus

swc build -d bench/workloads/pdfraster/src \
  --module-file bench/workloads/pdfraster/module.swg -bc release \
  -n pdfraster --out-dir /tmp/pdfraster/out --work-dir /tmp/pdfraster/work

python3 -m pip install pypdfium2==5.15.2
python3 bench/workloads/pdfraster/run.py compare \
  --corpus /tmp/pdfraster/corpus --candidate /tmp/pdfraster/out/pdfraster \
  --cpu 2 --side 1200 --output /tmp/pdfraster/results.json
```

Use Python 3.11 or later and select a logical CPU available to the current process.
`--cpu` sets affinity on Linux. To include FileSamples, pass `--filesamples` to `prepare` with
a directory containing the three original files. Use the optional `--file` filter repeatedly to
select individual manifest entries. To compare two Swag versions, build the driver against
each standard library and pass the other executable to `--baseline`.

The runner interleaves engines and pages in a fixed shuffled order. Each batch warms one
render and then reopens the file for each measured sample. Swag runs with one worker and
calls `Reader.open`, `loadPage`, and `Page.render`. The reference uses the PDFium bitmap API
with flags zero. Both render onto white BGRA surfaces sized from the page box and the
requested long side. Bitmap allocation and painting count toward render time. Checksums,
object counts, and process startup are outside the measured intervals.

The JSON records individual timings in nanoseconds, medians in milliseconds, dimensions,
pixel CRCs, object counts, and rejected pages. Timing totals combine all three stages before
taking the median. Image decoding and content preparation can fall in different stages in the
two engines. Swag counts its decoded items, while PDFium counts top-level page objects, including
forms. These counts describe the two implementations' work at different levels of grouping.

Checksums check repeatability within each engine. The 32 × 32 ink sample count helps spot
cases where an engine painted much less of the page. Matching dimensions and ink counts
alone do not establish rendering equivalence. Review unsupported features or large ink
differences before comparing timings.
