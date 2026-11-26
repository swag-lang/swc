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

Use `--aac-reference fdk` to compare native FDK AAC-LC with afterburner
enabled. This mode uses the `fdk-aac` development package through pkg-config
or a prebuilt `fdk_native` supplied with `--reference`. FFmpeg still decodes
the outputs for the untimed PCM comparison.

Pass `--aac-adaptive` to use short-window selection for the candidate AAC
encoder. The baseline uses its regular encoder. Generate the mono PCM16
attack inputs with `python3 aac_transients.py generate /tmp/aac-attacks`
and submit them at 48 kHz with one channel. For isolated attacks, run
`python3 aac_transients.py analyze /tmp/aac-isolated-results`. For mixed
attacks, also give `--background` the output directory from encoding the
background at the same encoder settings.

For FLAC, `--reference-setting` selects the FFmpeg compression level and defaults to 5.
`--libflac 0` adds the installed libFLAC streaming reference at level 0. Its input is
widened to the 32-bit API representation before the timer starts.
FLAC and WAV must decode to the submitted PCM byte for byte. The runner records each
encoded file size and SHA-256, and the raw times and PCM checks appear in `results.json`.
Choose `--baseline-bin` to compare a preserved Swag standard-module source tree with the
same compiler. `--exact-baseline` requires the two Swag outputs to be byte-identical.
