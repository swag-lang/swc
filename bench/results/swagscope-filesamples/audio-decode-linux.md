# FileSamples audio decode after optimization

Compared on Linux x86-64 (AMD EPYC 7763). Swag baseline is commit `335b91f31e`.
Both Swag builds used the same native Release compiler and `-bc release`. The reference
was native FFmpeg 7.1.5 through libavformat, libavcodec and libswresample.

Each run opened the file and materialized the first ten seconds as interleaved PCM16 at
the source rate and channel count. Swag used `SoundFile.load(preloadData: false)` and
`decodePcm16`. FFmpeg probed the stream, decoded with one codec thread and wrote through
libswresample into a contiguous output buffer. The Swag open time covers complete indexing
and format integrity checks. The FFmpeg open time covers input probing and decoder setup.

Each engine ran on the same pinned CPU. Three rounds rotated engine order, with one warm-up
and seven measured repetitions per engine and round. All times below are medians in
milliseconds. Opening, decoding and total times are independently aggregated. The six
compressed `sample3` inputs and the WAV control came from the linked mirror. The FLAC and
OGA `sample1` inputs came from the original corpus. All nine match the file sizes in the
original comparison. The new SHA-256 fingerprints, PCM comparisons and raw samples are
recorded with the timings. [Original comparison](README.md) · [Fixture mirror](https://github.com/jaywcjlove/filesamples/tree/f2da30a6d081f6b4a63682c514acaca7cc4c9921/docs/files/audio) · [Raw samples](audio-decode-linux.json)

## Open and materialize 10 seconds of PCM16

| Format | Swag before (ms) | Swag after (ms) | Speedup | FFmpeg (ms) |
| --- | ---: | ---: | ---: | ---: |
| AAC | 41.98 | 22.09 | 1.90× | 6.55 |
| AC-3 | 49.15 | 22.73 | 2.16× | 8.04 |
| DTS | 550.92 | 36.39 | 15.14× | 15.70 |
| FLAC | 552.97 | 24.75 | 22.35× | 12.31 |
| MP3 | 91.64 | 24.00 | 3.82× | 8.21 |
| OGA (FLAC) | 120.60 | 23.06 | 5.23× | 10.59 |
| Ogg Vorbis | 37.87 | 18.30 | 2.07× | 7.68 |
| Opus | 87.22 | 43.22 | 2.02× | 20.81 |
| WAV | 1.94 | 1.88 | Control | 27.24 |

## Time by stage

| Format | Swag open before → after (ms) | Swag decode before → after (ms) | FFmpeg open (ms) | FFmpeg decode (ms) |
| --- | ---: | ---: | ---: | ---: |
| AAC | 0.63 → 0.60 | 41.38 → 21.53 | 0.64 | 5.90 |
| AC-3 | 0.68 → 0.65 | 48.20 → 21.99 | 0.87 | 7.19 |
| DTS | 6.67 → 4.48 | 543.28 → 30.17 | 1.57 | 14.05 |
| FLAC | 531.22 → 11.32 | 21.89 → 13.42 | 0.43 | 11.65 |
| MP3 | 1.81 → 1.42 | 89.92 → 22.61 | 0.40 | 7.81 |
| OGA (FLAC) | 98.73 → 9.76 | 21.24 → 13.28 | 0.63 | 9.96 |
| Ogg Vorbis | 12.53 → 1.46 | 25.27 → 16.82 | 0.88 | 6.80 |
| Opus | 10.48 → 1.24 | 76.65 → 41.88 | 0.60 | 20.24 |
| WAV | 0.03 → 0.03 | 1.92 → 1.84 | 26.39 | 0.80 |

Faster sync search and CRC reduce native FLAC indexing. Ogg verifies each page once and
checks the CRC eight bytes at a time. The FLAC codec speeds up Rice residual reads, and
the Ogg codecs borrow complete packets directly from the page or read window when possible.

DTS uses a factored synthesis transform, a circular history buffer and grouped bit reads.
MP3 uses factored transforms, SIMD synthesis and a Huffman prefix table. A separate MP3
profile on the same fixture measured the inverse transform at 24.68 → 6.76 ms and the
polyphase bank at 52.77 → 7.39 ms, with 21 interleaved repetitions. AAC combines Huffman
and dequantization lookups with SIMD and cheaper overlap. Dolby batches bit reads and
shares FFT tables across blocks. Vorbis uses prefix lookup and SIMD transforms. Opus uses
SIMD CELT FFT butterflies and precomputed counts for pulse-vector decoding.

## PCM verification

The Swag before/after PCM16 was bit-identical for AAC, AC-3, DTS, FLAC, OGA (FLAC),
Ogg Vorbis and WAV.
MP3 changed 42,932 of 882,000 values by one PCM16 unit, with RMS error 0.221 units.
Opus changed 542 of 960,000 values by one PCM16 unit, with RMS error 0.024 units.
FLAC and OGA also match FFmpeg PCM16 byte for byte. The native Release audio module passed
300 functional and stress tests.

## Second optimization pass

Baseline commit `87100a43ff` and the second pass ran on the same Linux host with the same
fixtures and 21-sample procedure. This compares the two optimized builds directly.
The table shows total wall time including file opening and PCM16 materialization.
[Raw samples, stage times and PCM deltas](audio-decode-linux-round2.json)

| Format | First pass (ms) | Second pass (ms) | Time saved | FFmpeg (ms) | Swag / FFmpeg |
| --- | ---: | ---: | ---: | ---: | ---: |
| AAC | 22.75 | 18.85 | 17.2% | 6.67 | 2.83× |
| AC-3 | 22.82 | 17.64 | 22.7% | 8.33 | 2.12× |
| DTS | 32.95 | 27.83 | 15.6% | 14.75 | 1.89× |
| FLAC | 25.40 | 14.42 | 43.2% | 12.20 | 1.18× |
| MP3 | 22.69 | 17.92 | 21.0% | 9.05 | 1.98× |
| OGA (FLAC) | 23.59 | 13.40 | 43.2% | 11.20 | 1.20× |
| Ogg Vorbis | 18.41 | 13.26 | 28.0% | 8.20 | 1.62× |
| Opus | 42.52 | 32.23 | 24.2% | 20.23 | 1.59× |
| WAV | 2.05 | 1.89 | Control | 28.44 | 0.07× |

Carry-less multiplication speeds up FLAC frame checksums and Ogg page checksums.
The FLAC reader searches both bytes of the sync prefix, and the decoder spends less
time in linear prediction and stereo PCM output. AAC requantizes spectral values
while decoding each tuple and packs PCM16 directly after synthesis. AC-3 reuses the
bit allocation across blocks with the same parameters and reads from a bounded bit
reservoir. DTS reduces scratch initialization and parses each packet header once.
MP3 vectorizes across time slots and subbands. Opus specializes sparse pulse
reconstruction and uses packed SIMD for the inverse transform and PCM output. Vorbis
decodes stereo residue in pairs and uses SIMD for stereo uncoupling and windowing.

MP3 differs from the original Swag PCM by at most 1 PCM16 unit (RMS 0.221).
Opus differs from the original Swag PCM by at most 1 PCM16 unit (RMS 0.023).
The original and final Swag PCM are bit-identical for AAC, AC-3, DTS, FLAC, OGA (FLAC),
Ogg Vorbis and WAV.
The native Release audio module passed 304 functional and stress tests.

## Third optimization pass

Baseline commit `32aa206618` and the third pass ran on the same native Linux host
with the same inputs and decoder APIs. Times are medians of 35 measured repetitions
per engine. Five rounds rotate engine order on one pinned CPU and discard the warm-up
of each engine in each round. FFmpeg uses one codec thread. [Raw stage times and PCM
deltas](audio-decode-linux-round3.json)

| Format | Second pass (ms) | Third pass (ms) | FFmpeg (ms) | Swag / FFmpeg |
| --- | ---: | ---: | ---: | ---: |
| AAC | 18.74 | 8.74 | 6.44 | 1.357× |
| AC-3 | 16.49 | 13.07 | 7.80 | 1.675× |
| DTS | 26.80 | 13.92 | 14.73 | 0.945× |
| FLAC | 15.62 | 13.65 | 12.46 | 1.095× |
| MP3 | 17.92 | 12.65 | 8.14 | 1.553× |
| OGA (FLAC) | 13.78 | 12.00 | 11.34 | 1.058× |
| Ogg Vorbis | 12.88 | 8.21 | 7.80 | 1.052× |
| Opus | 31.34 | 23.91 | 19.43 | 1.230× |
| WAV | 1.95 | 1.94 | 26.03 | 0.075× |

A second pinned CPU repeats the measurements near parity.

| Format | Swag (ms) | FFmpeg (ms) | Swag / FFmpeg |
| --- | ---: | ---: | ---: |
| FLAC | 11.68 | 11.67 | 1.001× |
| OGA (FLAC) | 10.40 | 10.98 | 0.947× |
| DTS | 14.39 | 14.55 | 0.989× |
| Ogg Vorbis | 7.84 | 7.54 | 1.039× |

FLAC predicts groups of four samples from packed LPC history and writes stereo
decorrelation and PCM together. It falls back to the wide predictor when samples exceed
the packed range. AAC combines Huffman values and signs in the prefix lookup and uses
SIMD synthesis. DTS batches direct bitfield decoding and runs the synthesis filters in
parallel SIMD lanes. AC-3 specializes transform stages and writes PCM during synthesis.
MP3 caches bit prefixes, fuses signed Huffman tokens and skips zero-spectrum transforms
while advancing their overlap state. Vorbis improves entropy, floor and the MDCT/PCM
handoff. Opus shortens the pulse-vector search and pairs the stereo transform work.

AAC differs from original Swag PCM by at most 1 PCM16 unit (RMS 0.030).
DTS differs from original Swag PCM by at most 1 PCM16 unit (RMS 0.024).
MP3 differs from original Swag PCM by at most 1 PCM16 unit (RMS 0.221).
Ogg Vorbis differs from original Swag PCM by at most 1 PCM16 unit (RMS 0.020).
Opus differs from original Swag PCM by at most 1 PCM16 unit (RMS 0.023).
The original and current Swag PCM match bit for bit for AC-3, FLAC, OGA (FLAC) and WAV.
The native Release audio module passed 306 functional and stress tests.

## Fourth optimization pass

The one-core comparison uses the previous method. A second comparison allows both
programs four cores on the same host and requests four decoder threads from FFmpeg.
The Swag scheduler receives the same budget. Both measure file opening plus
materialization of the first ten seconds of interleaved PCM16. Each measurement
uses the same fixtures and five rounds of seven samples on the same CPU set.
[Raw stage times and PCM deltas](audio-decode-linux-round4.json)

| Format | Swag 1 core (ms) | FFmpeg 1 core (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: |
| AAC | 8.92 | 6.41 | 6.92 | 7.43 |
| AC-3 | 13.96 | 8.10 | 15.38 | 9.21 |
| DTS | 14.06 | 14.97 | 15.06 | 15.94 |
| FLAC | 10.57 | 11.51 | 7.88 | 8.99 |
| MP3 | 13.30 | 8.12 | 7.04 | 8.46 |
| OGA (FLAC) | 9.86 | 11.31 | 7.67 | 8.62 |
| Ogg Vorbis | 8.80 | 8.19 | 8.75 | 8.00 |
| Opus | 25.01 | 22.18 | 24.00 | 21.95 |
| WAV | 1.90 | 29.62 | 1.98 | 27.03 |

The FLAC decoder consumes four short Rice codes per load when they fit. The offline
SoundFile path decodes independent FLAC frames or Ogg FLAC page runs in bounded
batches. The caller receives each packet in order and can cancel before an error
from later read-ahead is exposed. Existing packet validation still applies.

MP3 splits long offline ranges into lanes seeded with the bit reservoir and the
transform and synthesis history. AAC parses independent access units in parallel,
then reconstructs them from the preserved noise-generator and overlap state.
Both publish the original packet boundaries on the calling thread. Opus speeds up
the CELT pitch comb, reuses PCM scratch and avoids copying complete Ogg packets.

FLAC, OGA and DTS are ahead of FFmpeg on one core in this series. AAC and MP3
also lead with four cores. AC-3, Vorbis and Opus still trail at both budgets.
The single-core AAC and MP3 gaps remain open.

The third and fourth pass PCM matches exactly for every fixture except Opus, whose
output changes by one PCM16 unit in 24 of 960,000 samples. Across all four passes
the largest change from the original output remains one PCM16 unit. FLAC and OGA
also match FFmpeg PCM byte for byte.

The one-core and four-core Swag output hashes match for every fixture. Native Release
passes all 312 functional and stress tests at both worker budgets. A focused
Release-safe run passes 79 tests with four workers.

## Fifth optimization pass

The changed codecs were compared with commit `6e878a404b` and native FFmpeg. Each series
pins both decoders to one core and times opening plus materializing ten seconds of PCM16.
The table shows the median of 56 samples on each CPU.
[Raw stage times and PCM deltas](audio-decode-linux-round5.json)

| Format | R4 CPU 0 (ms) | R5 CPU 0 (ms) | FFmpeg CPU 0 (ms) | R4 CPU 1 (ms) | R5 CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AAC | 9.29 | 9.31 | 7.10 | 10.31 | 9.70 | 7.33 |
| AC-3 | 14.02 | 12.95 | 8.29 | 13.96 | 12.95 | 8.28 |
| Ogg Vorbis | 8.40 | 7.90 | 7.62 | 8.11 | 7.83 | 7.43 |

Dolby stores grouped mantissas in compact tables and folds the first FFT butterfly into
the long IMDCT input rotation. Vorbis limits inverse coupling and floor 1 to the bins
residue can populate. AAC reads entropy prefixes from a rolling bit window.

A radix-8 Opus experiment changed total time by less than 1% on all three pinned
CPUs in the combined build.

With four cores, AAC takes 6.21 ms (R4 6.32 ms, FFmpeg
7.02 ms). The PCM matches the one-core run exactly.

The original Swag PCM stays within one PCM16 unit for all three fixtures.
All three fixtures match the R4 PCM exactly.

Native Release passes all 312 functional and stress tests. A focused
Release-safe run passes 72 tests.

## Sixth optimization pass

The comparison repeats the fourth-pass one-core and four-core budgets, with Swag
commit `10ee17ffa0` as the baseline. Each median uses 35 samples and includes opening
the file and materializing the first ten seconds as PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round6.json)

| Format | R5 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| AAC | 8.62 | 8.56 | 6.56 | 5.96 | 6.59 |
| AC-3 | 12.56 | 10.53 | 8.03 | 10.49 | 8.28 |
| DTS | 14.69 | 14.07 | 14.92 | 14.42 | 15.21 |
| FLAC | 10.04 | 10.17 | 11.09 | 7.36 | 7.40 |
| MP3 | 12.39 | 10.89 | 7.96 | 6.51 | 9.13 |
| OGA (FLAC) | 9.85 | 9.79 | 11.31 | 7.15 | 8.04 |
| Ogg Vorbis | 7.96 | 7.83 | 7.28 | 8.21 | 8.04 |
| Opus | 23.03 | 23.62 | 20.12 | 23.37 | 20.79 |
| WAV | 1.85 | 1.90 | 27.21 | 1.89 | 28.03 |

The MP3 synthesis window reuses the same delay-line loads for reflected samples.
The hybrid transform transposes four subbands at each end using packed SIMD.
The MP3 index reuses parsed header fields across a run and handles padding separately.
The ADTS reader walks frame headers in one byte-source window at a time.

AC-3 and E-AC-3 process long blocks with two channels in packed single precision.
The decoder carries the overlap between the packed and per-channel transforms when
the block changes window size. The AC-3 FileSamples PCM differs from R5 by
at most one PCM16 unit. The MP3 and AAC samples match R5 exactly.

The one-core and four-core Swag PCM matches byte for byte. FLAC and OGA match reference
FFmpeg PCM exactly. The largest change from the original Swag output remains one PCM16
unit. Native Release passes all 314 functional and stress tests. Native
Release-safe passes 111 focused decoder tests.

## Seventh optimization pass

This follow-up compares the changed codecs with commit `0f7a7ecb02` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round7.json)

| Format | R6 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R6 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AAC | 8.98 | 8.09 | 6.86 | 8.90 | 8.46 | 7.02 |
| Opus | 23.05 | 22.61 | 19.44 | 23.92 | 23.14 | 20.03 |

| Format | R6 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| AAC | 6.43 | 6.08 | 6.87 |
| Opus | 23.54 | 24.72 | 20.00 |

AAC applies the long-window overlap as the IMDCT writes samples and packs the
short-window overlap and mid/side reconstruction into SIMD vectors. Opus uses compact
codebooks for small pulse tails and packs the CELT spreading recurrences.
A second four-core Opus series of 70 samples measures R6 at 24.52 ms, this build at
23.26 ms and FFmpeg at 20.50 ms. The four-core change varies across the two series.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 314 functional and stress tests. Release-safe passes
50 focused decoder tests.

## Eighth optimization pass

This follow-up compares the changed codecs with commit `466e75061c` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round8.json)

| Format | R7 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R7 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AAC | 8.07 | 7.73 | 7.15 | 8.02 | 7.24 | 6.57 |

| Format | R7 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| AAC | 6.21 | 5.95 | 7.04 |

AAC applies the first two inverse FFT stages to four adjacent complex coefficients
in SIMD lanes. The initial rotations use the fixed unit and imaginary twiddles.
FileSamples PCM matches the seventh-pass output byte for byte.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 39 focused AAC tests. Release-safe passes the same
39 tests.
