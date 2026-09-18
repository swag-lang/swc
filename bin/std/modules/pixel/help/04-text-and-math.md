# Text and mathematical layout

Text has three layers. [[Pixel.TypeFace]] owns font-file data, [[Pixel.Font]]
selects a size and rendering mode, and [[Pixel.Painter]] records shaped glyphs.
Fonts are created and owned by a [[Pixel.FontCache]]; every renderer has one.
Use [[Pixel.RichString]] when a paragraph needs style runs, wrapping, alignment,
or hit-testable links.

## Load a font

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
