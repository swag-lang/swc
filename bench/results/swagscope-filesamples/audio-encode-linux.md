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
