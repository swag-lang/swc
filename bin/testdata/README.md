# Shared module test data

Fixtures used by multiple modules live here. Resolve them relative to the checkout through the
module's test source location so the working directory does not affect lookup.

| Directory | Contents | Consumers |
| --- | --- | --- |
| `audio/` | Encoded audio samples and PCM reference decodes | Audio, Video, Swag Scope |
| `font/` | Segoe UI and Noto Emoji test faces | GUI, Pixel, Swag Scope, TrueType |
| `image/` | APNG and WebP animations and a multi-image icon | GUI, Pixel |
| `pdf/` | Outline, image, object stream, rotation, and reference PDFs | GUI, Swag Scope |
| `video/` | Shared AVI, ISO-BMFF, Matroska, and YUV4MPEG2 samples | Video, Swag Scope |
| [`filesamples/`](filesamples/README.md) | External sample catalogue, manifest, and restore script | Any module |

Small shared inputs are stored with the sources. The FileSamples restore script fills its local
payload tree from the versioned manifest. Module-specific inputs and expected outputs belong in
the owning module's test directories.
