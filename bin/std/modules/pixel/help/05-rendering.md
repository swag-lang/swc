# Rendering recorded commands

Pixel separates four roles:

| Role | API |
|---|---|
| Own backend state and resources | [[Pixel.RenderCpu]], [[Pixel.RenderOgl]], or another implementation |
| Expose backend-independent operations | [[Pixel.IRenderer]] |
| Describe one drawable and its dimensions | [[Pixel.RenderContext]] |
| Record one deferred command stream | [[Pixel.Painter]] |

There is no central renderer registry or closed backend enum. Any type that
implements [[Pixel.IRenderer]] is available immediately. Keep the concrete value
alive, borrow it as the interface, and create each painter with that interface:

```swag
var cpu: RenderCpu
let renderer: IRenderer = &cpu
var painter = Painter.create(renderer)
```

The interface, painter, contexts, textures, and render targets do not own the
concrete renderer. They must not outlive it. Resources also stay tied to the
renderer that created them and cannot be moved to another backend.

## CPU frame lifecycle

[[Pixel.RenderCpu]] needs no native window, display server, GPU, or driver. Its
output is deterministic and [[Pixel.RenderCpu.surfaceImage]] returns an owned
copy of the current surface.

```swag
var cpu: RenderCpu
let renderer: IRenderer = &cpu
var painter = Painter.create(renderer)
var context = try renderer.createContext(null, 320, 180)
defer renderer.deleteContext(&context)

renderer.init()
renderer.begin(context)

painter.begin()
painter.clear(Color.fromRgb(20, 22, 30))
painter.fillRect({24, 24, 120, 48}, Color.fromRgb(60, 140, 240))
painter.end()
painter.render()

renderer.end()
let image = cpu.surfaceImage()
```

The concrete [[Pixel.RenderCpu.begin]] overload taking width and height is a
convenience for CPU-only code. The interface/context form above is preferable
when the caller can work with any renderer.

## OpenGL frame lifecycle

[[Pixel.RenderOgl]] uses the same interface. Pass the platform window handle to
[[Pixel.IRenderer.createContext]], make the first context current, then initialize
renderer-owned OpenGL resources. A context created with `shared` uses the same
renderer resources as that earlier context.

```swag
var ogl: RenderOgl
let renderer: IRenderer = &ogl
var painter = Painter.create(renderer)
var context = try renderer.createContext(
    cast(#null const *void) window.nativeHandle, width, height)
defer renderer.deleteContext(&context)

renderer.setCurrentContext(context)
renderer.init()

renderer.begin(context)
painter.begin()
// Record shapes, textures, and text here.
painter.end()
painter.render()
renderer.end()
```

Update [[Pixel.RenderContext.width]] and [[Pixel.RenderContext.height]] after a
drawable resize. Keep OpenGL calls on the thread required by the platform
integration.

## Render targets and layers

Use [[Pixel.RenderTarget]] for a manually managed off-screen pass.
[[Pixel.Layer]] packages temporary targets, supersampling, resolution, blur, and
composition. A layer obtains its renderer from the painter, so its call site does
not repeat or risk contradicting backend selection:

```swag
var layer: Layer
layer.begin(&painter, {width: 320, height: 180})
// Record layer content with painter.
layer.end()
layer.draw({dstRect: {0, 0, 320, 180}})
```

Textures created by [[Pixel.IRenderer.addImage]] and targets created by
[[Pixel.IRenderer.createRenderTarget]] belong to that renderer. Release them
through the same interface. CPU and OpenGL handles are not interchangeable.

## Pixel goldens

[[Pixel.Testing.assertImageGolden]] stores a rendered PNG beside the calling
test. The default comparison is exact; pass
[[Pixel.Testing.ImageGoldenOptions]] only when a workflow has a justified bounded
tolerance.

```swag
let image = cpu.surfaceImage()
Testing.assertImageGolden(&image, "toolbar.enabled")
```

The first run creates `goldens/toolbar.enabled.png` and passes so the new file can
be reviewed. A mismatch fails and writes `toolbar.enabled.actual.png`. After
reviewing both images, `tools\accept-test-goldens.bat` promotes pending snapshots.

[[Pixel.RenderCpu]] interprets built-in shapes, brushes, textures, clipping,
blending, bitmap text, render targets, blur, and supersampling. Custom GLSL
shaders and advanced MSDF outline, glow, softness, and bevel effects remain
OpenGL-only. Keep a small OpenGL integration suite for shader compiler, driver,
context, and presentation coverage.

> WARNING: End a painter before calling [[Pixel.Painter.render]]. Do not mutate
> its command or vertex buffers while a renderer is consuming them.
