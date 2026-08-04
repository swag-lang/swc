#global public

using Core, Pixel

private const DefaultImageName = "theme/widgets.svg"

private const DefaultFontRegularName = "theme/segoeui.ttf"
private const DefaultFontBoldName = "theme/segoeuib.ttf"
private const DefaultFontBoldItalicName = "theme/segoeuiz.ttf"
private const DefaultFontItalicName = "theme/segoeuii.ttf"

private const DefaultFontFsRegularName = "theme/consola.ttf"
private const DefaultFontFsBoldName = "theme/consolab.ttf"
private const DefaultFontFsBoldItalicName = "theme/consolaz.ttf"
private const DefaultFontFsItalicName = "theme/consolai.ttf"

private const DefaultIconsName = "theme/icons.svg"
private const DefaultSpinName = "theme/spin.png"

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
    widgets:        Svg.Drawing                // Vector widgets atlas, parsed once.
    widgetsRasters: HashTable'(s32, Image)     // Rasterizations of `widgets`, by whole scale.
    icons:          Svg.Drawing                // Vector icon set, parsed once.
    spin:           Image
}

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
    bundle.addEmbedded(DefaultImageName, DefaultImage)
    bundle.addEmbedded(DefaultIconsName, DefaultIcons)
    bundle.addEmbedded(DefaultSpinName, DefaultSpin)
    bundle.addEmbedded(DefaultFontRegularName, DefaultFontRegular)
    bundle.addEmbedded(DefaultFontBoldName, DefaultFontBold)
    bundle.addEmbedded(DefaultFontBoldItalicName, DefaultFontBoldItalic)
    bundle.addEmbedded(DefaultFontItalicName, DefaultFontItalic)
    bundle.addEmbedded(DefaultFontFsRegularName, DefaultFontFsRegular)
    bundle.addEmbedded(DefaultFontFsBoldName, DefaultFontFsBold)
    bundle.addEmbedded(DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)
    bundle.addEmbedded(DefaultFontFsItalicName, DefaultFontFsItalic)
}

// Uploads one theme image, honoring a disk override from the bundle.
//
// Without an override, the embedded art goes through the process-wide decoded cache.
// An override that cannot be read or decoded falls back to the embedded art, so a
// broken theme folder degrades to the default look instead of stopping the program.
private func addThemeImage(renderer: IRenderer, res: const *Resources.Bundle, name: string, embedded: const *Image)->Texture
{
    if res.isOverridden(name)
    {
        let bytes = catch res.load(name) as loadErr
        if loadErr == null
        {
            let decoded = catch Image.decode(name, bytes.toSlice()) as decodeErr
            if decodeErr == null do
                return renderer.addImage(decoded)
        }
    }

    return renderer.addImage(dref embedded)
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
    imgWidgets: Texture                         // Widgets atlas texture, rasterized from the vector theme document.
    atlasScale: f32                             // Device pixels per authored atlas texel; zero until the atlas is built.
    iconLists:  HashTable'(s32, *ImageList)     // Icon frame lists by logical size, rasterized from the vector icon set.
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

    // The renderer this theme was set up against; borrowed so on-demand resources — the
    // icon frame lists, atlas rebuilds — can be created outside the setup call.
    #[Swag.Late]
    internal
    renderer: Pixel.IRenderer
}

impl Theme
{
    // Applies a theme sheet to this theme.
    //
    // A sheet is a tweak text with up to three folders whose keys are the reflected field
    // names of [[ThemeColors]], [[ThemeMetrics]] and [[ThemeImageRects]]. An omitted key
    // keeps its current value, so a sheet only describes what it changes, and `$name`
    // copies another key of the same folder:
    //
    // ```
    // /ThemeColors
    // btnPush_Bk       0xFF202026
    // /ThemeMetrics
    // btnPush_Height   32
    // /ThemeImageRects
    // btnPush_Normal   {{1 29 27 27} 0}
    // btnPush_Hot      $btnPush_Normal
    // ```
    //
    // An unknown key or a malformed value fails with [[Core.Errors.SyntaxError]] carrying
    // the line number; the theme keeps the values already applied before the error. Call
    // [[Gui.Application.notifyThemeChanged]] afterwards when the theme is already on screen.
    mtd applySheet(sheet: string) fail
    {
        var tf: File.TweakFile
        tf.registerFolder'ThemeColors(&.colors)
        tf.registerFolder'ThemeMetrics(&.metrics)
        tf.registerFolder'ThemeImageRects(&.rects)
        try tf.parse(sheet)
    }

    // Loads the theme sheet resource `name` from `resources` and applies it.
    mtd loadSheet(resources: const *Resources.Bundle, name: string) fail
    {
        let bytes = try resources.load(name)
        try .applySheet(cast(string) bytes.toSlice())
    }

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
        for key, [value] in .res.iconLists do
            Memory.delete(value)
        .res.iconLists.clear()
        if @isset(.res.spin) do
            Memory.delete(.res.spin)
    }

    private mtd setupDefault(renderer: IRenderer, resources: const *Resources.Bundle)
    {
        .initialized = true
        .fonts       = renderer.fontCache()
        .renderer    = renderer
        .colors.setDark()

        .ensureAtlasScale(renderer, 1)

        let images = defaultThemeImages()
        with me.res
        {
            .spin = Memory.new'ImageList()
            .spin.set(addThemeImage(renderer, resources, DefaultSpinName, &images.spin), 48, 48)
        }

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

        let image = defaultWidgetsImage(wanted)
        .res.imgWidgets = renderer.addImage(dref image)
        .res.atlasScale = wanted

        // The icon frame lists follow the atlas density; drop them so the next
        // request rebuilds them at the new scale.
        for key, [value] in .res.iconLists
        {
            value.release(renderer)
            Memory.delete(value)
        }

        .res.iconLists.clear()
    }

    // Returns the icon frame list for `size` logical pixels, building it on first use.
    //
    // Frames are rasterized from the vector icon set at `size` times the atlas scale,
    // so icons follow the same density policy as the widgets atlas and stay sharp on
    // any display.
    internal mtd iconList(size: f32)->*ImageList
    {
        let key   = cast(s32) Math.max(Math.round(size), 1.0)
        let found = .res.iconLists.tryFind(key)
        if found do
            return found.value

        let images = defaultThemeImages()
        let cols   = cast(s32) Math.round(images.icons.width / 24)
        let rows   = cast(s32) Math.round(images.icons.height / 24)
        let cell   = key * cast(s32) Math.max(.res.atlasScale, 1.0)

        // Same supersampling policy as the widgets atlas: exact edge coverage, with
        // the internal buffer bounded on dense displays.
        var ss = 4'u8
        while ss > 1 and cols * cell * cast(s32) ss > 8192 do
            ss /= 2

        let image = images.icons.rasterize(cols * cell, rows * cell, ss)
        let list  = Memory.new'ImageList()
        list.set(.renderer.addImage(image), cell, cell)
        .res.iconLists.add(key, list)
        return list
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

            .defaultTypeFaceR  = expect themeTypeFace(resources, DefaultFontRegularName, DefaultFontRegular)!
            .defaultTypeFaceB  = expect themeTypeFace(resources, DefaultFontBoldName, DefaultFontBold)!
            .defaultTypeFaceI  = expect themeTypeFace(resources, DefaultFontItalicName, DefaultFontItalic)!
            .defaultTypeFaceBI = expect themeTypeFace(resources, DefaultFontBoldItalicName, DefaultFontBoldItalic)!

            .defaultFsTypeFaceR  = expect themeTypeFace(resources, DefaultFontFsRegularName, DefaultFontFsRegular)!
            .defaultFsTypeFaceB  = expect themeTypeFace(resources, DefaultFontFsBoldName, DefaultFontFsBold)!
            .defaultFsTypeFaceI  = expect themeTypeFace(resources, DefaultFontFsItalicName, DefaultFontFsItalic)!
            .defaultFsTypeFaceBI = expect themeTypeFace(resources, DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)!

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
