# Swag Scope fixture sources and licences

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

`title.png` and `qrcode.png` are unmodified copies of the two images of the InDesign layout sample
published for the iOSDC Japan 2025 pamphlet article. They give the explorer and reload tests real
images produced outside this repository.

- Source: `https://github.com/kotetuco/iOSDC-Japan-2025-Pamphlet-Sample/tree/main/AffinityPublisher`
  and `https://github.com/kotetuco/iOSDC-Japan-2025-Pamphlet-Sample/tree/main/images`
- Retrieved: 2026-09-03
- SHA-256: `2f3d5a98266f217c56e9d2c279274f5367e2f8d50201f1bd48a6a1e072cf408a` (title) and
  `a4e4ee6c8b36785bfcbcaf70c307ca8a7ffd0bb14eba0458623367f908e263a0` (QR graphic).
- License: MIT. The upstream repository carries the complete license notice.

`rv40-legacy-clock.mkv` is an unmodified copy of the synthetic 96x64, nine-frame RV40 fixture
in `bin/std/modules/video/src/tests/datas`. Its provenance, encoder settings, and timestamp
mutation are documented in that directory's `THIRDPARTY.md`. It contains only generated picture
samples and no audio. It verifies RV40 opening and seeking through Swag Scope's planar viewer.

- SHA-256: `3f0ae80c6a2a54412c938a7105ffc1c6a5df2eb580f90454d7ec85d43f31f01a`
- License: same as this repository.

`viewer.console.exe` is a Windows console program built by this repository's compiler from a module
whose `#main` is empty (`swc build -bc release`). The binary viewer's report page is photographed
on it: a PE32+ image with its sections and its imports, small enough to keep in the tree.

- SHA-256: `3bde0ddc065ea3b2497607f7d615ea420dad2e96b3fcd18d8a02d6cc1d35a0c9`
- License: same as this repository.
