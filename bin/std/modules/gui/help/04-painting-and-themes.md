# Painting and themes

Paint handlers receive a [[Gui.PaintEvent]] whose [[Gui.PaintContext]] connects
the current Pixel painter and OpenGL renderer. Drawing uses the same logical-pixel
coordinate system as the window.

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
