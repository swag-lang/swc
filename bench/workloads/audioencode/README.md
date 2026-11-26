# Audio encoding against native FFmpeg

This Linux workload compares AAC-LC, FLAC PCM16 and WAV PCM16. Both engines receive the
same interleaved PCM16 from memory and write a complete file. Each driver times opening,
submitting samples, and finalizing the output. Every process performs one warmup, and the
runner rotates the order of the engines between rounds. The timing excludes preparing the
input and decoding the results for quality checks.

Use Python 3.11 or newer, a built Swag compiler, FFmpeg and a C compiler with pkg-config
and development packages for libavformat, libavcodec and libavutil. `--reference` accepts a
prebuilt `ffmpeg_native` from this workload. Pin the runner to one otherwise idle CPU.
The output directory must be new and outside the source trees.

```sh
fixtures=/tmp/swag-audio-fixtures
python3 bench/workloads/audiodecode/generate.py "$fixtures"
ffmpeg -nostdin -v error -i "$fixtures/wav-48k-stereo-24.wav" -map 0:a:0 \
    -t 10 -c:a pcm_s16le -f s16le /tmp/swag-encode-stereo48.pcm

taskset -c 0 python3 bench/workloads/audioencode/compare.py \
    --codec aac --rate 48000 --channels 2 --compiler /absolute/build/release/swc \
    --output /tmp/swag-aac-results /tmp/swag-encode-stereo48.pcm
```

For AAC, both engines write ADTS. The default reference is FFmpeg AAC-LC with two-loop
quantization. The runner calibrates the reference bitrate against the Swag AAC payload,
excluding ADTS headers, and records the actual rates. `--reference-setting` can select a
specific bitrate in bits per second. `--bandwidth voice` exercises the Swag voice profile
and sets the reference cutoff to the same nominal band. The quality check removes each
encoder's declared priming and measures PCM SNR and error over the submitted frames.

For FLAC, `--reference-setting` selects the FFmpeg compression level and defaults to 5.
FLAC and WAV must decode to the submitted PCM byte for byte. The runner records each
encoded file size and SHA-256, and the raw times and PCM checks appear in `results.json`.
Choose `--baseline-bin` to compare a preserved Swag standard-module source tree with the
same compiler. `--exact-baseline` requires the two Swag outputs to be byte-identical.
