# Vector drawing

[[Pixel.Painter]] records a deferred command stream. A drawing scope always follows
the same shape: begin, issue commands, end, then submit the painter to a renderer.

```swag
using Pixel

var cpu: RenderCpu
let renderer: IRenderer = &cpu
var painter = Painter.create(renderer)
painter.begin()
painter.clear(Color.fromRgb(18, 20, 28))
painter.fillRoundRect(24, 24, 220, 96, 14, 14, Color.fromRgb(62, 132, 220))
painter.drawRect(24, 24, 220, 96, Color.fromRgb(230, 240, 255), 2)
painter.end()
```

`begin` clears previously recorded vertices and commands and restores the default
drawing state. [[Pixel.Painter.render]] submits the finished stream to the renderer
selected by [[Pixel.Painter.create]]. A default-initialized painter remains useful
for command inspection and goldens, but it cannot render or allocate a
[[Pixel.Layer]] until [[Pixel.Painter.setRenderer]] is called.

## Paths

Use [[Pixel.LinePath]] for one contour and [[Pixel.LinePathList]] for several
contours. A path starts at one point, accepts line, curve, Bézier, or arc segments,
and may be closed before filling.

```swag
var path: LinePath
path.start(80, 16)
path.lineTo(144, 128)
path.lineTo(16, 128)
path.close()

painter.begin()
painter.fillPath(&path, Color.fromRgb(245, 190, 48))
painter.drawPath(&path, Color.fromRgb(80, 54, 10), 2)
painter.end()
```

## Brushes and pens

[[Pixel.Brush]] describes fills: solid colors, textures, hatches, and linear,
radial, or sweep gradients. [[Pixel.Pen]] adds stroke width, joins, end caps, and
dash behavior around a brush.

## Blend modes

[[Pixel.Painter.setBlendingMode]] controls how later drawing combines with the
current target. Besides direct framebuffer operations, [[Pixel.BlendingMode]]
provides the standard separable modes such as `Multiply`, `Screen`, `Overlay`,
and `SoftLight`, plus the non-separable `Hue`, `Saturation`, `Color`, and
`Luminosity` modes. They blend straight source and backdrop colors, then apply
source-over coverage.

The artistic equations use destination alpha as backdrop coverage. Because a
new painter writes RGB but preserves alpha by default, initialize an opaque
surface with a full channel mask before selecting these modes. `clear` obeys
the current color mask.

```swag
painter.setColorMaskFull()
painter.clear(Color.fromRgb(24, 30, 42))
painter.setColorMaskColor()

painter.pushState()
painter.setBlendingMode(.Multiply)
painter.fillCircle(96, 72, 48, Color.fromArgb(180, Argb.RoyalBlue))
painter.setBlendingMode(.Screen)
painter.fillCircle(132, 72, 48, Color.fromArgb(180, Argb.Tomato))
painter.popState()
```

[[Pixel.RenderCpu]] supports every mode. Before using an artistic mode with an
unknown OpenGL context, query [[Pixel.RenderOgl.supportsAdvancedBlending]] after
renderer initialization. `Min` and `Max` remain raw component equations; use
`Darken` and `Lighten` for source-over artistic blending with partial alpha.

Use [[Pixel.Painter.pushState]] and [[Pixel.Painter.popState]] around local changes
to transforms, clipping, blending, interpolation, or quality. This keeps a
component's drawing code independent from its caller.

> TIP: Build reusable geometry once, then vary the brush, pen, transform, and
> clipping state when recording each frame.
