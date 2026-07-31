/*
Pixel provides owned image buffers, image codecs and transforms, vector-style
drawing primitives, text layout, colors, brushes, paths, and an OpenGL renderer.

Most image operations mutate an [[Pixel.Image]] in place. Pixel coordinates use
an origin at the top-left; `x` grows to the right and `y` grows downward.
Dimensions and integer coordinates are expressed in pixels unless a declaration
says otherwise. Colors use straight (non-premultiplied) alpha.

## Create and save an image

```swag
using Pixel

var image = Image.create(320, 180, .RGBA8)
image.fill(Color.fromRgb(24, 32, 48))
try image.save("preview.png")
```

The filename extension selects the encoder when loading or saving. Operations
that can reject malformed data, fail to access a file, or fail in a backend use
Swag's normal `fail` mechanism.
*/

#import("core")
#import("ogl")
#import("truetype")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Pixel"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/pixel"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.pixel"
    cfg.genDoc.titleContent = "Pixel"
    cfg.genDoc.titleToc     = "Pixel documentation"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.css          = "css/style.css"
}
