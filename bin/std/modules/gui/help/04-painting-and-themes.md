# Painting and themes

Paint handlers receive a [[Gui.PaintEvent]] whose [[Gui.PaintContext]] connects
the current Pixel painter and renderer. Drawing uses the same logical-pixel
coordinate system as the window. [[Gui.Application.renderer]] is a
[[Pixel.PainterRenderer]], so the same paint path can target OpenGL in the native
application and [[Pixel.RenderCpu]] in deterministic tests.

The theme is separated into:

| Part | Role |
|---|---|
| [[Gui.ThemeColors]] | Semantic colors for controls and states |
| [[Gui.ThemeMetrics]] | Sizes, spacing, borders, and timing |
| [[Gui.ThemeImageRects]] | Regions in the theme image atlas |
| [[Gui.ThemeStyle]] | A control's resolved font, colors, and resources |

Read theme data through the current window so custom controls respect local style
overrides:

```swag
let colors  = wnd.getThemeColors()
let metrics = wnd.getThemeMetrics()
let font    = wnd.getFont()
```

Paint only inside the invalidated region when possible. Call
[[Gui.Wnd.invalidate]] after a visual state change, and
[[Gui.Wnd.invalidateRect]] when only a bounded region changed.
[[Gui.Application.notifyThemeChanged]] recomputes styles and invalidates the
interface after editing shared theme data.

## Headless paint tests

[[Gui.Testing.HeadlessHost]] builds a deterministic application and widget tree
without creating an OS window. [[Gui.Testing.HeadlessHost.render]] runs the normal
surface paint pipeline through Pixel's software renderer and returns owned pixels.

```swag
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 80)
    discard PushButton.create(&host.root, "Continue", {20, 20, 120, 32})

    let image = host.render()
    Pixel.Testing.assertImageGolden(&image, "continue-button")
}
```

Use structural and event assertions for behavior, command goldens for emitted
paint operations, and PNG goldens for the final composition. A small OpenGL
integration suite remains necessary for context, shader compiler, and driver
coverage.
