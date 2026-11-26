# Generated audio decode fixtures on Linux

Swag Release at `96158d6b28` and native FFmpeg 7.1.5 open each input and materialize
its first ten seconds as PCM16. Each median includes 42 samples on CPU 0 of an AMD
EPYC 7763 with one worker per engine. The fixture generation and benchmark commands
are in the [audio decode workload](../../workloads/audiodecode/README.md).

[Raw stage times, fixture manifest and PCM digests](audio-decode-expanded-linux.json)

| Fixture | Swag (ms) | FFmpeg (ms) |
| --- | ---: | ---: |
| `aac-lc-32k-mono.aac` | 3.179 | 3.692 |
| `aac-lc-48k-stereo.aac` | 9.412 | 12.506 |
| `aac-lc-48k-5.1.aac` | 24.407 | 17.730 |
| `ac3-32k-mono.ac3` | 5.098 | 4.311 |
| `ac3-44k-stereo.ac3` | 9.745 | 9.296 |
| `ac3-48k-5.1.ac3` | 31.654 | 25.244 |
| `dts-48k-5.1.dts` | 49.699 | 35.510 |
| `eac3-48k-5.1.eac3` | 42.955 | 25.463 |
| `flac-44k-stereo-16.flac` | 6.803 | 11.521 |
| `flac-96k-stereo-24.flac` | 23.753 | 26.483 |
| `flac-48k-5.1-16.flac` | 23.347 | 36.900 |
| `mp3-8k-mono.mp3` | 1.183 | 1.522 |
| `mp3-24k-mono.mp3` | 2.992 | 2.940 |
| `mp3-48k-stereo.mp3` | 12.805 | 9.806 |
| `ogg-flac-48k-mono-16.oga` | 4.436 | 7.112 |
| `opus-voip-48k-mono.opus` | 29.584 | 14.165 |
| `opus-5ms-48k-stereo.opus` | 32.748 | 34.131 |
| `opus-20ms-48k-stereo.opus` | 32.064 | 31.418 |
| `vorbis-32k-mono.ogg` | 4.258 | 5.304 |
| `vorbis-48k-stereo.ogg` | 9.297 | 10.402 |
| `vorbis-48k-5.1.ogg` | 35.169 | 30.207 |
| `wav-48k-stereo-24.wav` | 1.763 | 1.518 |
