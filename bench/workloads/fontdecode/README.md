# Font decode comparison

The workload opens a fresh face from disk, sets the pixel size, and renders one glyph. The
runner records the opening and rasterization phases separately and checks that the two Swag
builds return the same glyph index, advance, bitmap dimensions, and CRC-64. Pillow with FreeType
supplies an independent timing in Basic layout mode and must return a nonempty grayscale mask.

The public corpus has 29 files and 32 scenarios. It covers static and variable TrueType at the
default axis coordinates, Latin CFF, large CID-keyed OpenType, four faces of a CJK collection,
and three WOFF1 files. It includes Arabic, Devanagari, Thai, Tibetan, Armenian, Hebrew, Ethiopic,
CJK, mathematical symbols, and supplementary-plane glyphs. The manifest pins upstream inputs
and their SHA-256 hashes. FontTools generates the WOFF1 files from those inputs.

Use Python 3.11 or later with Pillow and FontTools. The `prepare` command verifies existing
files and downloads any missing public inputs. Pass a directory containing the original
12 attachments as `--attachments` to add the earlier FileSamples comparison and its controls.

```sh
python3 bench/workloads/fontdecode/run.py prepare --corpus /tmp/fontdecode/fonts
```

Build the probe against each Swag standard library being compared. Point `SWAG_PATH` at the
corresponding `bin` directory or an external snapshot of it. Use separate build outputs for
both versions. An externally built compiler also needs its checkout's runtime beside it.
[Linux compiler guide](../../../tools/README.md#linux-compiler-build)

```sh
swc build -d bench/workloads/fontdecode/src \
  --module-file bench/workloads/fontdecode/module.swg -bc release --artifact-kind executable \
  -n fontdecode --out-dir /tmp/fontdecode/out --work-dir /tmp/fontdecode/work

python3 bench/workloads/fontdecode/run.py compare --cpu 0 \
  --corpus /tmp/fontdecode/fonts --baseline /path/to/baseline/fontdecode \
  --candidate /tmp/fontdecode/out/fontdecode --output /tmp/fontdecode/results.json
```

Each run reports the median of interleaved batches. The filesystem cache stays warm, each
engine renders 20 px by default, and each batch discards five warm-up renders. Destruction is
outside the timed spans. The results file records per-batch nanoseconds and fixture hashes.
Set `--cpu` to a CPU available to the process on Linux. Omit it on other platforms.

When comparing with a release that rejects a known valid fixture, pass its filename with
`--allow-baseline-rejection`. The runner labels the rejected baseline and still checks the
candidate against the reference for that scenario.

Pass `--collection-memory` to measure TTC faces opened with `Face.loadAt` from a buffer
read before timing starts. Both Swag executables need to be built from the probe source above.
This mode compares the two Swag builds and checks the same glyph measurements.

## CJK ownership comparison

The native FreeType probe exercises the pathname load, the owned snapshot load, and the
stream callback independently. Build it against the FreeType version used for the comparison.

```sh
cc -std=c11 -O2 bench/workloads/fontdecode/freetype_native.c \
  $(pkg-config --cflags --libs freetype2) -o /tmp/fontdecode/freetype
/tmp/fontdecode/freetype --version
for mode in file snapshot memory count
do
  /tmp/fontdecode/freetype "$mode" /tmp/fontdecode/fonts/NotoSansCJKjp-Regular.otf 0 0x65e5 20 21
done
```

Each mode opens a fresh face, sets its size, and renders one glyph. Five warmups are
excluded. The six output fields are mean input acquisition, face opening with size setup,
and glyph loading with rendering in nanoseconds, followed by bytes requested during open,
bytes requested for the glyph, and the glyph index.

The `file` mode uses `FT_New_Face`. The `snapshot` mode reads the whole file with `pread`
into a reusable buffer before calling `FT_New_Memory_Face`. The `memory` mode uses that
call with a buffer read before timing starts. The `count` mode wraps an already-read buffer in an `FT_Stream` and counts logical byte requests. Overlapping
requests count each time they occur. The counts describe stream access rather than
filesystem pages or faults.

## Shared source comparison

Pass the final argument `source` to the Swag probe to snapshot the file before timing
and open each fresh face from that snapshot. Use `memory` to compare the existing
`Face.loadAt` path on a buffer read before timing. FreeType's `memory` mode also
reuses one buffer acquired before timing.

```sh
/tmp/fontdecode/out/fontdecode /tmp/fontdecode/fonts/NotoSansCJK-Regular.ttc 1 54620 20 21 source
/tmp/fontdecode/out/fontdecode /tmp/fontdecode/fonts/NotoSansCJK-Regular.ttc 1 54620 20 21 memory
/tmp/fontdecode/freetype memory /tmp/fontdecode/fonts/NotoSansCJK-Regular.ttc 1 54620 20 21
```
