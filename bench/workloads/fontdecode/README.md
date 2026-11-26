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
