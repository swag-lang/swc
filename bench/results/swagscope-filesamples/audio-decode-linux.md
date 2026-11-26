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
