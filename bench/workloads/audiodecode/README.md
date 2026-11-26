# Audio decoding against native FFmpeg

This Linux workload measures opening an audio file and materializing up to its first
ten seconds as interleaved PCM16. Swag uses `Audio.SoundFile.decodePcm16`. The native
reference uses libavformat, libavcodec and libswresample. Both paths allocate their output
inside the timed region and write timing logs and optional PCM outside it.

Generate the fixtures with FFmpeg, including its LAME, Opus and Vorbis encoders. The
22 cases cover mono, stereo and 5.1, sample rates from 8 to 96 kHz, 16- and 24-bit FLAC,
E-AC-3, DTS, Ogg FLAC, short CELT frames and voice-mode Opus. The inputs are 12 seconds
of synthesized PCM with varying frequency, transients and energy across channels.
`manifest.json` records the encoder options, FFmpeg version, file sizes and SHA-256 hashes.

```sh
workload=bench/workloads/audiodecode
fixtures=/tmp/swag-audio-fixtures
python3 "$workload/generate.py" "$fixtures"

taskset -c 0 python3 "$workload/compare.py" \
    --compiler /absolute/build/release/swc \
    --output /tmp/swag-audio-results "$fixtures"/*.{aac,ac3,dts,eac3,flac,mp3,oga,ogg,opus,wav}
```

Use Python 3.11 or newer and a built Swag compiler. The runner builds the FFmpeg reference
with a C compiler, pkg-config and the FFmpeg development libraries. `--reference` accepts
a prebuilt `ffmpeg_native` from this workload. The output directory must be new and
outside the source trees. Pass FileSamples files as inputs to repeat the benchmark with
the original corpus.

The runner interleaves engines across rounds. Each process warms up once and contributes
seven measured runs. `--threads` sets both Swag's worker budget and FFmpeg's decoder
thread count. Use CPU affinity and an otherwise idle machine for comparisons. The median
total includes both open and decode. `results.json` also records each raw measurement,
the output dimensions, the PCM digests and the active CPU affinity.

With `--baseline-bin`, the same compiler builds a second Swag executable from a preserved
`bin` tree and the runner compares the two Swag PCM captures. Use `--max-pcm-delta 0` for
bit-exact changes, or specify a measured tolerance in PCM16 units. FFmpeg's PCM capture
is available for inspection. Differences between lossy decoders can also reflect encoder
delay, channel mapping and quantization.
