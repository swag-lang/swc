# Rendering recorded commands

[[Pixel.Painter]] is backend-facing data: it records commands and vertices but does
not own a window or present a frame. [[Pixel.RenderOgl]] consumes that recording in
an active [[Pixel.RenderingContext]].

## Frame lifecycle

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

## Render targets and layers

Use [[Pixel.RenderTarget]] for an off-screen pass. [[Pixel.Layer]] packages a
temporary target and the information needed to composite it back, which is useful
for opacity, blur, and effects spanning several draw calls.

Textures created by the renderer are represented by [[Pixel.Texture]]. Their
handles belong to that renderer; release or recycle them through the corresponding
renderer workflow rather than treating the handle as portable storage.

## Headless mode

[[Pixel.RenderOgl.setupHeadless]] enables deterministic CPU-backed behavior for
tests and environments without a presentation surface. It deliberately does not
exercise a real GPU driver, window system, or swap chain.

> WARNING: A painter must be ended before it is submitted. Do not mutate its command
> or vertex buffers while a renderer is consuming them.
