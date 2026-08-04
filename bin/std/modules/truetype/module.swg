/*
TrueType reads, measures, transforms, and rasterizes TrueType outline fonts
directly from memory.

A [[TrueType.Face]] owns a private copy of the font bytes and exposes one
reusable [[TrueType.GlyphSlot]]. Select a pixel size, load a character or glyph,
then consume its outline, metrics, or bitmap before loading the next glyph.
Coordinates and advances in a loaded slot use 26.6 fixed-point pixels: divide
them by 64 to obtain ordinary pixel values.

## Render a glyph

```swag
using Core, TrueType

let bytes = File.readAllBytes("Inter-Regular.ttf")
let face  = (try Face.load(bytes.toSlice()))!
defer face.destroy()

try face.setPixelSize(0, 32)
try face.loadChar('A', .Render)

let bitmap = &face.glyph.bitmap
// bitmap.buffer remains valid until this face loads or renders another glyph.
```

The module covers TrueType `glyf` outlines, Unicode character maps, legacy
kerning, grayscale rasterization, and single- or multi-channel signed-distance
fields.
*/

#import("core")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "TrueType"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/truetype"

    cfg.genDoc.kind       = .Api
    cfg.genDoc.outputName = "std.truetype"
    cfg.genDoc.icon       = "favicon.svg"
    cfg.genDoc.css        = "css/style.css"
}
