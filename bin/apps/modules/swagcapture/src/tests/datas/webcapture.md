# Browser recording fixture

`webcapture.webm` is an owned, generated 320 by 180 VP8/Opus clip for
`tools/capture-web.py`. Its moving yellow mark and time reading distinguish consecutive
pictures; the cyan corner identifies the web video area. Its audio is a 440 Hz sine wave.
The clip loops in a real browser served over local HTTP during the native integration.
It contains no third-party footage or personal content.

The fixture contains 90 pictures at 30 frames per second and exactly three seconds of stereo
48 kHz audio. The bar moves by 70 pixels per second and the label names each frame. The
sine amplitude is 0.18; three seconds contains exactly 1320 cycles, making its loop continuous.
It was generated with Pillow/NumPy and PyAV's `libvpx` (YUV420P, 256 kbit/s, realtime deadline,
CPU-used 4, CRF 10) and `libopus` (64 kbit/s) encoders, each with one codec thread.
Keeping this small clip here avoids depending on source-recording device availability or
background canvas throttling; the integration itself records real desktop pixels and native
system output.
