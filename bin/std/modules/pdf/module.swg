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
page.addText("Times, bold", 48, 108, 18, Color.fromArgb(Argb.Black), .TimesBold)
document.addPage(#move page)

var image = try document.pages[0].render({scale: 1.5})
try image.save("preview.png")
try document.save("document.pdf")
```

Loaded pages are inspected through `Document.pages`. Call
[[Pdf.Document.editPage]] to borrow a mutable page before replacing text,
colors, strokes, or item transforms; the borrow ends before pages are added or
removed.

For a large file that does not need to be edited as one complete document, open
[[Pdf.Reader]] instead. It keeps the encoded file mapped and decodes only the
page requested by [[Pdf.Reader.loadPage]]:

```swag
var reader = try Reader.open("large.pdf")
for index in reader.pageCount()
{
    var page  = try reader.loadPage(index)
    var image = try page.render({scale: 1.5})
    // Display or process image; page resources are released at the end of the iteration.
}
```

Text is written with the standard faces of [[Pdf.StandardFont]], which every
reader provides, so a written document embeds no font program. The same type
measures a run through its built-in metrics, without reading a font from the
system.

Loading and rendering reject malformed input and unsupported encodings through
Swag's normal `fail` mechanism. A streaming reader can therefore open a file
whose later page uses an unsupported encoding and reports that error only when
that page is requested. Embedded actions, scripts, forms, and external references
are never executed.

## What the reader handles

Nothing below is delegated to a platform service or a third-party library; the
only decoder that comes from outside the module is Core's Flate and Pixel's JPEG.

- Classic indirect objects, compressed object streams, cross-reference streams,
  page trees with inherited attributes, and page rotation.
- The Flate, LZW, ASCII hexadecimal, ASCII85, and run-length filters, with the
  TIFF and PNG predictors at every supported bit depth.
- The text, vector, color space, and inline image operators, including the
  complete text state and stroked-path cap, join, miter, and dash geometry.
- Simple and composite fonts: `/Widths` and `/W` metrics, the standard, WinAnsi
  and MacRoman encodings, `/Differences`, `/ToUnicode` CMaps, and embedded
  TrueType or OpenType programs.
- Images from one to sixteen bits per component, in the device, calibrated,
  ICC-based, indexed, Lab, separation, and DeviceN color spaces, with decode
  arrays, stencil masks, soft masks, and color key masks.

Encryption, interactive forms, Type1 and CFF font programs, shading patterns,
and the CCITT, JBIG2 and JPEG 2000 image codecs are out of scope; a document
that needs one of them reports it rather than painting something else.
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
