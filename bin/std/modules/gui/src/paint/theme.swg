#global public

using Core, Pixel

private const DefaultImageName = "theme/widgets.png"

private const DefaultFontRegularName = "theme/segoeui.ttf"
private const DefaultFontBoldName = "theme/segoeuib.ttf"
private const DefaultFontBoldItalicName = "theme/segoeuiz.ttf"
private const DefaultFontItalicName = "theme/segoeuii.ttf"

private const DefaultFontFsRegularName = "theme/consola.ttf"
private const DefaultFontFsBoldName = "theme/consolab.ttf"
private const DefaultFontFsBoldItalicName = "theme/consolaz.ttf"
private const DefaultFontFsItalicName = "theme/consolai.ttf"

private const DefaultIcons24Name = "theme/icons24.png"
private const DefaultIcons64Name = "theme/icons64.png"
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
private const DefaultIcons24 = #include(DefaultIcons24Name)
private const DefaultIcons64 = #include(DefaultIcons64Name)
private const DefaultSpin = #include(DefaultSpinName)

// Decoded default theme images, shared by every Theme instance. Decoding the
// embedded PNGs is pure CPU work whose result never changes, so it is done once
// per process (same policy as the TypeFace/Font caches).
private struct DefaultThemeImages
{
    lock:    Sync.Mutex
    decoded: bool
    widgets: Image
    icons24: Image
    icons64: Image
    spin:    Image
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
    bundle.addEmbedded(DefaultIcons24Name, DefaultIcons24)
    bundle.addEmbedded(DefaultIcons64Name, DefaultIcons64)
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
        cache.widgets = expect Image.decode(DefaultImageName, DefaultImage)
        cache.icons24 = expect Image.decode(DefaultIcons24Name, DefaultIcons24)
        cache.icons64 = expect Image.decode(DefaultIcons64Name, DefaultIcons64)
        cache.spin    = expect Image.decode(DefaultSpinName, DefaultSpin)
        cache.decoded = true
    }

    return cache
}

// Owns decoded theme textures, icon atlases, typefaces, and derived font families.
struct ThemeResources
{
    imgWidgets: Texture     // Img widgets associated with this value.
    #[Swag.Late]
    {
        icons24:             *ImageList     // Icons24 associated with this value.
        icons64:             *ImageList     // Icons64 associated with this value.
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
        if @isset(.res.icons24) do
            Memory.delete(.res.icons24)
        if @isset(.res.icons64) do
            Memory.delete(.res.icons64)
        if @isset(.res.spin) do
            Memory.delete(.res.spin)
    }

    private mtd setupDefault(renderer: IRenderer, resources: const *Resources.Bundle)
    {
        .initialized = true
        .fonts       = renderer.fontCache()
        .colors.setDark()

        let images = defaultThemeImages()
        with me.res
        {
            .imgWidgets = addThemeImage(renderer, resources, DefaultImageName, &images.widgets)

            .icons24 = Memory.new'ImageList()
            .icons24.set(addThemeImage(renderer, resources, DefaultIcons24Name, &images.icons24), 24, 24)

            .icons64 = Memory.new'ImageList()
            .icons64.set(addThemeImage(renderer, resources, DefaultIcons64Name, &images.icons64), 64, 64)

            .spin = Memory.new'ImageList()
            .spin.set(addThemeImage(renderer, resources, DefaultSpinName, &images.spin), 48, 48)
        }

        .setupDefaultFonts(resources)
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

            .defaultTypeFaceR  = notnull expect themeTypeFace(resources, DefaultFontRegularName, DefaultFontRegular)
            .defaultTypeFaceB  = notnull expect themeTypeFace(resources, DefaultFontBoldName, DefaultFontBold)
            .defaultTypeFaceI  = notnull expect themeTypeFace(resources, DefaultFontItalicName, DefaultFontItalic)
            .defaultTypeFaceBI = notnull expect themeTypeFace(resources, DefaultFontBoldItalicName, DefaultFontBoldItalic)

            .defaultFsTypeFaceR  = notnull expect themeTypeFace(resources, DefaultFontFsRegularName, DefaultFontFsRegular)
            .defaultFsTypeFaceB  = notnull expect themeTypeFace(resources, DefaultFontFsBoldName, DefaultFontFsBold)
            .defaultFsTypeFaceI  = notnull expect themeTypeFace(resources, DefaultFontFsItalicName, DefaultFontFsItalic)
            .defaultFsTypeFaceBI = notnull expect themeTypeFace(resources, DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)

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
