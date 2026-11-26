# Lossless block compression

`Core.Compress.Lz4` reads and writes independent blocks. Keep the decoded byte count with each
block. [LZ4 block format](https://github.com/lz4/lz4/blob/v1.10.0/doc/lz4_Block_format.md)

`Core.Compress.Snappy` reads and writes raw blocks, which carry their decoded size.
[Snappy raw format](https://github.com/google/snappy/blob/1.2.2/format_description.txt)

Both codecs support decoding into caller-owned storage. Use `Core.Compress.ZLib` where a format
requires zlib framing, as in PNG and existing SCC Deflate chunks.

## Initial prototype results on Linux x86-64

One virtual CPU on an AMD EPYC 9V74, using the Release compiler and `-bc release`. The system
libraries were LZ4 1.10.0, Snappy 1.2.2, zlib 1.3.1, Zstandard 1.5.7 and libdeflate 1.23.
The prototype used `94962d20e1` as its baseline and included experimental changes to zlib's
Deflate match search and Inflate refill. The integrated LZ4 and Snappy codecs landed on a newer
base with independent changes to Deflate and Inflate. The harness verifies byte-for-byte round-trips in both
directions for every compatible reference codec and Swag build. Each decoder is timed on the
same reference stream for its format and level. Encoding includes the allocation work of each
API. The native reference calls reuse a destination buffer, and the Swag encoders own their
result buffers. All decoders use preallocated output. File I/O and a warm-up call are outside the
timed interval. Rates divide the total input size by the sum of the median per-file process CPU
times from five batches. A smaller size percentage means a smaller encoded file.

The [Canterbury corpus](https://corpus.canterbury.ac.nz/) contains 11 files totaling 2,810,784 bytes.

| Implementation | Size | Encode MiB/s | Decode MiB/s |
| --- | ---: | ---: | ---: |
| Swag LZ4 | 43.13% | 302.3 | 2283.4 |
| LZ4 reference | 43.73% | 633.6 | 4433.4 |
| Swag Snappy | 44.36% | 334.4 | 715.2 |
| Snappy reference | 44.99% | 616.5 | 593.9 |
| Swag zlib 1, baseline | 28.96% | 99.6 | 475.2 |
| Swag zlib 1 | 28.96% | 99.3 | 528.0 |
| zlib 1 reference | 30.70% | 128.8 | 409.3 |
| Swag zlib 6, baseline | 26.03% | 30.1 | 552.9 |
| Swag zlib 6 | 26.03% | 31.1 | 569.7 |
| zlib 6 reference | 26.01% | 25.5 | 428.7 |
| Zstandard 1 | 24.43% | 403.3 | 1368.0 |
| libdeflate 6 | 25.68% | 87.5 | 872.9 |

The Swag media sample totals 496,057 bytes. It contains the filtered scanlines of two repository
PNGs, a photograph decoded to BGRA, and the `capture-all-forms.scc` test fixture.

| Implementation | Size | Encode MiB/s | Decode MiB/s |
| --- | ---: | ---: | ---: |
| Swag LZ4 | 61.39% | 240.2 | 1574.0 |
| LZ4 reference | 59.66% | 871.9 | 4132.0 |
| Swag Snappy | 56.16% | 271.0 | 710.6 |
| Snappy reference | 56.44% | 787.6 | 751.1 |
| Swag zlib 1, baseline | 42.90% | 65.1 | 322.3 |
| Swag zlib 1 | 42.90% | 64.2 | 327.6 |
| zlib 1 reference | 44.49% | 87.4 | 282.9 |
| Swag zlib 6, baseline | 39.63% | 21.8 | 384.7 |
| Swag zlib 6 | 39.63% | 23.4 | 404.6 |
| zlib 6 reference | 39.85% | 23.1 | 315.9 |
| Zstandard 1 | 44.24% | 338.1 | 974.0 |
| libdeflate 6 | 39.66% | 72.4 | 864.5 |

The two Swag zlib builds produced identical compressed bytes at both levels across all 15 inputs.
LZ4 had the highest Swag decode throughput across both corpora. Snappy had the highest Swag encode
throughput in this run and the smaller of the two new formats on the media sample. [lzbench on
Silesia](https://inikep.github.io/lzbench/) covers a broader set of implementations and data.

## LZ4 sequence writer

Reserving the output space for an entire sequence once avoids repeating capacity and alias
checks for each field. On the same host, seven paired batches per file measured the encoder
against the initial LZ4 implementation. All 18 files produced byte-identical streams.

| Corpus | Original MiB/s | Batched MiB/s | Speedup |
| --- | ---: | ---: | ---: |
| Canterbury | 313.4 | 365.8 | 1.17× |
| Swag media | 245.6 | 273.7 | 1.11× |
| Canterbury Large | 265.3 | 319.1 | 1.20× |
| Combined | 272.7 | 325.3 | 1.19× |

## Reproduce the comparison

Set `REPO` to the checkout, `WORK` to an existing scratch directory outside the checkout and `SWC`
to an absolute path to a Release compiler with its runtime directory. The runner uses Python 3
and the five shared libraries listed above. Set the CPU in `taskset` to a CPU available to the
process. `--json` records the per-file input and output hashes and timing samples.
The command measures the codecs in the current checkout. The optional baseline build compares
zlib at the original revision on the same inputs.

```sh
cd "$WORK"
git clone https://github.com/pfalcon/canterbury-corpus.git canterbury
git -C canterbury checkout c380ef9dc1dc62691757fdfeebdc2f85710e1e46

mkdir -p candidate/bin/std/modules baseline
cp -a "$REPO/bin/std/modules/core" "$REPO/bin/std/modules/linux" candidate/bin/std/modules/
git -C "$REPO" archive 94962d20e1 bin/std/modules/core | tar -xf - -C baseline
ln -s "$WORK/candidate/bin/std/modules/linux" baseline/bin/std/modules/linux

SWAG_PATH="$WORK/candidate/bin" "$SWC" build -d "$REPO/bench/workloads/compression/src" \
  --module-file "$REPO/bench/workloads/compression/module.swg" -bc release \
  --artifact-kind executable --artifact-name compression \
  --out-dir "$WORK/candidate-bin" --work-dir "$WORK/candidate-work"
SWAG_PATH="$WORK/baseline/bin" "$SWC" build -d "$REPO/bench/workloads/compression/src" \
  --module-file "$REPO/bench/workloads/compression/module.swg" -bc release \
  --tag compression.baseline --artifact-kind executable --artifact-name compression \
  --out-dir "$WORK/baseline-bin" --work-dir "$WORK/baseline-work"

corpus="$WORK/canterbury/canterbury"
taskset -c 3 python3 -B "$REPO/bench/workloads/compression/run.py" \
  --swag "$WORK/candidate-bin/compression" --baseline "$WORK/baseline-bin/compression" \
  --scratch "$WORK" --json "$WORK/canterbury.json" \
  "$corpus"/*.txt "$corpus"/{cp.html,fields.c,grammar.lsp,kennedy.xls,ptt5,sum,xargs.1}
```

For the media sample, concatenate the `IDAT` payloads and inflate them with `zlib.decompress`
for `bin/examples/modules/pixel7/src/data/succulent.png` and
`bin/std/modules/pixel/src/tests/datas/gopher-doc.with-alpha.png`. Decode
`bin/examples/modules/pixel7/src/data/fox.jpg` with Pillow 12.3.0 and export the pixels with
`image.convert("RGBA").tobytes("raw", "BGRA")`. Pass the three generated files and
`bin/apps/modules/swagcapture/src/tests/datas/capture-all-forms.scc` as the runner's input paths.

For a paired LZ4 comparison, use `b35a70a19b` as the archived baseline and omit
`--tag compression.baseline` from that build. Pass `--baseline-codec lz4 --samples 7 --batch-mib 8`
to the runner. The Canterbury Large inputs are `large/E.coli`, `large/bible.txt`, and
`large/world192.txt` in the corpus checkout.
