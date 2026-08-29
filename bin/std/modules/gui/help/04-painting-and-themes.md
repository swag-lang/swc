# Painting and themes

Paint handlers receive a [[Gui.PaintEvent]] whose [[Gui.PaintContext]] connects
the current Pixel painter and renderer. Drawing uses the same logical-pixel
coordinate system as the window. [[Gui.Application.renderer]] is a
[[Pixel.IRenderer]], so the same paint path can target OpenGL in a native
application, [[Pixel.RenderCpu]] in deterministic tests, or another renderer
selected through [[Gui.Application.setRenderer]].

The theme is separated into:

| Part | Role |
|---|---|
| [[Gui.ThemePalette]] | The thirty-odd decisions a theme makes |
| [[Gui.ThemeColors]] | Semantic colors for controls and states, all derived from the palette |
| [[Gui.ThemeMetrics]] | Sizes, spacing, borders, and timing |
| [[Gui.ThemeImageRects]] | Regions and painted corner radii in the theme image atlas |
| [[Gui.ThemeStyle]] | A control's resolved font, colors, and resources |

A palette is where a theme is written: grounds, rules, ink, one accent and the ink
drawn on it, status hues, a veil, and the chrome of a window.
[[Gui.ThemeColors.apply]] turns those into a value for every painted part, which is
what makes a theme complete by construction — it cannot answer for a button and
forget the field beside it. The three shipped palettes ([[Gui.Theme.setDark]],
[[Gui.Theme.setLight]], and [[Gui.Theme.setSwagDark]]) are
token lists and nothing else, and each also restores the geometry it implies.

The Swag palette uses one small four-logical-pixel corner for bounded interface
parts: fields, actions, rectangular tool cells, hover and selection grounds, and
standalone raised panels. Joined bars, rails, separators, and document grounds
remain square; the outer surface uses its larger
[[Gui.ThemeMetrics.surfaceWnd_CornerRadius]]. Set a window's
[[Gui.Wnd.backgroundStyle]] to [[Gui.BackgroundStyle.Panel]] when it is a raised
panel rather than joined application chrome, so its ground follows that geometry
in every palette. [[Gui.BackgroundStyle.Application]], [[Gui.BackgroundStyle.View]],
and [[Gui.BackgroundStyle.Window]] expose the main plain grounds. Use
[[Gui.BackgroundStyle.CommandBar]], [[Gui.BackgroundStyle.InformationBar]], and
[[Gui.BackgroundStyle.ToolBar]] for application-wide commands, contextual information,
and tools specific to the current content; each role remains distinct in every shipped palette.

```swag
var palette = Gui.ThemeColors.swagDarkPalette()
palette.signature = Gui.ThemeTone.from(0xFF00A0FF, 0xFF000000)
app.theme.setPalette(palette)
app.notifyThemeChanged()
```

`bin/examples/modules/gui10` is the theme inspector: it lists every color of every
palette by reflection, flags any value one palette answers for and another does not,
and shows every widget in every state.

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
