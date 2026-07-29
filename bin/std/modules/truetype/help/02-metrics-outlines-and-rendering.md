# Metrics, outlines, and rendering

TrueType exposes font data in three unit systems:

| Data | Unit |
|---|---|
| Face metadata such as [[TrueType.Face.ascender]] | Font design units |
| [[TrueType.SizeMetrics.xScale]] and `yScale` | 16.16 fixed point |
| Loaded glyph coordinates, metrics, and advances | 26.6 fixed-point pixels |

Divide a 26.6 value by `64.0` to obtain pixels. An outline uses a y-up coordinate
system; bitmap placement uses [[TrueType.GlyphSlot.bitmapLeft]] and
[[TrueType.GlyphSlot.bitmapTop]] relative to the baseline.

## Choose a rendering path

| Goal | Workflow |
|---|---|
| Inspect or convert vector geometry | Load, then use [[TrueType.Outline.decompose]] |
| Draw crisp text at one size | Load, optionally hint, then call [[TrueType.Face.renderGlyph]] |
| Build a single-channel distance atlas | Load, then call [[TrueType.Face.renderGlyphSdf]] |
| Preserve sharp corners in a distance atlas | Load, then call [[TrueType.Face.renderGlyphMsdf]] |

```swag
try face.setPixelSize(0, 28)
try face.loadChar('S')
try face.hintVertical()
try face.renderGlyph()

let bitmap = &face.glyph.bitmap
```

[[TrueType.Face.hintVertical]], [[TrueType.Outline.translate]],
[[TrueType.Outline.transform]], [[TrueType.Outline.embolden]], and
[[TrueType.GlyphSlot.oblique]] mutate the current outline. Reload the glyph to
recover its original scaled shape.

Distance-field rendering intentionally follows a separate path. Do not apply
pixel-grid hinting before generating an SDF or MSDF atlas. The `spread` argument
controls the transition range and is clamped to 1 through 64 pixels.
