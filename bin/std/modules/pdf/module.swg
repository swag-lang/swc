/*
Pdf reads, edits, renders, and writes Portable Document Format documents without
calling a platform PDF service or a third-party library.

The public model uses Pixel's top-left coordinate system. Loading converts PDF
page coordinates into that space, and saving converts them back. A document owns
its pages, page items, decoded images, and embedded font bytes. Returned images
are independent Pixel buffers owned by the caller.

## Create, render, and save a document

```swag
using Pdf, Pixel

var document = Document.create()
var page     = Page.create(595, 842)
page.addText("Hello PDF", 48, 72, 24, Color.fromArgb(Argb.Black))
document.addPage(#move page)

var image = try document.pages[0].render({scale: 1.5})
try image.save("preview.png")
try document.save("document.pdf")
```

Loaded pages are inspected through `Document.pages`. Call
[[Pdf.Document.editPage]] to borrow a mutable page before replacing text,
colors, strokes, or item transforms; the borrow ends before pages are added or
removed.

Loading and rendering reject malformed input and unsupported encodings through
Swag's normal `fail` mechanism. Embedded actions, scripts, forms, and external
references are never executed.

The reader handles classic indirect objects, compressed object streams, page
trees, Flate, ASCII hexadecimal, ASCII85, run-length streams, embedded TrueType
fonts, JPEG and 8-bit grayscale/RGB/CMYK images, and the common text and vector
painting operators. Encryption, forms, Type1/CFF fonts, color profiles, and
specialized image codecs are outside the initial implementation and fail when
their data is required for rendering.
*/

#import("core")
#import("pixel")

#run
{
    with let cfg = @compiler.getBuildCfg()!
    {
        .moduleVersion   = #swcversion
        .moduleRevision  = #swcrevision
        .moduleBuildNum  = #swcbuildnum
        .moduleNamespace = "Pdf"
        .backendKind     = .SharedLibrary
        .repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/pdf"

        .genDoc.kind         = .Api
        .genDoc.outputName   = "std.pdf"
        .genDoc.titleContent = "Pdf"
        .genDoc.titleToc     = "Pdf documentation"
        .genDoc.icon         = "favicon.svg"
        .genDoc.css          = "css/style.css"
    }
}
