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
| [[Gui.ThemePalette]] | The twenty-odd decisions a theme makes |
| [[Gui.ThemeColors]] | Semantic colors for controls and states, all derived from the palette |
| [[Gui.ThemeMetrics]] | Sizes, corners, spacing, borders, and timing |
| [[Gui.ThemeImageRects]] | Regions and painted corner radii in the theme image atlas |
| [[Gui.ThemeStyle]] | A control's resolved font, colors, and resources |

A palette is where a theme is written: the ground, the floating surface, the raised
ground, the hairline, three inks, what acts, what is chosen, the link, selection and
highlight grounds, and the status tones. [[Gui.ThemeColors.apply]] turns those into a
value for every painted part, which is what makes a theme complete by construction —
it cannot answer for a button and forget the field beside it.

The toolkit ships two themes. [[Gui.Theme.setDark]] applies Encre and
[[Gui.Theme.setLight]] applies Papier; [[Gui.Application.setAppearance]] chooses
between them, or follows the light or dark setting of the operating system with
[[Gui.AppearanceTheme.System]]. In both, Voltage acts — the primary action, the focus
ring, the caret, the current search occurrence — and Arc chooses: the selected row,
a checked box, a switch that is on, the underline of the active tab, a progress. On
Papier the primary action is the same button turned over, ink on paper, because
Voltage is never written on paper. The first group of [[Gui.ThemeColors]] carries
that vocabulary directly (`ground`, `surface`, `raised`, `line`, `strongLine`, the
three inks, `signature`, `arc`, `link`, `selection`, `highlight`, `critical`,
`caution`, `info`) for parts no control owns.

Both themes share the measures of the charter: a window corner of 10, floating
surfaces of 12 ([[Gui.ThemeMetrics.corner_Floating]]), menus of 10, controls of 6
and chips of 4, buttons and fields 32 high and list rows of 30. The atlas tiles are
drawn with those corners and publish them, so a mark drawn over a control follows
the corner the control was drawn with.

```swag
var palette = Gui.ThemeColors.encrePalette()
palette.signature = Gui.ThemeTone.from(Pixel.Color.fromArgb(0xFF00A0FF), Pixel.Argb.Black)
app.theme.setPalette(palette)
app.notifyThemeChanged()
```

`bin/examples/modules/gui10` is the theme inspector: it lists every color of both
themes and of a sheet-written example by reflection, side by side, and shows every
widget in every state.

Read theme data through the current window so custom controls respect local style
overrides:

```swag
let colors  = wnd.themeColors()
let metrics = wnd.themeMetrics()
let font    = wnd.font()
```

Paint only inside the invalidated region when possible. Call
[[Gui.Wnd.invalidate]] after a visual state change, and
[[Gui.Wnd.invalidateRect]] when only a bounded region changed.
[[Gui.Application.notifyThemeChanged]] recomputes styles and invalidates the
interface after editing shared theme data.

## Defocus the backdrop of a floating window

Set [[Gui.Wnd.backdrop]] to a [[Pixel.BackdropEffect]] before showing the window.
The material filters the content already painted behind it; the window and its children
are drawn afterward and stay sharp. Its opacity follows the window's presentation opacity,
including arrival and departure. Call [[Gui.Wnd.invalidate]] after changing the material.

```swag
panel.backdrop = Pixel.BackdropEffect{radius: 12, saturation: 0.85}
panel.invalidate()
```

[[Pixel.BackdropBlur.DualKawase]] uses a downsampling and reconstruction pyramid for broad
defocus. [[Pixel.BackdropBlur.Gaussian]] provides a normalized separable filter for smaller
extents. Both run through the CPU and OpenGL renderers. Optional tint and opacity controls
compose a material without changing the foreground's colors.

The lens uses the shared [[Gui.ThemeMetrics.lens_BlurRadius]] and
[[Gui.ThemeMetrics.lens_Saturation]] in both themes, without a light or dark veil.
While any backdrop is visible, its surface reconstructs the complete scene on each dirty
frame, so a hover or caret repaint cannot repeatedly blur the previous frame. This costs
more than an ordinary partial repaint. The material samples its current render target;
an enclosing off-screen layer needs an opaque background of its own.

## Headless paint tests

[[Gui.Testing.HeadlessHost]] builds a deterministic application and widget tree
without creating an OS window. [[Gui.Testing.HeadlessHost.render]] runs the normal
surface paint pipeline through Pixel's software renderer and returns owned pixels.
The host shuts down automatically when it leaves scope. Declare any data borrowed
by its windows or callbacks before the host so that it stays alive during teardown.

```swag
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 80)
    discard PushButton.create(&host.root, "Continue", Math.Rectangle{20, 20, 120, 32})

    let image = host.render()
    Pixel.Testing.assertImageGolden(&image, "continue-button")
}
```

Use structural and event assertions for behavior, command goldens for emitted
paint operations, and PNG goldens for the final composition. A small OpenGL
integration suite remains necessary for context, shader compiler, and driver
coverage.
