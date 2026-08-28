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

A theme sheet is a tweak text with up to four folders whose keys are the reflected
field names of [[Gui.ThemePalette]], [[Gui.ThemeColors]], [[Gui.ThemeMetrics]], and
[[Gui.ThemeImageRects]]. An omitted key keeps its current value, so a sheet is a
delta over the active theme, and `$name` copies another key of the same folder:

```
/ThemePalette
ground             0xFF161310
text               0xFFEDE4D4
signature.mark     0xFFD79921
signature.ground   0xFFD79921
signature.onGround 0xFF161310
/ThemeColors
btnPush_Bk         0xFF202026
/ThemeMetrics
btnPush_Height     32
/ThemeImageRects
btnPush_Normal     {{1 29 27 27} 0}
btnPush_Hot        $btnPush_Normal
```

A whole theme is the first folder and nothing else: naming any palette token
re-derives every semantic color from the tokens, so a sheet of thirty lines answers
for the three hundred parts of the interface and cannot leave one of them carrying
the color of the theme it started from. The other folders are for the parts a theme
wants different from what its own tokens derive, and they are read after the
derivation whatever order they appear in.
`bin/examples/modules/gui10/src/sepia.tweak` is a complete worked sheet.

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

## Languages

A tag is only presentable once it is registered with its name, so a picker can
list what the application ships without hard-coding it:

```swag
Gui.registerLanguage("fr", "Français")
```

[[Gui.ReferenceLanguage]] — `"en"` — is always registered and always comes
first: it names the declared reference wording and needs no resource file.
[[Gui.languages]] returns what a picker should show, and a language is named in
its own words, so those names are never translated.

English is the language an application starts in. Following the account instead
is a choice the user makes, not a guess the application makes on its behalf:
[[Gui.systemLanguage]] resolves [[Core.Env.userLocaleName]] against the
registered tags and falls back to the reference language, and
[[Gui.Application.setSystemLanguage]] applies it. Applying a tag that was never
registered fails rather than silently presenting itself as applied.

Embed the translation and validate it when the module compiles: a mistyped key
becomes a build error with its line number instead of a runtime fallback.

```swag
const FrenchStrings = #include("lang/fr/myapp.tweak")

#run
{
    expect Gui.validateStrings'AppStrings(cast(string) FrenchStrings)
}
```

## Wording a literal cannot carry

Two places state a wording where a string table cannot reach: a property
attribute and a menu item built from a literal. Both have a hook.

A property attribute value is a compile-time constant, so the grid generates
`#[Properties.Name("Thickness")]` exactly as declared. Install one resolver and
that literal becomes a key instead — every label, description, category
segment, heading, note, unit and enumeration entry the grid builds passes
through it:

```swag
Properties.setTextResolver(func(key: string)->#null string
{
    switch key
    {
    case "Thickness": return appStrings().propThickness
    }
    return null
})
```

Answer `null` for a string the resolver does not own: the strings this module
declares answer next, and the declared wording stands when nobody does. Rows
resolve as they are built, so rebuild a grid that has to follow a switch —
[[Gui.PropertiesCtrl.clear]] and the same `addStruct` calls again.

A menu bar copies the wording into its item once, so the entries of a bar built
at start-up would keep the language they were built in while everything below
them refreshes through the command state. Build them from a
[[Gui.MenuLabelResolver]] instead, and the label is read again on every layout:

```swag
topMenu.addPopup(func()->string => appStrings().menuFile, fileMenu)
```

## Sizes belong to the text

Translated wording is longer than the reference more often than not, so a
surface that survives a language switch is one that never wrote its sizes down.
Leave an axis unsized and the layout pass asks the window itself through
[[Gui.IWnd.measureContent]]: a button widens with its caption, a combo box with
its widest entry, a wrapped paragraph grows taller, and a band docked without a
height is as tall as what it holds. An axis carrying an explicit size keeps it,
so this is opt-in per widget and per axis.

```swag
// Width measured from the caption, height stated because the row is a design decision.
let action = PushButton.create(card, appStrings().createVault, {0, 0, 0, 36})

// A paragraph that decides its own height, whatever the language costs.
let help = Label.create(card, appStrings().createHelp, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
help.dockStyle = .Top
```

Re-label with [[Gui.Button.setText]], [[Gui.Label.setText]] and
[[Gui.FormLayoutCtrl.setRowLabel]] when the notification arrives, then arrange
again: the sizes follow the new wording on their own. Prove it rather than
trust it — `Gui.Testing.assertContentFits` walks a surface and fails on the
first window smaller than what it says it needs, so a test that loops over
[[Gui.languages]] is enough to keep every shipped translation honest.
