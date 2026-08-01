# Rendering recorded commands

[[Pixel.Painter]] is backend-facing data: it records commands and vertices but does
not own a window or present a frame. [[Pixel.RenderOgl]] consumes that recording in
an active [[Pixel.RenderingContext]]. [[Pixel.RenderCpu]] consumes the same recording
into owned image buffers without a graphics context.

## OpenGL frame lifecycle

```swag
renderer.begin(renderingContext)

painter.begin()
painter.clear(Color.fromRgb(20, 22, 30))
// Record shapes, textures, and text here.
painter.end()

renderer.draw(&painter)
renderer.end()
```

The renderer's `begin` makes the context current and resets its frame transform.
Its `end` finishes and presents the frame. Keep each renderer on the thread and
context expected by the platform OpenGL integration.

## Software frame lifecycle

The CPU renderer takes dimensions instead of a native context. Rendering is
synchronous, and [[Pixel.RenderCpu.surfaceImage]] returns an owned copy of the
frame pixels.

```swag
var renderer: RenderCpu
renderer.begin(320, 180)

painter.begin()
painter.clear(Color.fromRgb(20, 22, 30))
painter.fillRect({24, 24, 120, 48}, Color.fromRgb(60, 140, 240))
painter.end()

renderer.draw(&painter)
renderer.end()
let image = renderer.surfaceImage()
```

The software path is deterministic and independent of a display server, GPU,
driver, and swap chain. It is therefore suitable for unit tests, pixel goldens,
server-side image generation, and reproducing paint failures in continuous
integration.

## Pixel goldens

[[Pixel.Testing.assertImageGolden]] stores a rendered reference as PNG beside the
calling test. The default comparison is exact; pass
[[Pixel.Testing.ImageGoldenOptions]] only when a workflow has a justified bounded
tolerance.

```swag
let image = renderer.surfaceImage()
Testing.assertImageGolden(&image, "toolbar.enabled")
```

The first run creates `goldens/toolbar.enabled.png` and passes so the new file can
be reviewed. A mismatch fails and writes `toolbar.enabled.actual.png`. After
reviewing both images, `tools\goldens.bat accept` promotes every pending text or
PNG snapshot.

## Render targets and layers

Use [[Pixel.RenderTarget]] for an off-screen pass. [[Pixel.Layer]] packages a
temporary target and the information needed to composite it back, which is useful
for opacity, blur, and effects spanning several draw calls.

Textures created by either renderer are represented by [[Pixel.Texture]]. Their
handles belong to that renderer; release or recycle them through the corresponding
renderer workflow rather than treating the handle as portable storage. CPU and
OpenGL handles are not interchangeable.

## Headless mode

[[Pixel.RenderOgl.setupHeadless]] enables deterministic CPU-backed behavior for
existing code whose renderer type is [[Pixel.RenderOgl]], including GUI tests and
[[Pixel.Layer]]. It delegates resources and painter submission to [[Pixel.RenderCpu]]
and needs neither `init` nor a graphics context.

Use [[Pixel.RenderCpu]] directly in new context-free code. Use the compatibility
entry point when an existing API stores a concrete [[Pixel.RenderOgl]]. Both paths
interpret Pixel's built-in shapes, brushes, textures, clipping, blending, bitmap
text, render targets, blur, and supersampling resolve. A custom GLSL shader has no
portable CPU implementation and is rejected by the software renderer. Advanced
MSDF outline, glow, softness, and bevel effects also remain OpenGL-only; plain
distance-field face coverage is available in software.

CPU pixel tests verify Pixel's recording, geometry, state, resource, and
compositing logic. Keep a smaller OpenGL integration suite as well: only it can
detect shader compiler, driver, context, and presentation regressions.

> WARNING: A painter must be ended before it is submitted. Do not mutate its command
> or vertex buffers while a renderer is consuming them.
