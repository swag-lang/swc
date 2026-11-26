# Audio encoding on Linux

The [audio encoding workload](../../workloads/audioencode/README.md) submits PCM16
straight from memory and records encoder setup, sample submission and finalization.

## AAC-LC encoder

Swag baseline `48b09f94f4` and the candidate use the same native Release compiler.
FFmpeg 7.1.5 uses its AAC-LC two-loop encoder. Each median has 12 samples on CPU 2
of an AMD EPYC 7763. Inputs contain ten seconds of PCM16. The reference payload
rate is within one percent of Swag on every case.

[Raw timings, input and output digests, and quality metrics](audio-encode-linux-round1.json)

| Input | Swag before (ms) | Swag after (ms) | FFmpeg (ms) | Swag (kb/s) | FFmpeg (kb/s) | Swag SNR (dB) | FFmpeg SNR (dB) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Mono 48 kHz | 18.93 | 10.36 | 187.03 | 93.57 | 93.51 | 28.92 | 25.10 |
| Stereo 44.1 kHz | 34.28 | 18.79 | 409.04 | 182.14 | 183.04 | 28.96 | 24.41 |
| Stereo 48 kHz | 35.98 | 19.59 | 406.51 | 188.41 | 187.28 | 28.80 | 24.03 |
| FileSamples stereo 44.1 kHz | 36.28 | 19.19 | 285.21 | 221.53 | 220.49 | 28.45 | 25.31 |
| Voice mono 48 kHz | 8.91 | 6.59 | 104.66 | 26.47 | 26.43 | 20.42 | 19.43 |

The Swag bitstream matches the baseline byte for byte for all five cases, including the
voice profile. Its writer emits full bytes from a bit reservoir and packs signed Huffman
pairs ahead of time. Quantization uses square roots and retains the original power call
near rounding ties. SNR is measured after removing the declared AAC priming.

Native Release passes 324 audio tests. Release-safe passes 43 focused AAC tests.

## FLAC encoder

Native Swag Release at `e2b6049ee1` and the updated writer were measured on ten
seconds of PCM16, with 12 samples per engine on CPU 1 of the same machine.
FFmpeg 7.1.5 and libFLAC 1.5.0 both use compression level 0. Wall time includes
opening, submitting and finishing. PCM starts in memory.

[Raw FLAC and WAV timings and PCM checks](audio-encode-linux-round2.json)

| Input | Swag before (ms) | Swag after (ms) | FFmpeg (ms) | libFLAC (ms) | Swag bytes | FFmpeg bytes | libFLAC bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 66.16 | 11.50 | 17.32 | 11.18 | 1,322,646 | 1,078,819 | 1,052,820 |
| Mono 48 kHz | 29.95 | 5.82 | 8.88 | 5.83 | 644,435 | 415,241 | 423,470 |
| Stereo noise 48 kHz | 69.51 | 8.95 | 16.94 | 13.38 | 1,921,810 | 1,932,747 | 1,924,547 |
| Stereo 44.1 kHz | 55.10 | 10.63 | 16.33 | 10.07 | 1,199,241 | 783,950 | 806,276 |
| Stereo 48 kHz | 62.92 | 12.14 | 17.20 | 12.03 | 1,294,291 | 798,554 | 782,810 |
| 5.1 at 48 kHz | 180.91 | 32.70 | 45.09 | 33.14 | 3,779,482 | 2,359,220 | 2,430,017 |

The writer restricts the exact Rice cost search to the parameters around the
mean folded residual, computes their costs in batches and emits groups of bits
through a word buffer. It preserves the previous FLAC bitstream for all six
inputs. FFmpeg decodes the output of all engines back to the original PCM.
The results show the remaining compression gap on structured inputs, including
stereo and 5.1. Native Release passes 325 audio tests and Release-safe passes
42 focused FLAC and WAV tests.

## WAV encoder

The native Release writer at `e2b6049ee1` and FFmpeg 7.1.5 encode the same
ten-second PCM16 input to a shared pathname on one core. Each median has 60
samples under each filesystem. All WAV files decode to the original PCM.

| Input | Swag overlay (ms) | FFmpeg overlay (ms) | Swag tmpfs (ms) | FFmpeg tmpfs (ms) |
| --- | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 1.35 | 1.25 | 0.38 | 0.55 |
| Mono 48 kHz | 0.93 | 0.92 | 0.23 | 0.38 |
| Stereo 48 kHz | 1.40 | 1.41 | 0.42 | 0.59 |

The FFmpeg WAV header adds 34 bytes to each file. The Swag file includes a
44-byte RIFF header and the original PCM bytes.

## Exact AAC quantization and denser FLAC encoding

Both Swag builds use the same native Release compiler, with `ea5f49e640` as
the baseline. Primary medians use 12 samples per engine pinned to CPU 3.
The inputs contain ten seconds of interleaved PCM16.

[Raw stage times, output sizes, and PCM checks](audio-encode-linux-round3.json)

### AAC-LC

| Input | Swag before (ms) | Swag after (ms) | FFmpeg 7.1.5 (ms) | Swag (kb/s) | FFmpeg (kb/s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 21.28 | 14.95 | 295.63 | 221.53 | 220.49 |
| Mono 48 kHz | 10.06 | 7.30 | 176.10 | 93.57 | 93.51 |
| Voice mono 48 kHz | 5.06 | 3.98 | 93.43 | 26.47 | 26.43 |
| Stereo 44.1 kHz | 19.75 | 13.78 | 441.28 | 182.14 | 183.04 |
| Stereo 48 kHz | 19.72 | 14.44 | 389.37 | 188.41 | 189.70 |

Quantization compares each coefficient with the exact binary32 magnitude
thresholds. The encoder folds the MDCT input directly and expands its
coefficients in vector pairs. All five Swag ADTS outputs are identical to
the baseline, including the voice profile.

### FLAC PCM16

| Input | Swag before (ms) | Swag after (ms) | FFmpeg 7.1.5 level 0 (ms) | libFLAC 1.5.0 level 0 (ms) | Swag bytes before | Swag bytes after | FFmpeg bytes | libFLAC bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 10.75 | 9.69 | 16.18 | 10.39 | 1,322,646 | 1,214,438 | 1,078,819 | 1,052,820 |
| Mono 48 kHz | 5.76 | 5.14 | 10.31 | 5.84 | 644,435 | 563,722 | 415,241 | 423,470 |
| Stereo 44.1 kHz | 10.79 | 10.80 | 15.98 | 10.47 | 1,199,241 | 1,083,638 | 783,950 | 806,276 |
| Stereo 48 kHz | 13.78 | 10.07 | 17.24 | 11.39 | 1,294,291 | 1,130,810 | 798,554 | 782,810 |
| 5.1 at 48 kHz | 51.17 | 33.14 | 57.99 | 36.98 | 3,779,482 | 3,267,599 | 2,359,220 | 2,430,017 |
| Stereo noise 48 kHz | 8.85 | 8.48 | 18.17 | 13.05 | 1,921,810 | 1,921,810 | 1,932,747 | 1,924,547 |

The writer costs first- and second-order fixed subframes, chooses the smaller
available representation, and reserves the complete Rice output before
emitting it. Both Swag outputs and both reference outputs decode to the
original PCM. The five structured inputs are 8.2–13.5% smaller than the
previous Swag files. The noise output keeps the same size.
Stereo 44.1 kHz is effectively tied with the previous Swag writer on time.

For level 5, FFmpeg and libFLAC produced 917,696 and 905,396 bytes on FileSamples
and 2,682,535 and 2,652,952 bytes on 5.1. The same Swag output is faster to
encode than both level-5 references on these inputs in this series.

### FFmpeg 9.1 reference

These two additional comparisons use the same benchmark with FFmpeg 9.1,
with native x86 assembly enabled. They use 12 samples per engine on CPU 0.

| Input | Swag before (ms) | Swag after (ms) | FFmpeg 9.1 (ms) | Swag bytes | FFmpeg bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| AAC stereo 48 kHz | 32.82 | 18.69 | 799.66 | 238,799 | 239,905 |
| FLAC 5.1 at 48 kHz, level 0 reference | 37.26 | 34.19 | 33.33 | 3,267,599 | 2,359,222 |

The AAC reference payload rate is within 1% of Swag. The FLAC outputs decode
to the same PCM. FFmpeg 9.1 is slightly faster on this 5.1 encoding case and
its FLAC file is smaller.

Native Release passes 326 audio tests. Release-safe passes 55 focused AAC,
MDCT and FLAC writer tests.

## AAC packet buffering and short FLAC prefixes

Swag builds use the same native Release compiler and `642ebed850` as the
baseline. Each input contains ten seconds of PCM16. The Swag repeat alternates
builds at the same tmpfs output path on CPU 3, with 60 samples from each.
The separate overlay series compares native FFmpeg 9.1 with x86 assembly,
with 12 samples per engine on CPU 3.

[Raw stage times, output sizes, and decoded PCM checks](audio-encode-linux-round4.json)

| AAC input | Before tmpfs (ms) | Swag tmpfs (ms) | Swag overlay (ms) | FFmpeg 9.1 overlay (ms) | Swag (kb/s) | FFmpeg (kb/s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 14.05 | 11.46 | 13.15 | 516.08 | 221.53 | 222.76 |
| Mono 48 kHz | 7.20 | 5.71 | 9.85 | 275.16 | 93.57 | 93.94 |
| Stereo 44.1 kHz | 13.28 | 10.63 | 12.26 | 680.97 | 182.14 | 182.72 |
| Stereo 48 kHz | 13.78 | 11.24 | 12.83 | 625.47 | 188.41 | 189.29 |
| Stereo noise 48 kHz | 18.78 | 14.41 | 14.59 | 207.73 | 527.71 | 475.83 |
| Voice mono 48 kHz | 3.73 | 3.37 | 5.58 | 125.56 | 26.47 | 26.71 |

The encoder collects per-band magnitude peaks with SIMD and flushes full
32-bit words into bounded packet storage. All six ADTS outputs remain
byte-identical to the previous Swag build. The noise comparison uses
different achieved payload rates. The other native reference rates stay
within 1% of Swag.

The FLAC writer keeps STREAMINFO block bounds at or above 16 samples while
preserving the exact lengths of short frames and accepting older checkpoints
on resume. FFmpeg and libFLAC decode single-sample, mixed-size flush and
legacy-resume cases to the original PCM. The two ten-second FLAC benchmark
files remain byte-identical to the previous writer.

Native Release passes 328 audio tests. Release-safe passes 56 focused AAC,
MDCT and FLAC writer tests.

## AAC zero-band quantization and partitioned FLAC

Both Swag builds use the same native Release compiler, with `9ec4f3b2c5`
as the audio baseline. Each run submits ten seconds of PCM16. The medians
use 12 samples per engine on CPU 3.

[Raw stage times, quality metrics, and byte counts](audio-encode-linux-round5.json)

### AAC-LC against FFmpeg 9.1 and FDK AAC 2.0.3

The columns under each reference come from interleaved runs against the same
Swag builds. FDK uses AAC-LC with afterburner enabled. Achieved payload rates
are within 1% for these five cases. The native encoder delay is removed before
amplitude comparison.

| Input | Swag before with FFmpeg (ms) | Swag with FFmpeg (ms) | FFmpeg (ms) | Swag with FDK (ms) | FDK (ms) | Swag SNR (dB) | FFmpeg SNR (dB) | FDK SNR (dB) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 12.45 | 9.13 | 480.83 | 9.03 | 121.48 | 28.45 | 21.24 | 32.51 |
| Mono 48 kHz | 6.41 | 4.73 | 267.85 | 4.53 | 53.88 | 28.92 | 21.89 | 24.01 |
| Stereo 44.1 kHz | 10.93 | 8.11 | 670.30 | 8.22 | 103.27 | 28.96 | 22.73 | 25.79 |
| Stereo 48 kHz | 12.08 | 9.29 | 616.63 | 8.80 | 110.68 | 28.80 | 21.55 | 24.80 |
| Voice mono 48 kHz | 3.71 | 3.40 | 118.59 | 3.38 | 32.83 | 20.42 | 15.87 | 21.04 |

The encoder skips a scalefactor band when its peak falls below its first
nonzero magnitude threshold. Swag ADTS is byte-identical to the previous
build on all six inputs, including noise and voice. FDK's FileSamples result
has a 4.06 dB waveform SNR advantage at 220.43 kb/s versus Swag's 221.53 kb/s.

### FLAC PCM16

| Input | Swag before (ms) | Swag after (ms) | FFmpeg 9.1 level 0 (ms) | libFLAC 1.5.0 level 0 (ms) | Swag bytes before | Swag bytes after | FFmpeg bytes | libFLAC bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FileSamples stereo 44.1 kHz | 8.96 | 8.87 | 11.85 | 13.09 | 1,214,438 | 1,186,502 | 1,078,821 | 1,052,820 |
| Mono 48 kHz | 4.95 | 4.60 | 6.54 | 5.88 | 563,722 | 415,717 | 415,243 | 423,470 |
| Stereo 44.1 kHz | 8.60 | 8.70 | 11.90 | 12.98 | 1,083,638 | 798,436 | 783,952 | 806,276 |
| Stereo 48 kHz | 9.69 | 10.99 | 14.50 | 11.08 | 1,130,810 | 836,626 | 798,556 | 782,810 |
| Stereo noise 48 kHz | 8.45 | 8.05 | 10.79 | 12.85 | 1,921,810 | 1,921,810 | 1,932,749 | 1,924,547 |
| 5.1 at 48 kHz | 30.48 | 28.82 | 29.89 | 29.67 | 3,267,599 | 2,635,460 | 2,359,222 | 2,430,017 |

The writer chooses up to eight Rice partitions and retains an exact
single-partition fallback. All engines restore the original PCM.
FileSamples shrinks by 2.3%, mono and stereo by 26.0–26.3%, and 5.1 by
19.3%. Generated stereo 48 kHz takes 1.30 ms longer in this series and
produces 294,184 fewer bytes. The noise file retains the same size.

At level 5, FFmpeg encodes 5.1 in 46.25 ms and produces 2,682,537 bytes.
libFLAC takes 38.45 ms and produces 2,652,952 bytes. In the same series Swag
takes 27.57 ms and produces 2,635,460 bytes.

Native Release passes 329 audio tests. Release-safe passes 57 focused AAC,
MDCT and FLAC writer tests.
