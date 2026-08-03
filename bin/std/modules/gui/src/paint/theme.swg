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
    // Applies the dark Swag palette and its square top-level surface geometry.
    mtd setSwagDark()
    {
        .colors.setSwagDark()
        .metrics.surfaceWnd_CornerRadius = 0
    }

    // Applies the light Swag palette and its square top-level surface geometry.
    mtd setSwagLight()
    {
        .colors.setSwagLight()
        .metrics.surfaceWnd_CornerRadius = 0
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

    private mtd setupDefault(renderer: IRenderer)
    {
        .initialized = true
        .fonts       = renderer.fontCache()
        .colors.setDark()

        let images = defaultThemeImages()
        with me.res
        {
            .imgWidgets = renderer.addImage(images.widgets)

            .icons24 = Memory.new'ImageList()
            .icons24.set(renderer.addImage(images.icons24), 24, 24)

            .icons64 = Memory.new'ImageList()
            .icons64.set(renderer.addImage(images.icons64), 64, 64)

            .spin = Memory.new'ImageList()
            .spin.set(renderer.addImage(images.spin), 48, 48)
        }

        .setupDefaultFonts()
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

            .defaultTypeFaceR  = notnull expect defaultTypeFace(DefaultFontRegularName, DefaultFontRegular)
            .defaultTypeFaceB  = notnull expect defaultTypeFace(DefaultFontBoldName, DefaultFontBold)
            .defaultTypeFaceI  = notnull expect defaultTypeFace(DefaultFontItalicName, DefaultFontItalic)
            .defaultTypeFaceBI = notnull expect defaultTypeFace(DefaultFontBoldItalicName, DefaultFontBoldItalic)

            .defaultFsTypeFaceR  = notnull expect defaultTypeFace(DefaultFontFsRegularName, DefaultFontFsRegular)
            .defaultFsTypeFaceB  = notnull expect defaultTypeFace(DefaultFontFsBoldName, DefaultFontFsBold)
            .defaultFsTypeFaceI  = notnull expect defaultTypeFace(DefaultFontFsItalicName, DefaultFontFsItalic)
            .defaultFsTypeFaceBI = notnull expect defaultTypeFace(DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)

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
