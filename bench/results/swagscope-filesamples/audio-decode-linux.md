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
