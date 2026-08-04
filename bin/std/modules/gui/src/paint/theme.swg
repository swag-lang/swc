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
private const DefaultSpinName = "../theme/spin.png"

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
private const DefaultSpin = #include(DefaultSpinName)

// Decoded default theme images, shared by every Theme instance. Decoding the
// embedded sources is pure CPU work whose result never changes, so it is done
// once per process (same policy as the TypeFace/Font caches). The widgets atlas
// and the icon set are authored as vector documents; widget rasterizations depend
// only on the requested scale, so they are cached beside the parsed drawings.
private struct DefaultThemeImages
{
    lock:           Sync.Mutex
    decoded:        bool
    widgets:        Svg.Drawing                 // Vector widgets atlas, parsed once.
    widgetsRasters: HashTable'(s32, Image)      // Rasterizations of `widgets`, by whole scale.
    icons:          Svg.Drawing                 // Vector icon set, parsed once.
    spin:           Image
}

private var g_DefaultThemeImages: DefaultThemeImages

private func defaultTypeFace(name: string, bytes: const [..] u8)->#null *TypeFace fail
{
    return try TypeFace.create(name, bytes)
}

private func defaultThemeImages()->*DefaultThemeImages
{
    let cache = &g_DefaultThemeImages
    Sync.scopedLock(&cache.lock)
    if !cache.decoded
    {
        cache.widgets = expect Svg.Drawing.parse(cast(string) DefaultImage)
        cache.icons   = expect Svg.Drawing.parse(cast(string) DefaultIcons)
        cache.spin    = expect Image.decode(DefaultSpinName, DefaultSpin)
        cache.decoded = true
    }

    return cache
}

// Returns the shared widgets atlas rasterized at `scale` device pixels per authored texel.
//
// Rasterizations are cached by scale: every theme of a process asks for the same few
// whole scales, so each is built once and themes re-created at an already-seen scale
// (headless test hosts, notably) reuse the pixels.
private func defaultWidgetsImage(scale: f32)->*Image
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

    return &cache.widgetsRasters.add(key, cache.widgets.rasterize(w, h, ss)).value
}

// Owns decoded theme textures, icon atlases, typefaces, and derived font families.
struct ThemeResources
{
    imgWidgets: Texture      // Widgets atlas texture, rasterized from the vector theme document.
    atlasScale: f32          // Device pixels per authored atlas texel; zero until the atlas is built.
    icons:      IconSet      // The theme icon set, rasterized on demand per size and scale.
    #[Swag.Late]
    {
        spin:                *ImageList     // Spin associated with this value.
        defaultTypeFaceR:    *TypeFace      // Default type face r associated with this value.
        defaultTypeFaceB:    *TypeFace      // Default type face b associated with this value.
        defaultTypeFaceI:    *TypeFace      // Default type face i associated with this value.
        defaultTypeFaceBI:   *TypeFace      // Default type face bi associated with this value.
        defaultFsTypeFaceR:  *TypeFace      // Default fs type face r associated with this value.
        defaultFsTypeFaceB:  *TypeFace      // Default fs type face b associated with this value.
        defaultFsTypeFaceI:  *TypeFace      // Default fs type face i associated with this value.
        defaultFsTypeFaceBI: *TypeFace      // Default fs type face bi associated with this value.
    }

    fontDefault:   FontFamily     // Font default associated with this value.
    fontDefaultFs: FontFamily     // Font default fs associated with this value.
}

// Groups all render resources, colors, metrics, and atlas rectangles for one GUI theme.
struct Theme
{
    res:     ThemeResources      // Res associated with this value.
    rects:   ThemeImageRects     // Rects associated with this value.
    metrics: ThemeMetrics        // Metrics associated with this value.
    colors:  ThemeColors         // Colors associated with this value.

    // Whether the theme was set up. A theme is established once against a renderer, so the
    // flag is a result to read, never a switch to flip.
    readonly
    initialized: bool

    // Font storage of the renderer this theme was set up against; borrowed, never owned. Every
    // font the theme hands out therefore lives exactly as long as the renderer that will draw it.
    #[Swag.Late]
    internal
    fonts: *Pixel.FontCache
}

impl Theme
{
    // Applies the dark Swag palette and its shared control geometry.
    mtd setSwagDark()
    {
        .colors.setSwagDark()
        .setSwagGeometry()
    }

    // Applies the light Swag palette and its shared control geometry.
    mtd setSwagLight()
    {
        .colors.setSwagLight()
        .setSwagGeometry()
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
        .metrics.surfaceWnd_CornerRadius = 0

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
        // A fonts-only theme (headless text measurement) never created the image lists.
        .res.icons.free()
        if @isset(.res.spin) do
            Memory.delete(.res.spin)
    }

    private mtd setupDefault(renderer: IRenderer)
    {
        .initialized = true
        .fonts       = renderer.fontCache()
        .colors.setDark()

        .ensureAtlasScale(renderer, 1)

        let images = defaultThemeImages()
        .res.icons.setup(renderer, &images.icons)
        with me.res
        {
            .spin = Memory.new'ImageList()
            .spin.set(renderer.addImage(images.spin), 48, 48)
        }

        .setupDefaultFonts()
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

        let image = defaultWidgetsImage(wanted)
        .res.imgWidgets = renderer.addImage(dref image)
        .res.atlasScale = wanted
    }

    // Loads the embedded typefaces and builds the default font families.
    //
    // Glyph metrics are rasterized on the CPU, so this works with either painter backend.
    // Idempotent.
    private mtd setupDefaultFonts()
    {
        with me.res
        {
            if @isset(.defaultTypeFaceR) do
                return

            .defaultTypeFaceR  = expect defaultTypeFace(DefaultFontRegularName, DefaultFontRegular)!
            .defaultTypeFaceB  = expect defaultTypeFace(DefaultFontBoldName, DefaultFontBold)!
            .defaultTypeFaceI  = expect defaultTypeFace(DefaultFontItalicName, DefaultFontItalic)!
            .defaultTypeFaceBI = expect defaultTypeFace(DefaultFontBoldItalicName, DefaultFontBoldItalic)!

            .defaultFsTypeFaceR  = expect defaultTypeFace(DefaultFontFsRegularName, DefaultFontFsRegular)!
            .defaultFsTypeFaceB  = expect defaultTypeFace(DefaultFontFsBoldName, DefaultFontFsBold)!
            .defaultFsTypeFaceI  = expect defaultTypeFace(DefaultFontFsItalicName, DefaultFontFsItalic)!
            .defaultFsTypeFaceBI = expect defaultTypeFace(DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)!

            .fontDefault.regular    =.fonts.createFont(.defaultTypeFaceR, me.metrics.defaultFontSize)
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
