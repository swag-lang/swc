# Text and mathematical layout

Text has three layers. [[Pixel.TypeFace]] owns font-file data, [[Pixel.Font]]
selects a size and rendering mode, and [[Pixel.Painter]] records shaped glyphs.
Fonts are created and owned by a [[Pixel.FontCache]]; every renderer has one.
Use [[Pixel.RichString]] when a paragraph needs style runs, wrapping, alignment,
or hit-testable links.

## Load a font

Use [[Pixel.TypeFace.loadAt]] to select a zero-based face from a `.ttc` or `.otc` collection,
or [[Pixel.TypeFace.createAt]] when the collection bytes are already in memory. The cache
distinguishes the supplied name and face index; the returned typeface remains owned by Pixel.

```swag
using Pixel

var cpu: RenderCpu
let renderer: IRenderer = &cpu
var painter = Painter.create(renderer)
let font = try renderer.fontCache().createFont("Inter-Regular.ttf", 20)

painter.begin()
painter.drawString(24, 32, "Hello, Pixel", font, Color.fromRgb(245, 245, 245))
painter.end()
```

[[Pixel.FontRenderMode]] `Auto` chooses between bitmap and multi-channel
signed-distance-field rendering according to the effective on-screen size. Select a
specific mode only when stable atlas behavior or a particular rendering technique
matters more than automatic quality.

## Inspect a font catalog

[[Pixel.FontCatalog]] builds an owned metadata snapshot from application-supplied font files.
It reads every face of a collection without loading glyphs, groups family names without case,
and selects regular, bold, italic, light, or semibold by slant, width, and weight. File order does
not affect selection. A rejected file leaves the existing catalog unchanged.
Use [[Pixel.FontCatalog.addDirectory]] to search a directory tree; it skips malformed font
files independently and reports directory enumeration failures.

```swag
var catalog: Pixel.FontCatalog
discard try catalog.addFile("fonts/Example.ttc")
if let selected = catalog.findFace("Example", .SemiBold)
{
    let typeFace = try selected.load()
}
```

The catalog owns names and paths, but not file contents. A selected [[Pixel.FontFileFace]] is
borrowed until the next catalog mutation; loading it uses the exact file/index pair and Pixel's
usual typeface cache. Selection does not synthesize bold or italic. The catalog groups by
typographic family names when available, bringing light and semibold variants into the same
family. If a query matches no typographic family, legacy family names are searched instead;
asking for a separately named light family still selects that family's faces.

On Linux, [[Pixel.FontCatalog.loadSystem]] scans conventional system and user font directories
into a fresh snapshot. It includes the XDG user data directory and legacy `$HOME/.fonts`,
ignores unavailable directories and invalid fonts, and does not consult Fontconfig aliases.

## Rich text

[[Pixel.RichString.set]] takes text written in Pixel's lightweight inline markup.
[[Pixel.RichString.compute]] splits it into styled chunks after the text changes,
and [[Pixel.Painter.drawRichString]] lays the chunks out and records the result.

Keep the [[Pixel.FontFamily]] and formatting inputs alive while computing and
drawing the text. The rich string retains its source text and derived layout state,
so it can be reused until one of those inputs changes.

## Mathematical expressions

Parse notation with [[Pixel.MathExpression.parse]], measure it with
[[Pixel.MathExpression.measure]], and draw it through [[Pixel.Painter.drawMath]].
For one-off trusted strings, [[Pixel.Painter.drawMathLatex]] combines parsing,
layout, and drawing.

> NOTE: Mathematical layout supports a practical TeX-like subset, not a complete
> TeX engine. Parse failures identify unsupported or malformed input through the
> normal `fail` path.
