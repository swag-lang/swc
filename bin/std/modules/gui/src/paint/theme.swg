#global public

using Core, Pixel

private const DefaultImageName = "../theme/widgets.svg"

private const DefaultFontRegularName = "../theme/segoeui.ttf"
private const DefaultFontBoldName = "../theme/segoeuib.ttf"
private const DefaultFontBoldItalicName = "../theme/segoeuiz.ttf"
private const DefaultFontItalicName = "../theme/segoeuii.ttf"

private const DefaultFontFsRegularName = "../theme/consola.ttf"
private const DefaultFontFsBoldName = "../theme/consolab.ttf"
private const DefaultFontFsBoldItalicName = "../theme/consolaz.ttf"
private const DefaultFontFsItalicName = "../theme/consolai.ttf"

private const DefaultIconsName = "../theme/icons.svg"

private const DefaultImage = #include(DefaultImageName)
private const DefaultFontRegular = #include(DefaultFontRegularName)
private const DefaultFontBold = #include(DefaultFontBoldName)
private const DefaultFontBoldItalic = #include(DefaultFontBoldItalicName)
private const DefaultFontItalic = #include(DefaultFontItalicName)
private const DefaultFontFsRegular = #include(DefaultFontFsRegularName)
private const DefaultFontFsBold = #include(DefaultFontFsBoldName)
private const DefaultFontFsBoldItalic = #include(DefaultFontFsBoldItalicName)
private const DefaultFontFsItalic = #include(DefaultFontFsItalicName)
private const DefaultIcons = #include(DefaultIconsName)

// Parsed default theme art, shared by every Theme instance. Parsing the embedded sources is
// pure CPU work whose result never changes, so it is done once per process (same policy as
// the TypeFace/Font caches). Every piece of theme art is a vector document, and rasterizing one
// depends on the requested size and scale alone, so the results are cached beside the drawings:
// widget atlases here by scale, icon sheets inside the [[Gui.IconAtlas]] by cell size. A process
// that builds many themes — a test executable creates one per headless host — then pays for the
// rasterization of each sheet once rather than once per theme.
private struct DefaultThemeImages
{
    lock:           Sync.Mutex
    decoded:        bool
    widgets:        Svg.Drawing                // Vector widgets atlas, parsed once.
    widgetsRasters: HashTable'(s32, Image)     // Rasterizations of `widgets`, by whole scale.
    icons:          IconAtlas                  // Vector icon set, parsed once, with its own frames.
}

// Bundle names of the theme resources. The `Default*Name` constants above are include
// paths relative to this file; these are the logical names a disk folder overrides.
private const ResImageName = "theme/widgets.svg"
private const ResIconsName = "theme/icons.svg"
private const ResFontRegularName = "theme/segoeui.ttf"
private const ResFontBoldName = "theme/segoeuib.ttf"
private const ResFontBoldItalicName = "theme/segoeuiz.ttf"
private const ResFontItalicName = "theme/segoeuii.ttf"
private const ResFontFsRegularName = "theme/consola.ttf"
private const ResFontFsBoldName = "theme/consolab.ttf"
private const ResFontFsBoldItalicName = "theme/consolaz.ttf"
private const ResFontFsItalicName = "theme/consolai.ttf"

private var g_DefaultThemeImages: DefaultThemeImages

// Nullable adapter over [[Pixel.TypeFace.create]], so a failed creation can be caught
// with a null result instead of a non-defaultable pointer.
private func defaultTypeFace(name: string, bytes: const [..] u8)->#null *TypeFace fail
{
    return try TypeFace.create(name, bytes)
}

// Registers the embedded theme art and fonts as the fallback providers of `bundle`.
//
// The application calls this before the first surface exists, so a disk folder added
// to the bundle can override any of these names while a bare application keeps the
// compiled-in theme without any configuration.
internal func registerDefaultThemeResources(bundle: *Resources.Bundle)
{
    bundle.addEmbedded(ResImageName, DefaultImage)
    bundle.addEmbedded(ResIconsName, DefaultIcons)
    bundle.addEmbedded(ResFontRegularName, DefaultFontRegular)
    bundle.addEmbedded(ResFontBoldName, DefaultFontBold)
    bundle.addEmbedded(ResFontBoldItalicName, DefaultFontBoldItalic)
    bundle.addEmbedded(ResFontItalicName, DefaultFontItalic)
    bundle.addEmbedded(ResFontFsRegularName, DefaultFontFsRegular)
    bundle.addEmbedded(ResFontFsBoldName, DefaultFontFsBold)
    bundle.addEmbedded(ResFontFsBoldItalicName, DefaultFontFsBoldItalic)
    bundle.addEmbedded(ResFontFsItalicName, DefaultFontFsItalic)
}

// Creates the typeface behind one theme font resource, honoring a disk override.
//
// The process-wide typeface cache is keyed by name, so an overridden font registers
// under a disk-flavored key and never collides with the embedded face of the same
// name. An override that cannot be read or parsed falls back to the embedded face.
private func themeTypeFace(res: const *Resources.Bundle, name: string, embedded: const [..] u8)->#null *TypeFace fail
{
    if res.isOverridden(name)
    {
        let bytes = catch res.load(name) as loadErr
        if loadErr == null
        {
            var overrideName: String = name
            overrideName += "#override"
            let face = catch defaultTypeFace(overrideName.toString(), bytes.toSlice()) as faceErr
            if faceErr == null and face != null do
                return face
        }
    }

    return try defaultTypeFace(name, embedded)
}

private func defaultThemeImages()->*DefaultThemeImages
{
    let cache = &g_DefaultThemeImages
    Sync.scopedLock(&cache.lock)
    if !cache.decoded
    {
        cache.widgets = expect Svg.Drawing.parse(cast(string) DefaultImage)
        expect cache.icons.setup(cast(string) DefaultIcons)
        cache.decoded = true
    }

    return cache
}

// Returns the shared widgets atlas rasterized at `scale` device pixels per authored texel.
//
// The atlas is rasterized through `renderer`, which is the single most expensive step of
// a GUI startup: on a GPU backend the supersampled buffer is filled and downsampled by
// the hardware that will later sample it, instead of one core walking sixteen million
// pixels. Rasterizations are cached by scale, not by renderer: the backends agree on the
// pixels, so every theme of a process asks for the same few whole scales and each is
// built once — themes re-created at an already-seen scale (headless test hosts, notably)
// reuse them.
private func defaultWidgetsImage(renderer: IRenderer, scale: f32)->*Image
{
    let cache = defaultThemeImages()
    Sync.scopedLock(&cache.lock)

    let key   = cast(s32) scale
    let found = cache.widgetsRasters.tryFind(key)
    if found do
        return &found.value

    let w = cast(s32) Math.round(cache.widgets.width * scale)
    let h = cast(s32) Math.round(cache.widgets.height * scale)

    // Rasterize with strong supersampling so tile edges carry exact coverage; cap
    // the internal buffer so a dense display keeps the one-time cost bounded.
    var ss = 4'u8
    while ss > 1 and w * cast(s32) ss > 4096 do
        ss /= 2

    return &cache.widgetsRasters.add(key, cache.widgets.rasterize(renderer, w, h, ss)).value
}

// Owns decoded theme textures, icon atlases, typefaces, and derived font families.
struct ThemeResources
{
    public
    {
        imgWidgets: Texture     // Widgets atlas texture, rasterized from the vector theme document.
        atlasScale: f32         // Device pixels per authored atlas texel; zero until the atlas is built.
        icons:      IconSet     // The theme icon set, rasterized on demand per size and scale.
        #[Swag.Late]
        {
            defaultTypeFaceR:    *TypeFace     // Default type face r associated with this value.
            defaultTypeFaceB:    *TypeFace     // Default type face b associated with this value.
            defaultTypeFaceI:    *TypeFace     // Default type face i associated with this value.
            defaultTypeFaceBI:   *TypeFace     // Default type face bi associated with this value.
            defaultFsTypeFaceR:  *TypeFace     // Default fs type face r associated with this value.
            defaultFsTypeFaceB:  *TypeFace     // Default fs type face b associated with this value.
            defaultFsTypeFaceI:  *TypeFace     // Default fs type face i associated with this value.
            defaultFsTypeFaceBI: *TypeFace     // Default fs type face bi associated with this value.
        }

        fontDefault:   FontFamily     // Font default associated with this value.
        fontDefaultFs: FontFamily     // Font default fs associated with this value.
    }
}

// Groups all render resources, colors, metrics, and atlas rectangles for one GUI theme.
struct Theme
{
    public
    {
        res:     ThemeResources      // Decoded art, fonts, and font families of the theme.
        rects:   ThemeImageRects     // Regions of the theme atlas each part is drawn from.
        metrics: ThemeMetrics        // Logical dimensions, spacing, and timings.
        colors:  ThemeColors         // One color per painted part, derived from `palette`.

        // The tokens the colors were derived from. A theme sheet that names one of them
        // re-derives the whole palette, which is what makes a theme file thirty lines rather
        // than three hundred; a sheet that names a color instead overrides that one part.
        public readonly
        palette: ThemePalette

        // Whether the theme was set up. A theme is established once against a renderer, so the
        // flag is a result to read, never a switch to flip.
        public readonly
        initialized: bool

        // Font storage of the renderer this theme was set up against; borrowed, never owned. Every
        // font the theme hands out therefore lives exactly as long as the renderer that will draw it.
        #[Swag.Late]
        internal
        fonts: *Pixel.FontCache
    }
}

impl Theme
{
    // Applies a theme sheet to this theme.
    //
    // A sheet is a tweak text with up to four folders whose keys are the reflected field
    // names of [[Gui.ThemePalette]], [[Gui.ThemeColors]], [[Gui.ThemeMetrics]] and
    // [[Gui.ThemeImageRects]]. An omitted key keeps its current value, so a sheet only
    // describes what it changes, and `$name` copies another key of the same folder:
    //
    // ```
    // /ThemePalette
    // ground           0xFF161310
    // text             0xFFEDE4D4
    // accent           0xFFD79921
    // /ThemeColors
    // btnPush_Bk       0xFF202026
    // /ThemeMetrics
    // btnPush_Height   32
    // /ThemeImageRects
    // btnPush_Normal   {{1 29 27 27} 0}
    // btnPush_Hot      $btnPush_Normal
    // ```
    //
    // A whole theme is written in the first folder: naming any palette token re-derives
    // every color from the tokens, so a sheet of thirty lines answers for the three hundred
    // parts of the interface and cannot leave one of them behind. The other folders are for
    // the parts a theme wants different from what its own tokens derive, and they are read
    // after the derivation whatever order they appear in.
    //
    // An unknown key or a malformed value fails with [[Core.Errors.SyntaxError]] carrying
    // the line number; the theme keeps the values already applied before the error. Call
    // [[Gui.Application.notifyThemeChanged]] afterwards when the theme is already on screen.
    mtd applySheet(sheet: string) fail
    {
        // The two layers of a sheet cannot be filled in one pass: deriving the palette would
        // overwrite the individual parts the same text asks for. So the sheet is read twice,
        // each pass keeping the folders it owns and sending the others to a scratch copy —
        // which is also what lets a sheet name its folders in any order.
        var palette        = .palette
        var scratchColors  = .colors
        var scratchMetrics = .metrics
        var scratchRects   = .rects

        var tokens: File.TweakFile
        tokens.registerFolder'ThemePalette(&palette)
        tokens.registerFolder'ThemeColors(&scratchColors)
        tokens.registerFolder'ThemeMetrics(&scratchMetrics)
        tokens.registerFolder'ThemeImageRects(&scratchRects)
        try tokens.parse(sheet)

        if palette != .palette do
            .setPalette(palette)

        var scratchPalette = .palette
        var parts: File.TweakFile
        parts.registerFolder'ThemePalette(&scratchPalette)
        parts.registerFolder'ThemeColors(&.colors)
        parts.registerFolder'ThemeMetrics(&.metrics)
        parts.registerFolder'ThemeImageRects(&.rects)
        try parts.parse(sheet)
    }

    // Derives every color of the theme from `palette`.
    //
    // The tokens are kept, so a later sheet that changes one of them re-derives from the
    // whole set rather than from the defaults.
    mtd setPalette(palette: ThemePalette)
    {
        .palette = palette
        .colors.apply(palette)
    }

    // Loads the theme sheet resource `name` from `resources` and applies it.
    mtd loadSheet(resources: const *Resources.Bundle, name: string) fail
    {
        let bytes = try resources.load(name)
        try .applySheet(cast(string) bytes.toSlice())
    }

    // Applies the neutral dark palette and the geometry the theme atlas was authored with.
    mtd setDark()
    {
        .setPalette(ThemeColors.darkPalette())
        .setDefaultGeometry()
    }

    // Applies the neutral light palette and the geometry the theme atlas was authored with.
    mtd setLight()
    {
        .setPalette(ThemeColors.lightPalette())
        .setDefaultGeometry()
    }

    // Applies the dark Swag palette and its shared control geometry.
    mtd setSwagDark()
    {
        .setPalette(ThemeColors.swagDarkPalette())
        .setSwagGeometry()
    }

    // Applies the light Swag palette and its shared control geometry.
    mtd setSwagLight()
    {
        .setPalette(ThemeColors.swagLightPalette())
        .setSwagGeometry()
    }

    // Restores the geometry the theme atlas was authored with.
    //
    // Every palette has to answer for the shape of a control as well as for its color, or
    // a surface leaving the Swag palette keeps square push buttons and a barely cut window
    // under a blue accent — a mix no palette ever described. The declared values of
    // [[Gui.ThemeImageRects]] and [[Gui.ThemeMetrics]] are that authored geometry, which is
    // why restoring it is an initialization rather than a second list of numbers to keep in
    // step with the first.
    private mtd setDefaultGeometry()
    {
        var defaults: ThemeMetrics
        .metrics.surfaceWnd_CornerRadius = defaults.surfaceWnd_CornerRadius
        @init(&.rects, 1)
    }

    // Gives a push button the geometry the theme already gives an edit box.
    //
    // The default atlas draws a push button as a pill, which is the one control that cannot sit
    // next to a field without looking borrowed from another kit. Pointing it at the edit tiles
    // is the whole change: same corner, same stroke weight, so a row of a form reads as one
    // control and not as a box beside a capsule. Nothing else is repointed, because refusing a
    // capsule is not the same as squaring every corner of the interface.
    private mtd setSwagGeometry()
    {
        // A window is the one form the chart lets round. The cut is a vocabulary for the mark and
        // for the repeated elements of a page; carried literally onto the outline of a window it
        // reads as a slab dropped on the desktop, next to every other application that softens
        // that corner. The radius still has to be seen to do its job: at 8 the corner read as a
        // bevel on a square window rather than as a decision, so it is 12 — deliberate against
        // the desktop, and still well short of the 18 the neutral palettes use.
        .metrics.surfaceWnd_CornerRadius = 12

        .rects.btnPush_Normal         = .rects.edit_SquareBk
        .rects.btnPush_Hot            = .rects.edit_SquareBk
        .rects.btnPush_Pressed        = .rects.edit_SquareBk
        .rects.btnPush_Disabled       = .rects.edit_SquareBk
        .rects.btnPush_NormalBorder   = .rects.edit_SquareBorder
        .rects.btnPush_HotBorder      = .rects.edit_SquareBorder
        .rects.btnPush_PressedBorder  = .rects.edit_SquareBorder
        .rects.btnPush_DisabledBorder = .rects.edit_SquareBorder
    }

    private mtd freeDefault()
    {
        .res.icons.free()
    }

    // Establishes the shared theme resources against `renderer`, sharp at `dpiScale`.
    //
    // The caller passes the density of the surface the theme is about to draw on, because
    // rasterizing the widgets atlas is the single most expensive step of a GUI startup and
    // [[Theme.ensureAtlasScale]] cannot reuse a coarser atlas: building at 1 first would
    // throw that work away on every scaled display. The fonts resolve through `resources`,
    // so a disk folder can override the embedded ones.
    private mtd setupDefault(renderer: IRenderer, resources: const *Resources.Bundle, dpiScale = 1.0'f32)
    {
        .initialized = true
        .fonts       = renderer.fontCache()
        .setDark()

        .ensureAtlasScale(renderer, dpiScale)

        let images = defaultThemeImages()
        .res.icons.setup(renderer, &images.icons)

        .setupDefaultFonts(resources)
    }

    // Keeps the widgets atlas texture at least as sharp as `scale` device pixels per authored texel.
    //
    // The vector theme document is the source of truth; the atlas texture is only its cached
    // rasterization, rebuilt here so themed drawing stays one textured blit at native
    // resolution. The scale is rounded up to a whole number so the nine-slice source cuts of
    // [[ThemeImageRects]] stay on texel boundaries: on a fractional grid every tile border
    // would sample its neighbor. The atlas only sharpens; a request at or below the current
    // scale returns immediately, so a surface moving to a coarser monitor keeps the sharp
    // atlas, which minifies cleanly.
    mtd ensureAtlasScale(renderer: IRenderer, scale: f32)
    {
        let wanted = Math.max(Math.ceil(scale), 1.0)
        if wanted <= .res.atlasScale do
            return

        if .res.atlasScale > 0 do
            renderer.removeTexture(&.res.imgWidgets)

        let image = defaultWidgetsImage(renderer, wanted)
        .res.imgWidgets = renderer.addImage(image[])
        .res.atlasScale = wanted
    }

    // Loads the default typefaces and builds the default font families, resolving each
    // font resource through `resources` so a disk folder can override the embedded ones.
    //
    // Glyph metrics are rasterized on the CPU, so this works with either painter backend.
    // Idempotent.
    private mtd setupDefaultFonts(resources: const *Resources.Bundle)
    {
        with me.res
        {
            if @isset(.defaultTypeFaceR) do
                return

            .defaultTypeFaceR  = expect themeTypeFace(resources, ResFontRegularName, DefaultFontRegular)!
            .defaultTypeFaceB  = expect themeTypeFace(resources, ResFontBoldName, DefaultFontBold)!
            .defaultTypeFaceI  = expect themeTypeFace(resources, ResFontItalicName, DefaultFontItalic)!
            .defaultTypeFaceBI = expect themeTypeFace(resources, ResFontBoldItalicName, DefaultFontBoldItalic)!

            .defaultFsTypeFaceR  = expect themeTypeFace(resources, ResFontFsRegularName, DefaultFontFsRegular)!
            .defaultFsTypeFaceB  = expect themeTypeFace(resources, ResFontFsBoldName, DefaultFontFsBold)!
            .defaultFsTypeFaceI  = expect themeTypeFace(resources, ResFontFsItalicName, DefaultFontFsItalic)!
            .defaultFsTypeFaceBI = expect themeTypeFace(resources, ResFontFsBoldItalicName, DefaultFontFsBoldItalic)!

            .fontDefault.regular    = .fonts.createFont(.defaultTypeFaceR, me.metrics.defaultFontSize)
            .fontDefault.bold       = .fonts.createFont(.defaultTypeFaceB, me.metrics.defaultFontSize)
            .fontDefault.italic     = .fonts.createFont(.defaultTypeFaceI, me.metrics.defaultFontSize)
            .fontDefault.boldItalic = .fonts.createFont(.defaultTypeFaceBI, me.metrics.defaultFontSize)

            .fontDefaultFs.regular    = .fonts.createFont(.defaultFsTypeFaceR, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.bold       = .fonts.createFont(.defaultFsTypeFaceB, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.italic     = .fonts.createFont(.defaultFsTypeFaceI, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.boldItalic = .fonts.createFont(.defaultFsTypeFaceBI, me.metrics.defaultFixedFontSize)
        }
    }

    // Create a default font family with the given size
    mtd createDefaultFontfamily(size: u32)->FontFamily
    {
        var result: retval
        result.regular    = .fonts.createFont(.res.defaultTypeFaceR, size)
        result.bold       = .fonts.createFont(.res.defaultTypeFaceB, size)
        result.italic     = .fonts.createFont(.res.defaultTypeFaceI, size)
        result.boldItalic = .fonts.createFont(.res.defaultTypeFaceBI, size)
        return result
    }

    // Create a default font with the given size
    mtd createDefaultFont(size: u32, style = FontFamilyStyle.Regular)->*Font
    {
        switch #complete style
        {
        case .Regular:    return .fonts.createFont(.res.defaultTypeFaceR, size)
        case .Bold:       return .fonts.createFont(.res.defaultTypeFaceB, size)
        case .Italic:     return .fonts.createFont(.res.defaultTypeFaceI, size)
        case .BoldItalic: return .fonts.createFont(.res.defaultTypeFaceBI, size)
        }

        unreachable
    }

    // Create a default font (fixed size) with the given size
    mtd createDefaultFontFS(size: u32, style = FontFamilyStyle.Regular)->*Font
    {
        switch #complete style
        {
        case .Regular:    return .fonts.createFont(.res.defaultFsTypeFaceR, size)
        case .Bold:       return .fonts.createFont(.res.defaultFsTypeFaceB, size)
        case .Italic:     return .fonts.createFont(.res.defaultFsTypeFaceI, size)
        case .BoldItalic: return .fonts.createFont(.res.defaultFsTypeFaceBI, size)
        }

        unreachable
    }
}
