# Getting started

Pixel covers two related jobs: manipulating owned images on the CPU and recording
two-dimensional drawing commands for a renderer. Start with the smallest layer
that solves the problem.

| Goal | Start with |
|---|---|
| Load, transform, or encode pixels | [[Pixel.Image]] |
| Express a color | [[Pixel.Color]] and [[Pixel.Argb]] |
| Draw shapes, paths, textures, or text | [[Pixel.Painter]] |
| Build reusable vector geometry | [[Pixel.LinePath]] and [[Pixel.LinePathList]] |
| Render recorded commands with OpenGL | [[Pixel.RenderOgl]] |
| Load and lay out fonts | [[Pixel.TypeFace]], [[Pixel.Font]], and [[Pixel.RichString]] |

## A first image

An [[Pixel.Image]] owns a tightly packed, row-major pixel buffer. The pixel format
determines how many bytes belong to each pixel.

```swag
using Pixel

var image = Image.create(320, 180, .RGBA8)
image.fill(Color.fromRgb(24, 32, 48))
try image.save("preview.png")
```

Image operations that change dimensions or encoding update the same value. Copying
an image copies its owned bytes; it does not create a shared view.

## Coordinate and color conventions

Pixel coordinates start at the top-left. `x` grows to the right and `y` grows
downward. Unless a declaration says otherwise, dimensions, positions, stroke widths,
and font sizes are expressed in pixels.

[[Pixel.Color]] stores straight alpha. A transparent color therefore retains its
RGB components; blending and render targets decide how those components contribute
to the destination.

> NOTE: Operations that can reject input, access files, allocate backend resources,
> or compile shaders use Swag's normal `fail` mechanism. Propagate those failures
> with `try`, or handle them at the boundary of your application.
