# sFileScope fixture sources and licences

`glint-aac-mjpeg.mp4` is the 10-frame synthetic MP4 fixture documented in std/video's test
corpus. Its picture is generated colour blocks and its sound is generated stereo sine waves.

- SHA-256: `3414695932df3598a24212796c46183a3cce46d7c81dba7b60eef6886047ab63`
- License: same as this repository; the glint AAC encoder used for the generated sound is MIT
  licensed and its notice is reproduced in std/audio.

`ffmpeg-h264-baseline.mp4` is one of the nine ffmpeg encodings of the synthetic clip documented in
std/video's test corpus: 64x48, 20 frames, Constrained Baseline. The video viewer needs an H.264
stream because that is the one codec whose decoder hands its pictures over as planes, and the
viewer takes a different path for those.

- SHA-256: `bd42f819cf870879a1e7152adb804feb0329969d094ef756a57ea9651081b6e2`
- License: same as this repository; the picture is generated, not a third-party recording.

`ffmpeg-h264-two-aac.mkv` is the Matroska fixture documented in std/video's test corpus. It
stream-copies the synthetic H.264 clip above and maps the generated AAC-LC track of
`glint-aac-mjpeg.mp4` twice, with the first copy marked as default. The video viewer uses it to
exercise the visible audio-track selector and its transport handoff.

- SHA-256: `36c7ad0fdee8156478589265ad51a3025d8c7822904fd504c82e7dd50bfd2c5d`
- License: same as this repository and its two generated source fixtures.

`viewer.pdf` is an unmodified copy of Apache PDFBox's
`examples/src/test/resources/org/apache/pdfbox/examples/pdmodel/document.pdf` at commit
`d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d`. It gives the PDF viewer a file produced outside the
Swag PDF writer and covers a PDF 1.4 classic cross-reference table with a Flate content stream.

- SHA-256: `a31f3b5fc79e6ae2703f9d2817af088f29aef4937e370b173512d820a9972c35`
- License: Apache License 2.0. The complete upstream provenance and license notice are reproduced
  in `bin/std/modules/gui/src/tests/datas/THIRDPARTY.md`.
