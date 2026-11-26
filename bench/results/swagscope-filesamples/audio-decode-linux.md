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

## Ninth optimization pass

This follow-up compares the changed codecs with commit `2b741a0e65` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round9.json)

| Format | R8 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R8 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ogg Vorbis | 8.05 | 7.71 | 7.38 | 7.92 | 7.68 | 7.51 |

| Format | R8 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| Ogg Vorbis | 8.17 | 7.54 | 7.96 |

The inverse MDCT combines pre-rotation with the first two FFT stages for Vorbis blocks.
It writes each four-point result together after transposing the SIMD lanes.
FileSamples PCM matches the eighth-pass output exactly.

The 70-sample one-core repeat on CPU 3 measures 7.79 ms for R8, 7.34 ms for this
build and 7.29 ms for FFmpeg. The 70-sample repeat on CPUs 1–4 gives 7.89 ms,
7.61 ms and 7.60 ms. The four-core comparison ranges from a Swag lead to near
parity between the two CPU sets.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 314 functional and stress tests. Release-safe passes
27 focused Vorbis, MDCT, Ogg and AAC encoder tests.

### Full ninth-pass comparison

All nine fixtures were measured again with the ninth-pass build `c235d7a7eb` and
the fifth-pass baseline. Each value is the median of 35 runs on the same CPU set
as the sixth pass. The reported time includes opening and decoding ten seconds to
interleaved PCM16. [Raw stage times and PCM deltas](audio-decode-linux-round9.json)

| Format | R5 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| AAC | 8.72 | 7.38 | 6.67 | 6.28 | 6.90 |
| AC-3 | 12.32 | 10.25 | 8.03 | 10.77 | 8.50 |
| DTS | 14.30 | 14.42 | 15.08 | 14.24 | 15.39 |
| FLAC | 10.35 | 10.34 | 11.44 | 7.25 | 8.01 |
| MP3 | 12.60 | 10.89 | 8.49 | 7.47 | 8.14 |
| OGA (FLAC) | 9.62 | 9.55 | 11.08 | 6.86 | 7.40 |
| Ogg Vorbis | 8.04 | 7.45 | 7.23 | 7.38 | 7.21 |
| Opus | 22.66 | 22.03 | 19.62 | 24.10 | 20.10 |
| WAV | 1.77 | 1.74 | 26.14 | 1.73 | 25.83 |

The Swag PCM matches between worker budgets for all nine fixtures. FLAC and OGA
match FFmpeg byte for byte. The largest difference from the original Swag output
is one PCM16 unit.

## Tenth optimization pass

This follow-up compares the changed codecs with commit `c235d7a7eb` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round10.json)

| Format | R9 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R9 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ogg Vorbis | 7.38 | 7.02 | 7.34 | 7.58 | 7.08 | 7.83 |

| Format | R9 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| Ogg Vorbis | 7.28 | 7.06 | 7.44 |

Vorbis appends uninitialized PCM slots and fills them in the existing overlap loop.
The decoder writes every appended sample for all channel layouts. FileSamples PCM
matches the ninth-pass output byte for byte, as do the seven additional Vorbis fixtures
used for the focused comparison.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 314 functional and stress tests. Release-safe passes
18 focused Vorbis, Ogg and MDCT tests.

## Eleventh optimization pass

This follow-up compares the changed codecs with commit `a669e20dcc` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round11.json)

| Format | R10 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R10 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AAC | 7.52 | 7.27 | 6.81 | 7.48 | 7.33 | 6.90 |
| AC-3 | 10.31 | 9.91 | 8.29 | 10.74 | 10.20 | 8.40 |
| Opus | 22.17 | 21.92 | 19.13 | 22.51 | 22.59 | 19.67 |

| Format | R10 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| AAC | 5.72 | 5.47 | 6.62 |
| AC-3 | 10.55 | 10.15 | 8.14 |
| Opus | 22.91 | 23.55 | 19.40 |

AAC stores spectral coefficients in single precision for the SIMD input rotation
and reflects the symmetric IMDCT output groups. The overlap head uses separate
multiplication and addition rounding in both worker modes.

AC-3 stores the mantissa code and scale when bit allocation changes and reuses
them for subsequent blocks. The tested Dolby output matches the previous pass
byte for byte.

Opus precomputes the coded CELT split angle, gains and log tangent in a 130 KiB
table. The tested Opus output matches the previous pass byte for byte.

An 84-sample Opus repeat on CPU 3 measures 23.35 ms for R10, 22.79 ms for this
build and 20.46 ms for FFmpeg. The 70-sample Opus repeat on CPUs 1–4 measures 23.56 ms for R10, 23.42 ms for
this build and 20.60 ms for FFmpeg. The four-core Opus change varies by CPU set.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 314 functional and stress tests. Release-safe passes
66 focused AAC, Dolby and Opus tests.

## Twelfth optimization pass

This follow-up compares the changed codecs with commit `7447dae0a7` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round12.json)

| Format | R11 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R11 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MP3 | 10.29 | 9.59 | 7.74 | 10.30 | 9.62 | 7.63 |

| Format | R11 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| MP3 | 6.58 | 6.24 | 8.02 |

MP3 reconstructs pure mid/side stereo with packed adds and subtracts on complete long
and short band layouts. The polyphase filter shares fourteen history rows between
windows two time slots apart. The ring keeps the rows that all four time slots
need during the shared synthesis pass.

The FileSamples PCM matches R11 byte for byte at both worker budgets.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 314 functional and stress tests. Release-safe
passes 27 focused MP3 tests.

## Thirteenth optimization pass

This follow-up compares the changed codecs with commit `58caf2ec57` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round13.json)

| Format | R12 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R12 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AAC | 7.36 | 6.70 | 6.99 | 7.33 | 6.69 | 6.79 |

| Format | R12 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| AAC | 5.45 | 5.07 | 6.91 |

AAC combines four input rotations with the first two inverse FFT stages,
then transposes the SIMD lanes into the order needed by the later stages.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 39 focused AAC tests. Release-safe passes the same
39 tests.

## Fourteenth optimization pass

This follow-up compares the changed codecs with commit `cdab4f5c1a` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round14.json)

| Format | R13 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R13 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AC-3 | 9.83 | 9.24 | 7.98 | 10.00 | 9.70 | 8.26 |
| MP3 | 10.31 | 9.91 | 8.37 | 10.27 | 9.93 | 8.35 |
| Opus | 22.41 | 22.11 | 20.50 | 22.45 | 21.39 | 19.72 |

| Format | R13 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| AC-3 | 10.09 | 9.45 | 8.31 |
| MP3 | 5.61 | 5.20 | 8.28 |
| Opus | 22.69 | 21.91 | 20.77 |

AC-3 advances four dither states in parallel. MP3 applies its hybrid transform
window and overlap as it unfolds each symmetric pair. Opus uses reciprocal range
quotients and writes CELT PCM16 directly when no output gain is needed.

All 22 generated fixtures match the prior Swag output within one PCM16 unit.
The four generated AC-3 and E-AC-3 fixtures are byte-identical.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output.

Native Release passes 314 audio tests. Release-safe passes
54 focused AC-3, MP3 and Opus tests.

## Fifteenth optimization pass

This follow-up compares the changed codecs with commit `96158d6b28` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round15.json)

| Format | R14 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R14 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 10.79 | 9.38 | 11.49 | 10.85 | 9.45 | 11.74 |
| Ogg FLAC | 10.24 | 8.92 | 11.24 | 9.91 | 8.57 | 10.89 |
| AAC | 6.45 | 6.18 | 6.54 | 6.50 | 6.27 | 6.49 |

| Format | R14 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| FLAC | 7.33 | 6.32 | 7.20 |
| Ogg FLAC | 7.54 | 6.38 | 7.96 |
| AAC | 4.66 | 4.06 | 6.91 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R14 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R14 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `aac-lc-32k-mono.aac` | 3.02 | 2.48 | 3.44 | 2.96 | 1.88 | 3.53 |
| `aac-lc-48k-5.1.aac` | 23.67 | 19.55 | 17.88 | 16.91 | 10.73 | 17.53 |
| `aac-lc-48k-stereo.aac` | 9.33 | 8.93 | 8.21 | 6.27 | 5.10 | 8.43 |
| `flac-44k-stereo-16.flac` | 6.76 | 5.75 | 11.27 | 4.12 | 3.59 | 7.95 |

FLAC packs four guarded 16-bit stereo samples directly after restoring the
channel assignment. AAC specializes mono and 5.1 PCM conversion while isolating
the new code from stereo. The generated-fixture PCM matches the corresponding
baseline bit for bit at each worker budget. The generated 5.1 AAC stream has an
existing one-unit PCM16 difference across worker budgets in both builds.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. The FLAC and Ogg FLAC PCM
match the preceding build exactly.

Native Release passes 314 audio tests. Release-safe passes
69 focused FLAC and AAC tests.

## Sixteenth optimization pass

This follow-up compares the changed codecs with commit `254fcb304c` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round16.json)

| Format | R15 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R15 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DTS | 13.39 | 11.71 | 14.61 | 14.06 | 13.05 | 15.11 |
| Opus | 21.06 | 21.07 | 19.21 | 22.40 | 22.27 | 20.17 |
| WAV | 1.56 | 1.00 | 25.91 | 1.77 | 1.13 | 29.13 |

| Format | R15 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| DTS | 14.53 | 13.01 | 15.39 |
| Opus | 21.79 | 21.22 | 19.46 |
| WAV | 1.71 | 1.08 | 25.95 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R15 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R15 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `dts-48k-5.1.dts` | 48.24 | 31.27 | 33.82 | 56.30 | 33.16 | 35.09 |
| `opus-20ms-48k-stereo.opus` | 31.23 | 30.66 | 29.85 | 35.73 | 41.82 | 38.24 |
| `opus-5ms-48k-stereo.opus` | 31.61 | 30.77 | 34.42 | 33.60 | 32.52 | 34.73 |
| `opus-voip-48k-mono.opus` | 29.01 | 16.34 | 13.73 | 30.96 | 16.41 | 14.82 |
| `wav-48k-stereo-24.wav` | 1.43 | 0.61 | 1.42 | 1.62 | 0.67 | 1.61 |

DTS groups short ternary Huffman codes and vectorizes LFE synthesis. Opus
vectorizes fixed-point SILK filters and resampling. Streaming WAV reuses its
input window through a contiguous PCM range. The generated DTS and WAV
fixtures cross ahead of FFmpeg at one core in this series.

The four-core 20 ms Opus timing had a noisy first series. The 84-sample repeat
measured 32.23 ms for R15, 31.08 ms for Swag, and 31.18 ms for FFmpeg.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 316 audio tests. Release-safe passes
37 focused DTS, Opus and WAV tests.

## Seventeenth optimization pass

This follow-up compares the changed codecs with commit `b56213567d` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round17.json)

| Format | R16 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R16 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 16.67 | 16.43 | 22.74 | 8.93 | 8.76 | 11.35 |
| Ogg FLAC | 16.31 | 16.30 | 22.70 | 8.53 | 8.57 | 11.04 |
| AAC | 6.11 | 6.05 | 6.67 | 6.33 | 6.39 | 6.65 |

| Format | R16 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| FLAC | 6.25 | 6.43 | 7.43 |
| Ogg FLAC | 6.73 | 6.68 | 7.91 |
| AAC | 4.70 | 4.64 | 6.73 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R16 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R16 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `aac-lc-48k-5.1.aac` | 19.12 | 19.32 | 17.36 | 11.85 | 13.15 | 18.70 |
| `flac-44k-stereo-16.flac` | 5.87 | 5.76 | 11.30 | 3.33 | 3.55 | 8.29 |
| `flac-48k-5.1-16.flac` | 22.90 | 22.78 | 36.23 | 12.13 | 13.05 | 21.86 |
| `flac-96k-stereo-24.flac` | 22.91 | 20.99 | 26.37 | 12.89 | 11.08 | 14.60 |

FLAC extends grouped LPC prediction to wide sample histories, including
the 24-bit generated fixture, with a scalar fallback for values outside the
SIMD range. AAC bounds stereo reconstruction by the bands actually signaled
by both channels. This closes the 248-sample, one-unit cross-worker difference
on the generated 5.1 fixture. Its output now matches across worker budgets.

The four-core surround repeat used 84 samples. AAC 5.1 measured 15.40 ms for
R16 and 14.12 ms for Swag. FLAC 5.1 measured 12.38 ms for R16 and 12.86 ms
for Swag, versus 22.80 ms for FFmpeg. The 24-bit FLAC gains occurred at both
worker budgets.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. The FLAC and Ogg FLAC PCM
match the preceding build exactly.

Native Release passes 318 audio tests. Release-safe passes
71 focused FLAC and AAC tests.

## Eighteenth optimization pass

This follow-up compares the changed codecs with commit `9a7dab89b5` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round18.json)

| Format | R17 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R17 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 9.52 | 9.60 | 11.34 | 8.71 | 8.88 | 11.23 |
| Ogg FLAC | 8.36 | 8.48 | 11.00 | 8.52 | 8.71 | 11.11 |
| AAC | 6.20 | 6.22 | 6.68 | 6.19 | 6.11 | 6.42 |
| MP3 | 9.25 | 8.97 | 7.81 | 9.11 | 9.19 | 7.94 |

| Format | R17 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| FLAC | 6.21 | 6.58 | 7.21 |
| Ogg FLAC | 6.64 | 6.44 | 6.89 |
| AAC | 4.47 | 4.37 | 6.61 |
| MP3 | 4.49 | 4.79 | 7.86 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R17 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R17 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `aac-lc-32k-mono.aac` | 2.59 | 2.48 | 3.45 | 2.02 | 2.00 | 3.42 |
| `aac-lc-48k-5.1.aac` | 19.53 | 19.01 | 17.92 | 14.62 | 12.67 | 17.36 |
| `aac-lc-48k-stereo.aac` | 8.87 | 8.58 | 8.24 | 5.50 | 5.72 | 8.05 |
| `flac-44k-stereo-16.flac` | 5.93 | 5.95 | 11.48 | 3.34 | 3.40 | 7.46 |
| `flac-48k-5.1-16.flac` | 23.07 | 20.40 | 36.15 | 11.08 | 9.62 | 19.27 |
| `flac-96k-stereo-24.flac` | 21.15 | 17.82 | 27.39 | 10.14 | 8.55 | 13.96 |
| `mp3-48k-stereo.mp3` | 11.14 | 11.15 | 9.52 | 6.07 | 5.86 | 9.43 |

AAC scans escape lengths with a leading-zero count. MP3 fuses the opening
synthesis butterfly with its subband loads and packs the first output
position across slots. FLAC packs scaled stereo output and reuses each
channel pointer while writing six-channel output. The generated fixture
PCM matches R17 at each worker budget and across budgets.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 319 audio tests. Release-safe passes
99 focused AAC, FLAC and MP3 tests.

## Nineteenth optimization pass

This follow-up compares the changed codecs with commit `04127573e4` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round19.json)

| Format | R18 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R18 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MP3 | 9.16 | 8.84 | 7.93 | 8.95 | 8.54 | 7.63 |
| Ogg Vorbis | 6.66 | 6.86 | 7.22 | 6.69 | 6.69 | 7.34 |
| Opus | 22.08 | 20.90 | 20.17 | 21.46 | 20.65 | 19.88 |
| WAV | 1.05 | 0.90 | 26.48 | 1.00 | 0.88 | 25.90 |

| Format | R18 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| MP3 | 5.58 | 4.78 | 8.10 |
| Ogg Vorbis | 6.83 | 7.01 | 7.72 |
| Opus | 22.27 | 21.11 | 19.53 |
| WAV | 1.11 | 1.01 | 28.05 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R18 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R18 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mp3-48k-stereo.mp3` | 10.64 | 10.53 | 9.17 | 6.11 | 6.02 | 9.54 |
| `opus-20ms-48k-stereo.opus` | 31.05 | 29.87 | 31.45 | 33.00 | 28.70 | 29.21 |
| `opus-5ms-48k-stereo.opus` | 32.15 | 29.08 | 33.69 | 31.64 | 29.56 | 34.08 |
| `opus-voip-48k-mono.opus` | 16.26 | 15.76 | 13.70 | 16.48 | 16.56 | 14.62 |
| `vorbis-32k-mono.ogg` | 4.02 | 3.72 | 5.35 | 4.25 | 3.67 | 5.71 |
| `vorbis-48k-5.1.ogg` | 34.30 | 31.74 | 28.71 | 35.81 | 32.18 | 28.83 |
| `vorbis-48k-stereo.ogg` | 9.11 | 9.19 | 10.59 | 9.65 | 9.84 | 11.27 |
| `wav-48k-stereo-24.wav` | 0.63 | 0.60 | 1.49 | 0.72 | 0.71 | 1.91 |

MP3 trims silent bands beyond the current spectrum and saved overlap. Opus
vectorizes stereo CELT synthesis preparation and inlines range operations.
Vorbis packs mono and six-channel PCM output, and contiguous PCM16 ranges
can deliver the input slice directly. The measured Swag builds share the
R18 compiler and Core snapshot.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 320 audio tests. Release-safe passes
64 focused MP3, Opus, Vorbis and WAV tests.

## Twentieth optimization pass

This follow-up compares the changed codecs with commit `d642c28933` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round20.json)

| Format | R19 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R19 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| AC-3 | 9.36 | 9.04 | 8.22 | 9.22 | 8.82 | 8.41 |

| Format | R19 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| AC-3 | 9.08 | 8.78 | 8.34 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R19 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R19 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ac3-32k-mono.ac3` | 5.09 | 5.04 | 4.46 | 5.05 | 5.01 | 4.44 |
| `ac3-44k-stereo.ac3` | 10.56 | 10.53 | 10.19 | 10.29 | 9.77 | 9.68 |
| `ac3-48k-5.1.ac3` | 31.52 | 24.43 | 25.68 | 33.18 | 23.54 | 26.10 |
| `eac3-48k-5.1.eac3` | 42.43 | 23.87 | 26.45 | 44.47 | 24.63 | 27.50 |

E-AC-3 reuses prepared allocation across compatible blocks, processes
grouped mantissas with lookup tables, and shares the AC-3 dither and synthesis
primitives. Both codecs synthesize long 5.1 blocks in channel pairs. The
matched Swag builds use the same compiler and Core sources.

The PCM matches between the one-core and four-core runs. The FileSamples,
generated mono, and generated stereo outputs match R19 bit for bit. The
generated 5.1 outputs differ by at most one PCM16 unit from R19.

Native Release passes 321 audio tests. Release-safe passes
17 focused Dolby tests.

## Twenty-first optimization pass

This follow-up compares the changed codecs with commit `39f20ce765` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round21.json)

| Format | R20 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R20 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MP3 | 8.69 | 8.38 | 7.80 | 9.27 | 9.23 | 8.36 |
| Ogg Vorbis | 6.73 | 6.82 | 7.21 | 7.10 | 7.16 | 7.72 |
| Opus | 21.47 | 21.19 | 20.70 | 20.64 | 19.88 | 20.03 |

| Format | R20 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| MP3 | 5.36 | 5.07 | 7.87 |
| Ogg Vorbis | 6.82 | 7.03 | 7.54 |
| Opus | 21.28 | 19.72 | 19.60 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R20 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R20 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `mp3-48k-stereo.mp3` | 10.49 | 10.26 | 9.15 | 7.14 | 6.03 | 9.55 |
| `opus-20ms-48k-stereo.opus` | 29.09 | 28.55 | 29.67 | 29.21 | 28.66 | 28.87 |
| `opus-5ms-48k-stereo.opus` | 28.53 | 27.99 | 32.08 | 29.14 | 28.67 | 33.02 |
| `opus-voip-48k-mono.opus` | 15.68 | 15.65 | 13.44 | 16.23 | 16.29 | 13.98 |
| `vorbis-32k-mono.ogg` | 3.44 | 3.53 | 5.00 | 3.60 | 3.73 | 5.07 |
| `vorbis-48k-5.1.ogg` | 29.40 | 28.03 | 27.32 | 29.83 | 28.38 | 27.12 |
| `vorbis-48k-stereo.ogg` | 9.23 | 9.12 | 10.10 | 8.93 | 9.21 | 10.15 |

MP3 clears the spectral workspace with a bulk memory operation. Opus
refills raw bits in groups and normalizes packed integer PVQ pulses.
Vorbis decodes five-value type-2 residue vectors directly into five
planar outputs. All selected outputs are byte-identical to R20.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 321 audio tests. Release-safe passes
48 focused MP3, Opus and Vorbis tests.

## Twenty-second optimization pass

This follow-up compares the changed codecs with commit `c7bac1acde` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round22.json)

| Format | R21 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R21 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 11.10 | 10.96 | 13.14 | 10.07 | 9.93 | 12.14 |
| Ogg FLAC | 9.26 | 9.31 | 11.72 | 9.43 | 9.29 | 11.80 |
| MP3 | 9.10 | 9.16 | 8.51 | 9.08 | 8.96 | 8.47 |

| Format | R21 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| FLAC | 7.07 | 7.07 | 8.21 |
| Ogg FLAC | 6.84 | 6.89 | 8.43 |
| MP3 | 4.87 | 5.01 | 8.67 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R21 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R21 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `flac-44k-stereo-16.flac` | 6.59 | 6.56 | 12.58 | 3.59 | 3.56 | 7.95 |
| `flac-48k-5.1-16.flac` | 21.42 | 21.37 | 38.80 | 11.29 | 10.88 | 20.82 |
| `flac-96k-stereo-24.flac` | 19.19 | 18.19 | 28.50 | 9.63 | 9.82 | 16.10 |
| `mp3-24k-mono.mp3` | 3.03 | 3.09 | 3.31 | 2.15 | 2.14 | 2.93 |
| `mp3-48k-stereo.mp3` | 10.59 | 10.90 | 9.75 | 5.93 | 5.91 | 9.41 |
| `mp3-8k-mono.mp3` | 1.10 | 1.06 | 1.33 | 0.85 | 0.84 | 1.28 |
| `ogg-flac-48k-mono-16.oga` | 4.34 | 3.78 | 6.95 | 2.70 | 2.31 | 5.17 |

FLAC groups wider Rice residuals, simplifies the mid-side combination,
and reuses the mono output pointer. MP3 mirrors the history prefix used
across the ring boundary and writes each transform half straight to history.
The original MP3 results varied by CPU. The 84-sample CPU 2 repeat measured
8.66 to 8.60 ms on FileSamples and 10.63 to 10.46 ms on the generated
48 kHz stereo fixture. PCM is byte-identical across these changes.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 321 audio tests. Release-safe passes
59 focused FLAC and MP3 tests.

## Twenty-third optimization pass

This follow-up compares the changed codecs with commit `98a3032b32` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round23.json)

| Format | R22 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R22 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ogg FLAC | 8.92 | 8.79 | 11.07 | 8.78 | 8.58 | 11.21 |
| AAC | 6.30 | 6.28 | 6.79 | 6.25 | 6.31 | 6.63 |
| Ogg Vorbis | 7.14 | 7.05 | 7.61 | 6.76 | 6.66 | 7.18 |
| Opus | 20.29 | 20.41 | 20.24 | 19.46 | 19.88 | 19.54 |

| Format | R22 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| Ogg FLAC | 6.21 | 6.24 | 7.96 |
| AAC | 4.75 | 4.47 | 6.70 |
| Ogg Vorbis | 6.70 | 6.73 | 7.10 |
| Opus | 19.97 | 19.55 | 19.42 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R22 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R22 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `aac-lc-32k-mono.aac` | 2.40 | 2.42 | 3.41 | 2.32 | 2.22 | 3.42 |
| `aac-lc-48k-5.1.aac` | 18.43 | 18.50 | 17.55 | 11.19 | 9.66 | 17.49 |
| `aac-lc-48k-stereo.aac` | 8.34 | 8.32 | 7.84 | 5.59 | 5.98 | 8.37 |
| `ogg-flac-48k-mono-16.oga` | 3.64 | 3.64 | 6.48 | 2.60 | 2.25 | 5.91 |
| `opus-5ms-48k-stereo.opus` | 28.07 | 28.32 | 32.68 | 28.50 | 28.97 | 33.07 |
| `vorbis-32k-mono.ogg` | 3.60 | 3.44 | 4.93 | 3.72 | 3.49 | 5.09 |
| `vorbis-48k-5.1.ogg` | 27.59 | 26.80 | 27.25 | 28.08 | 28.27 | 28.04 |
| `vorbis-48k-stereo.ogg` | 8.96 | 8.85 | 9.99 | 9.00 | 8.89 | 10.19 |

AAC merges packets inside their existing six-channel synthesis lanes
and handles only lane boundaries in the final merge. It also simplifies
the escape-value test. Vorbis reduces codebook build work. Ogg reuses the
verified page slice and masks its stored checksum in the SIMD fold. All
selected PCM remains byte-identical to R22.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 322 audio tests. Release-safe passes
69 focused AAC, Ogg, Opus and Vorbis tests.

## Twenty-fourth optimization pass

This follow-up compares the changed codecs with commit `408651d6bd` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round24.json)

| Format | R23 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R23 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 8.84 | 8.82 | 11.00 | 8.91 | 9.42 | 11.63 |
| Ogg FLAC | 7.90 | 7.82 | 10.46 | 8.16 | 8.23 | 11.11 |
| Opus | 19.79 | 19.63 | 19.35 | 20.03 | 19.65 | 19.52 |

| Format | R23 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| FLAC | 6.62 | 6.38 | 7.69 |
| Ogg FLAC | 6.83 | 6.98 | 8.04 |
| Opus | 20.21 | 19.84 | 20.29 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R23 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R23 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `flac-44k-stereo-16.flac` | 6.04 | 5.95 | 11.38 | 3.45 | 3.42 | 7.48 |
| `flac-48k-5.1-16.flac` | 20.03 | 18.86 | 35.31 | 10.01 | 9.41 | 19.47 |
| `flac-96k-stereo-24.flac` | 16.62 | 16.58 | 26.08 | 9.53 | 9.00 | 15.29 |
| `ogg-flac-48k-mono-16.oga` | 3.68 | 3.35 | 6.59 | 2.48 | 2.08 | 5.82 |
| `opus-20ms-48k-stereo.opus` | 28.25 | 28.46 | 29.88 | 30.43 | 29.41 | 29.46 |
| `opus-5ms-48k-stereo.opus` | 28.31 | 28.45 | 32.30 | 27.81 | 27.37 | 32.27 |
| `opus-voip-48k-mono.opus` | 15.72 | 15.92 | 13.64 | 16.00 | 16.39 | 14.38 |

FLAC packs mono and six-channel PCM16 with exact saturation even for wide
intermediate values. Opus reserves space for two maximum CELT frames before
moving the pitch and overlap history. The larger window uses 7,200 more bytes
for a stereo decoder. The generated voice fixture took 0.20 ms longer on
one core and 0.39 ms longer at the four-core budget in this series.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 323 audio tests. Release-safe passes
43 focused FLAC and Opus tests.

## Twenty-fifth optimization pass

This follow-up compares the changed codecs with commit `e0052e7dce` and native FFmpeg.
Each median uses 56 samples and includes opening and materializing ten seconds of PCM16.
[Raw stage times and PCM deltas](audio-decode-linux-round25.json)

| Format | R24 CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | R24 CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 9.20 | 9.15 | 11.33 | 8.92 | 8.73 | 11.10 |
| Ogg FLAC | 8.39 | 8.58 | 10.92 | 8.23 | 8.46 | 11.05 |

| Format | R24 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: |
| FLAC | 6.47 | 6.36 | 7.19 |
| Ogg FLAC | 6.21 | 6.09 | 7.88 |


The generated-fixture medians use 42 samples per worker budget.

| Fixture | R24 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | R24 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `flac-44k-stereo-16.flac` | 5.80 | 5.83 | 10.99 | 3.54 | 3.50 | 7.71 |
| `flac-48k-5.1-16.flac` | 18.46 | 18.64 | 35.10 | 10.31 | 10.30 | 20.80 |
| `flac-96k-stereo-24.flac` | 16.38 | 16.56 | 25.92 | 9.72 | 10.49 | 17.35 |
| `flac-verbatim-48k-stereo-16.flac` | 7.32 | 1.64 | 5.70 | 5.71 | 1.89 | 7.33 |
| `flac-verbatim-48k-stereo-24.flac` | 9.06 | 2.02 | 7.12 | 6.78 | 2.27 | 9.03 |
| `flac-verbatim-48k-stereo-32.flac` | 12.23 | 3.57 | 9.21 | 7.68 | 3.30 | 10.76 |
| `ogg-flac-48k-mono-16.oga` | 3.46 | 3.47 | 6.84 | 2.31 | 2.41 | 6.34 |

FLAC decodes consecutive verbatim signed samples from a bounded bit
window. Three deterministic, stereo 48 kHz verbatim fixtures exercise
16-, 24- and 32-bit samples. The 22 previous fixture hashes are unchanged.
The new PCM16 outputs are byte-identical to native FFmpeg and R24.

The PCM matches between the one-core and four-core runs, with a peak difference of
one PCM16 unit from the original Swag output. All files match the preceding build
bit for bit.

Native Release passes 324 audio tests. Release-safe passes
33 focused FLAC tests.

## Twenty-eighth optimization pass

This pass compares MP3 and Dolby on the same native Release compiler against
`d7e3bc1803` and native FFmpeg 7.1.5. Each FileSamples median uses 56 samples
and includes opening and materializing the first ten seconds of PCM16.

[Raw stage times and PCM deltas](audio-decode-linux-round28.json)

| Format | Before CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | Before CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| AC-3 | 9.64 | 9.04 | 8.74 | 9.34 | 8.89 | 8.20 | 8.98 | 8.34 | 7.88 |
| MP3 | 8.57 | 7.89 | 7.88 | 8.25 | 7.71 | 7.67 | 5.79 | 5.72 | 8.13 |

The generated-fixture medians use 42 samples per worker budget.

| Fixture | Before 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ac3-32k-mono.ac3` | 8.73 | 8.62 | 8.09 | 4.88 | 4.83 | 4.23 |
| `ac3-44k-stereo.ac3` | 17.74 | 17.13 | 17.18 | 9.95 | 9.88 | 9.25 |
| `ac3-48k-5.1.ac3` | 23.43 | 22.74 | 24.45 | 25.10 | 23.74 | 24.62 |
| `eac3-48k-5.1.eac3` | 23.63 | 23.06 | 24.45 | 23.26 | 23.66 | 25.08 |
| `mp3-24k-mono.mp3` | 2.78 | 2.61 | 2.89 | 2.32 | 1.91 | 3.00 |
| `mp3-48k-stereo.mp3` | 10.47 | 9.52 | 9.32 | 5.92 | 5.91 | 9.24 |
| `mp3-8k-mono.mp3` | 1.04 | 1.00 | 1.30 | 0.76 | 0.88 | 1.43 |

MP3 reads guarded bit windows directly, updates only the bit position when it
consumes a code, and applies a Huffman sample sign with integer XOR. Its PCM is
byte-identical to the preceding build. AC-3 fuses stereo synthesis and packs
the resulting PCM in pairs. Dolby reuses the current header-read window.

AC-3 FileSamples changes 29 samples and generated stereo changes 17, with a
maximum difference of one PCM16 unit. The other generated Dolby files remain
byte-identical. Both FileSamples outputs stay within one PCM16 unit of the
original Swag reference. All nine outputs match across worker budgets.
AC-3 FileSamples still trails native FFmpeg. MP3 approaches parity on one core
and leads with four cores in this series.

Native Release passes 325 audio tests. Release-safe passes 38 focused MP3 and
Dolby functional tests.

## Twenty-ninth optimization pass

This pass compares Opus and Vorbis on the same native Release compiler against
`acfe1f9c13` and native FFmpeg 7.1.5. Each FileSamples median uses 56 samples
and includes opening and materializing the first ten seconds of PCM16.

[Raw stage times and PCM deltas](audio-decode-linux-round29.json)

| Format | Before CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | Before CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Opus | 20.64 | 20.05 | 20.24 | 20.07 | 19.79 | 19.94 | 20.34 | 20.35 | 20.64 |
| Vorbis | 7.09 | 7.01 | 7.52 | 6.98 | 6.58 | 7.30 | 7.88 | 7.47 | 7.85 |

The generated-fixture medians use 42 samples per worker budget.

| Fixture | Before 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `opus-20ms-48k-stereo.opus` | 27.85 | 27.94 | 28.91 | 28.41 | 28.97 | 29.59 |
| `opus-5ms-48k-stereo.opus` | 28.57 | 27.62 | 34.21 | 29.05 | 28.08 | 34.43 |
| `opus-voip-48k-mono.opus` | 16.08 | 15.41 | 13.76 | 16.18 | 15.62 | 13.90 |
| `vorbis-32k-mono.ogg` | 3.52 | 3.44 | 5.49 | 3.56 | 3.66 | 5.27 |
| `vorbis-48k-5.1.ogg` | 27.60 | 27.85 | 27.88 | 28.48 | 28.27 | 29.18 |
| `vorbis-48k-stereo.ogg` | 8.84 | 8.77 | 10.23 | 9.06 | 8.83 | 10.42 |

Opus writes stereo CELT overlap in pairs without changing the order of floating-point
operations. Its SILK resampler combines four FIR outputs in one loop while preserving
each integer accumulation. Vorbis borrows the initial Ogg header payloads and reuses
the ninth entropy bit in the stereo residue path.

All eight fixtures produce byte-identical PCM to the previous build and across worker
budgets. The two FileSamples outputs stay within one PCM16 unit of the original Swag
reference. FileSamples Opus leads native FFmpeg by 0.15 to 0.29 ms in this series.
The low-rate voice fixture still trails by 1.66 ms on one core. Generated 20 ms Opus
and mono Vorbis take slightly longer with four cores and remain ahead of FFmpeg.

Native Release passes 325 audio tests. Release-safe passes 28 focused Ogg, Opus and
Vorbis tests.

## Thirty-first optimization pass

This pass compares Swag against `ef5b06b283` on the same Release compiler and
against [FFmpeg 9.1](https://github.com/FFmpeg/FFmpeg/tree/n9.1). The native
reference includes the relevant audio codecs and x86 assembly with runtime CPU
dispatch. Each median uses 42 samples. Total time includes opening and writing
up to ten seconds of interleaved PCM16 to memory.

[Raw stage times, PCM digests, and fixture manifest](audio-decode-linux-round31.json)

| FileSamples format | Before 1 core (ms) | Swag 1 core (ms) | FFmpeg 9.1 1 core (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 9.1 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FLAC | 8.84 | 8.99 | 9.92 | 6.64 | 6.29 | 6.81 |
| Ogg FLAC | 8.25 | 8.35 | 9.54 | 6.58 | 7.06 | 6.77 |
| AAC | 6.12 | 6.16 | 6.36 | 4.34 | 4.05 | 6.14 |
| AC-3 | 8.31 | 7.29 | 6.40 | 8.55 | 7.61 | 6.60 |
| DTS | 12.64 | 12.84 | 12.67 | 12.37 | 12.14 | 13.36 |
| MP3 | 8.08 | 7.78 | 7.21 | 4.07 | 3.94 | 7.00 |
| Ogg Vorbis | 6.69 | 6.74 | 6.64 | 6.81 | 6.59 | 6.62 |
| Opus | 20.74 | 20.95 | 18.79 | 20.29 | 19.76 | 18.65 |
| WAV | 0.91 | 0.90 | 8.10 | 1.00 | 1.00 | 8.45 |

The raw data includes a second single-core FileSamples run on CPU 1 for AC-3,
MP3, Vorbis and Opus. The WAV result includes over 7 ms of open time in FFmpeg
9.1 on this file. Its decode stage is faster than Swag's.

| Generated input | Before 1 core (ms) | Swag 1 core (ms) | FFmpeg 9.1 1 core (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 9.1 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ac3-32k-mono.ac3` | 4.84 | 4.49 | 3.69 | 5.01 | 4.52 | 3.59 |
| `ac3-32k-stereo.ac3` | 7.66 | 7.02 | 6.14 | 7.80 | 7.49 | 6.68 |
| `ac3-44k-stereo.ac3` | 9.35 | 8.57 | 7.21 | 9.36 | 9.02 | 7.36 |
| `ac3-48k-5.1.ac3` | 24.89 | 23.05 | 22.21 | 23.83 | 22.73 | 21.86 |
| `ac3-48k-stereo.ac3` | 9.52 | 8.79 | 7.45 | 9.66 | 9.14 | 7.58 |
| `eac3-48k-5.1.eac3` | 23.35 | 21.62 | 21.54 | 24.62 | 22.78 | 21.72 |
| `mp3-24k-mono.mp3` | 2.65 | 2.67 | 2.67 | 2.01 | 1.95 | 2.54 |
| `mp3-44k-stereo-cbr.mp3` | 8.34 | 8.07 | 7.06 | 4.49 | 3.95 | 7.37 |
| `mp3-48k-stereo.mp3` | 9.18 | 9.18 | 8.05 | 5.44 | 5.55 | 8.11 |
| `mp3-8k-mono.mp3` | 0.99 | 0.99 | 1.10 | 0.71 | 0.74 | 1.11 |
| `vorbis-32k-mono.ogg` | 3.50 | 3.46 | 4.26 | 3.46 | 3.39 | 4.43 |
| `vorbis-48k-5.1.ogg` | 28.59 | 28.06 | 27.49 | 27.01 | 27.59 | 26.15 |
| `vorbis-48k-7.1.ogg` | 39.79 | 35.75 | 32.34 | 40.02 | 34.95 | 32.34 |
| `vorbis-48k-stereo.ogg` | 8.72 | 8.95 | 9.06 | 9.04 | 9.03 | 9.44 |
| `opus-20ms-48k-stereo.opus` | 27.65 | 27.75 | 26.47 | 28.55 | 28.89 | 26.72 |
| `opus-5ms-48k-stereo.opus` | 27.51 | 27.44 | 29.73 | 27.83 | 27.52 | 30.97 |
| `opus-voip-16k-mono.opus` | 8.75 | 8.14 | 9.62 | 8.80 | 8.17 | 9.80 |
| `opus-voip-48k-mono.opus` | 15.33 | 14.65 | 13.05 | 15.79 | 14.86 | 13.13 |
| `dts-48k-stereo.dts` | 13.32 | 13.05 | 13.39 | 12.93 | 12.86 | 14.28 |

Dolby reads literal fields and mantissas through guarded 32-bit windows.
MP3 reads adjacent side-information fields together. SILK combines its common
LPC saturation checks and keeps the same edge behavior. Vorbis interleaves
eight PCM16 planes with vector stores. All 26 Swag outputs are byte-identical
to the preceding build and across worker budgets.

The corpus now has 31 generated fixtures. The previous 25 SHA-256 digests
are unchanged. The 7.1 Vorbis case improves by 4.04 ms at one core and
5.08 ms at four cores. The new 16 kHz voice input improves by 0.61 ms
and leads FFmpeg 9.1. The 48 kHz voice case and FileSamples Opus still trail
the newer reference, as do FileSamples AC-3 and single-core MP3.

Native Release passes 327 audio tests. Release-safe passes 67 focused Dolby,
MP3, Ogg, Opus and Vorbis tests.

## Thirty-third optimization pass

Both Swag builds use the same updated native Release compiler, built from
`acfe1f9c13`, and audio sources based on `eed36df2cf`. The reference is
FFmpeg 9.1. The 42-sample medians include opening and materializing up to
ten seconds of PCM16. The single-core runs use CPU 3.

[Raw stage times and PCM digests](audio-decode-linux-round33.json)

| Input | Before 1 core (ms) | Swag 1 core (ms) | FFmpeg 9.1 1 core (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 9.1 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample3.dts` | 11.38 | 11.64 | 12.22 | 13.55 | 12.79 | 14.20 |
| `sample3.ogg` | 6.53 | 6.47 | 6.44 | 6.87 | 6.69 | 6.62 |
| `dts-48k-5.1.dts` | 32.86 | 33.00 | 33.08 | 31.60 | 31.52 | 33.02 |
| `dts-48k-stereo.dts` | 13.19 | 12.80 | 13.51 | 13.30 | 13.32 | 13.64 |
| `vorbis-32k-mono.ogg` | 3.46 | 3.42 | 4.30 | 3.48 | 3.40 | 4.38 |
| `vorbis-48k-5.1.ogg` | 27.22 | 26.71 | 25.89 | 27.54 | 27.13 | 25.91 |
| `vorbis-48k-7.1.ogg` | 35.70 | 34.00 | 32.37 | 35.97 | 34.83 | 32.43 |
| `vorbis-48k-stereo.ogg` | 8.90 | 8.72 | 9.65 | 8.81 | 8.87 | 9.10 |

DTS reuses parsed dimensions and packet sizes when the entire core header
repeats. On the FileSamples four-core run, the median open stage drops from
3.71 to 3.20 ms. The single-core open medians are close. A corrupted header
after two matching packets still fails validation. Vorbis computes its floor
line slope using a fixed-point reciprocal while preserving exact positions.

All eight files retain byte-identical PCM, including across one and four
worker budgets. The 7.1 Vorbis fixture improves by 1.70 and 1.13 ms and remains
behind FFmpeg 9.1.

Native Release passes 328 audio tests. Release-safe passes 19 focused
DTS and Vorbis tests.

## Thirty-fifth optimization pass

The same native Release compiler compares the updated Swag decoders,
`b6e4283c9a` and native FFmpeg 9.1. Each median uses 42 samples and
includes opening and materializing up to ten seconds of interleaved PCM16.

[Raw stage times and PCM digests](audio-decode-linux-round35.json)

| FileSamples format | Before CPU 0 (ms) | Swag CPU 0 (ms) | FFmpeg CPU 0 (ms) | Before CPU 1 (ms) | Swag CPU 1 (ms) | FFmpeg CPU 1 (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `sample3.ac3` | 8.22 | 7.45 | 6.79 | 7.39 | 7.04 | 6.17 | 7.53 | 7.17 | 6.44 |
| `sample3.mp3` | 8.15 | 7.90 | 7.08 | 8.11 | 8.00 | 7.36 | 5.20 | 5.11 | 7.05 |
| `sample3.ogg` | 6.50 | 6.63 | 6.48 | 6.46 | 6.51 | 6.43 | 6.50 | 6.56 | 6.52 |
| `sample3.opus` | 19.47 | 19.63 | 17.73 | 19.57 | 19.80 | 18.07 | 19.92 | 20.23 | 17.98 |

| Generated input | Before 1 core (ms) | Swag 1 core (ms) | FFmpeg 1 core (ms) | Before 4 cores (ms) | Swag 4 cores (ms) | FFmpeg 4 cores (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `ac3-32k-mono.ac3` | 4.44 | 4.26 | 3.50 | 4.47 | 4.28 | 3.66 |
| `ac3-32k-stereo.ac3` | 7.19 | 6.88 | 6.28 | 6.98 | 6.87 | 6.20 |
| `ac3-44k-stereo.ac3` | 8.68 | 8.44 | 7.25 | 8.69 | 8.31 | 7.06 |
| `ac3-48k-5.1.ac3` | 21.99 | 21.31 | 20.96 | 22.80 | 21.82 | 21.79 |
| `ac3-48k-stereo.ac3` | 8.46 | 8.30 | 7.13 | 9.19 | 8.85 | 8.05 |
| `eac3-48k-5.1.eac3` | 22.52 | 22.42 | 22.00 | 22.85 | 22.37 | 22.91 |
| `mp3-24k-mono.mp3` | 2.74 | 2.62 | 2.67 | 1.88 | 1.87 | 2.81 |
| `mp3-44k-stereo-cbr.mp3` | 8.49 | 8.04 | 7.12 | 4.87 | 4.08 | 7.03 |
| `mp3-48k-stereo.mp3` | 9.62 | 9.45 | 8.52 | 6.38 | 5.87 | 8.57 |
| `mp3-8k-mono.mp3` | 1.03 | 0.97 | 1.10 | 0.84 | 0.74 | 1.19 |
| `vorbis-32k-mono.ogg` | 3.48 | 3.46 | 4.42 | 3.75 | 3.58 | 4.41 |
| `vorbis-48k-5.1.ogg` | 27.83 | 27.80 | 26.22 | 27.06 | 20.30 | 26.45 |
| `vorbis-48k-7.1.ogg` | 34.66 | 34.54 | 32.35 | 33.60 | 25.03 | 32.77 |
| `vorbis-48k-stereo.ogg` | 8.66 | 8.87 | 9.38 | 8.51 | 8.54 | 9.04 |
| `opus-20ms-48k-stereo.opus` | 28.31 | 28.99 | 27.18 | 27.93 | 28.11 | 26.93 |
| `opus-5ms-48k-stereo.opus` | 27.26 | 27.41 | 29.38 | 27.65 | 28.06 | 29.54 |
| `opus-voip-16k-mono.opus` | 8.17 | 7.53 | 9.71 | 7.96 | 7.47 | 9.58 |
| `opus-voip-48k-mono.opus` | 15.11 | 14.96 | 13.24 | 14.77 | 14.32 | 13.09 |

Offline Vorbis decoding can split complete packets on a surround Ogg page
into two independent batches and reconstruct the worker overlap with one
preceding packet. It retains serial handling of packet fragments. The
new path applies to native offline surround decodes with multiple workers.
AC-3 uses precomputed exponent group deltas. MP3 uses a second Huffman
lookup and fuses its first IMDCT butterfly. SILK avoids duplicate copies and
unneeded work for unvoiced frames.

All 22 selected inputs produce byte-identical PCM to the preceding build
and across one and four workers. Four-core Vorbis 5.1 and 7.1 lead FFmpeg
in this series. FileSamples MP3 is ahead at four cores and still trails
on one. FileSamples Opus takes 0.16–0.31 ms longer in these cohorts, while
both generated voice cases improve in the four-core runs.

Native Release passes 330 audio tests. Release-safe passes 68 focused
Dolby, MP3, Opus, Ogg and Vorbis tests.
