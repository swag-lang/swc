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
    lock:        Sync.Mutex
    decoded:     bool
    widgets:     Image
    icons24:     Image
    icons64:     Image
    spin:        Image
}

private var g_DefaultThemeImages: DefaultThemeImages

private func defaultThemeImages()->*DefaultThemeImages
{
    let cache = &g_DefaultThemeImages
    Sync.scopedLock(&cache.lock)
    if !cache.decoded
    {
        cache.widgets = assume Image.decode(DefaultImageName, DefaultImage)
        cache.icons24 = assume Image.decode(DefaultIcons24Name, DefaultIcons24)
        cache.icons64 = assume Image.decode(DefaultIcons64Name, DefaultIcons64)
        cache.spin    = assume Image.decode(DefaultSpinName, DefaultSpin)
        cache.decoded = true
    }

    return cache
}

struct ThemeResources
{
    imgWidgets:              Texture
    icons24:                 #null *ImageList
    icons64:                 #null *ImageList
    spin:                    #null *ImageList
    defaultTypeFaceR:        #null *TypeFace
    defaultTypeFaceB:        #null *TypeFace
    defaultTypeFaceI:        #null *TypeFace
    defaultTypeFaceBI:       #null *TypeFace
    defaultFsTypeFaceR:      #null *TypeFace
    defaultFsTypeFaceB:      #null *TypeFace
    defaultFsTypeFaceI:      #null *TypeFace
    defaultFsTypeFaceBI:     #null *TypeFace
    fontDefault:             FontFamily
    fontDefaultFs:           FontFamily
}

struct Theme
{
    intialized:     bool
    res:            ThemeResources
    rects:          ThemeImageRects
    metrics:        ThemeMetrics
    colors:         ThemeColors
}

impl Theme
{
    private mtd freeDefault()
    {
        Memory.delete(.res.icons24)
        Memory.delete(.res.icons64)
        Memory.delete(.res.spin)
    }

    private mtd setupDefault(renderer: *RenderOgl)
    {
        .intialized = true
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

    // Initialize only the default fonts from the embedded font data.
    // This needs no renderer (glyph metrics are rasterized on the CPU), so it can
    // be used for headless/offscreen text measurement. Idempotent.
    public mtd setupDefaultFonts()
    {
        with me.res
        {
            if .defaultTypeFaceR do
                return

            catch createGuiTypeFace(&.defaultTypeFaceR, DefaultFontRegularName, DefaultFontRegular)
            catch createGuiTypeFace(&.defaultTypeFaceB, DefaultFontBoldName, DefaultFontBold)
            catch createGuiTypeFace(&.defaultTypeFaceI, DefaultFontItalicName, DefaultFontItalic)
            catch createGuiTypeFace(&.defaultTypeFaceBI, DefaultFontBoldItalicName, DefaultFontBoldItalic)

            catch createGuiTypeFace(&.defaultFsTypeFaceR, DefaultFontFsRegularName, DefaultFontFsRegular)
            catch createGuiTypeFace(&.defaultFsTypeFaceB, DefaultFontFsBoldName, DefaultFontFsBold)
            catch createGuiTypeFace(&.defaultFsTypeFaceI, DefaultFontFsItalicName, DefaultFontFsItalic)
            catch createGuiTypeFace(&.defaultFsTypeFaceBI, DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)

            .fontDefault.regular    = Font.create(assume .defaultTypeFaceR, me.metrics.defaultFontSize)
            .fontDefault.bold       = Font.create(assume .defaultTypeFaceB, me.metrics.defaultFontSize)
            .fontDefault.italic     = Font.create(assume .defaultTypeFaceI, me.metrics.defaultFontSize)
            .fontDefault.boldItalic = Font.create(assume .defaultTypeFaceBI, me.metrics.defaultFontSize)

            .fontDefaultFs.regular    = Font.create(assume .defaultFsTypeFaceR, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.bold       = Font.create(assume .defaultFsTypeFaceB, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.italic     = Font.create(assume .defaultFsTypeFaceI, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.boldItalic = Font.create(assume .defaultFsTypeFaceBI, me.metrics.defaultFixedFontSize)
        }
    }

    // Create a default font family with the given size
    mtd createDefaultFontfamily(size: u32)->FontFamily
    {
        var result: retval
        result.regular    = Font.create(assume .res.defaultTypeFaceR, size)
        result.bold       = Font.create(assume .res.defaultTypeFaceB, size)
        result.italic     = Font.create(assume .res.defaultTypeFaceI, size)
        result.boldItalic = Font.create(assume .res.defaultTypeFaceBI, size)
        return result
    }

    // Create a default font with the given size
    mtd createDefaultFont(size: u32, style = FontFamilyStyle.Regular)->*Font
    {
        #[Swag.Complete]
        switch style
        {
        case Regular:
            return Font.create(assume .res.defaultTypeFaceR, size)
        case Bold:
            return Font.create(assume .res.defaultTypeFaceB, size)
        case Italic:
            return Font.create(assume .res.defaultTypeFaceI, size)
        case BoldItalic:
            return Font.create(assume .res.defaultTypeFaceBI, size)
        }

        unreachable
    }

    // Create a default font (fixed size) with the given size
    mtd createDefaultFontFS(size: u32, style = FontFamilyStyle.Regular)->*Font
    {
        #[Swag.Complete]
        switch style
        {
        case Regular:
            return Font.create(assume .res.defaultFsTypeFaceR, size)
        case Bold:
            return Font.create(assume .res.defaultFsTypeFaceB, size)
        case Italic:
            return Font.create(assume .res.defaultFsTypeFaceI, size)
        case BoldItalic:
            return Font.create(assume .res.defaultFsTypeFaceBI, size)
        }

        unreachable
    }
}
