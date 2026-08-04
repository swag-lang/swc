# Resources and localization

Every [[Gui.Application]] owns a [[Core.Resources.Bundle]] in
[[Gui.Application.resources]]. A resource is a run of bytes addressed by a
`/`-separated name, such as `theme/widgets.png` or `lang/fr/gui.tweak`. The
embedded content of every loaded module registers itself as the fallback
provider, so a bare application needs no configuration; a disk folder added
before the first surface lets files override any of those names without
recompiling:

```swag
var app: Application

#main
{
    // Files under datas/ now override the embedded theme art, fonts,
    // theme sheets, and language files of the same name.
    app.resources.addFolder("datas")

    let surface = notnull (try app.createSurface(100, 100, 640, 420, SurfaceFlags.StandardWindow))
    surface.show()
    return app.run()
}
```

## Theme sheets

A theme sheet is a tweak text with up to three folders whose keys are the
reflected field names of [[Gui.ThemeColors]], [[Gui.ThemeMetrics]], and
[[Gui.ThemeImageRects]]. An omitted key keeps its current value, so a sheet is a
delta over the active theme, and `$name` copies another key of the same folder:

```
/ThemeColors
btnPush_Bk       0xFF202026
/ThemeMetrics
btnPush_Height   32
/ThemeImageRects
btnPush_Normal   {{1 29 27 27} 0}
btnPush_Hot      $btnPush_Normal
```

Apply a sheet with [[Gui.Theme.applySheet]], or resolve
`themes/<name>.tweak` through the bundle and refresh every surface with
[[Gui.Application.loadTheme]]. An unknown key fails with the faulty line
number, so a broken sheet is reported instead of half-applied silently.

## String tables

Visible strings live in structs of `string` fields whose declared values are
the reference English wording. The GUI module owns [[Gui.Strings]], read
through [[Gui.strings]]; an application declares its own table the same way
and registers it once with [[Gui.registerStrings]]:

```swag
struct AppStrings
{
    mainTitle: string = "My application"
}

var g_AppStrings: AppStrings

#main
{
    Gui.registerStrings'AppStrings(&g_AppStrings, "myapp")
    // ...
}
```

A language file is one `key value` line per overridden field, resolved as the
resource `lang/<tag>/<file>.tweak`. A key the file omits keeps its reference
value, so a translation only carries what it changes.
[[Gui.Application.setLanguage]] retargets every registered table and sends a
`LanguageChanged` notification through every surface; command-driven controls
pick the new wording up on their next update, while text set once at
construction must listen for the notification or be rebuilt.

Embed the translation and validate it when the module compiles: a mistyped key
becomes a build error with its line number instead of a runtime fallback.

```swag
const FrenchStrings = #include("lang/fr/myapp.tweak")

#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
```

Translated captions are longer than the reference wording more often than not.
[[Gui.PushButton.fitWidthToLabel]] sizes a button from its caption, and the
standard dialogs already size their action buttons this way, so a French or
German caption widens its button instead of clipping.
