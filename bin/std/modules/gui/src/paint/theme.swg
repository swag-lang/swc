#global public
using Core, Pixel

fileprivate const DefaultImageName = "theme/widgets.png"

fileprivate const DefaultFontRegularName = "theme/segoeui.ttf"
fileprivate const DefaultFontBoldName = "theme/segoeuib.ttf"
fileprivate const DefaultFontBoldItalicName = "theme/segoeuiz.ttf"
fileprivate const DefaultFontItalicName = "theme/segoeuii.ttf"

fileprivate const DefaultFontFsRegularName = "theme/consola.ttf"
fileprivate const DefaultFontFsBoldName = "theme/consolab.ttf"
fileprivate const DefaultFontFsBoldItalicName = "theme/consolaz.ttf"
fileprivate const DefaultFontFsItalicName = "theme/consolai.ttf"

fileprivate const DefaultIcons24Name = "theme/icons24.png"
fileprivate const DefaultIcons64Name = "theme/icons64.png"
fileprivate const DefaultSpinName = "theme/spin.png"

fileprivate const DefaultImage = #include(DefaultImageName)
fileprivate const DefaultFontRegular = #include(DefaultFontRegularName)
fileprivate const DefaultFontBold = #include(DefaultFontBoldName)
fileprivate const DefaultFontBoldItalic = #include(DefaultFontBoldItalicName)
fileprivate const DefaultFontItalic = #include(DefaultFontItalicName)
fileprivate const DefaultFontFsRegular = #include(DefaultFontFsRegularName)
fileprivate const DefaultFontFsBold = #include(DefaultFontFsBoldName)
fileprivate const DefaultFontFsBoldItalic = #include(DefaultFontFsBoldItalicName)
fileprivate const DefaultFontFsItalic = #include(DefaultFontFsItalicName)
fileprivate const DefaultIcons24 = #include(DefaultIcons24Name)
fileprivate const DefaultIcons64 = #include(DefaultIcons64Name)
fileprivate const DefaultSpin = #include(DefaultSpinName)

struct ThemeResources
{
    imgWidgets:              Texture
    icons24:                 *ImageList
    icons64:                 *ImageList
    spin:                    *ImageList
    defaultTypeFaceR:        *TypeFace
    defaultTypeFaceB:        *TypeFace
    defaultTypeFaceI:        *TypeFace
    defaultTypeFaceBI:       *TypeFace
    defaultFsTypeFaceR:      *TypeFace
    defaultFsTypeFaceB:      *TypeFace
    defaultFsTypeFaceI:      *TypeFace
    defaultFsTypeFaceBI:     *TypeFace
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
    fileprivate mtd freeDefault()
    {
        Memory.delete(.res.icons24)
        Memory.delete(.res.icons64)
        Memory.delete(.res.spin)
    }

    fileprivate mtd setupDefault(renderer: *RenderOgl)
    {
        .intialized = true
        .colors.setDark()

        with me.res
        {
            var img = assume Image.decode(DefaultImageName, DefaultImage)
            .imgWidgets = renderer.addImage(img)

            img      = assume Image.decode(DefaultIcons24Name, DefaultIcons24)
            .icons24 = Memory.new'ImageList()
            .icons24.set(renderer.addImage(img), 24, 24)

            img      = assume Image.decode(DefaultIcons64Name, DefaultIcons64)
            .icons64 = Memory.new'ImageList()
            .icons64.set(renderer.addImage(img), 64, 64)

            img   = assume Image.decode(DefaultSpinName, DefaultSpin)
            .spin = Memory.new'ImageList()
            .spin.set(renderer.addImage(img), 48, 48)

            .defaultTypeFaceR  = assume TypeFace.create(DefaultFontRegularName, DefaultFontRegular)
            .defaultTypeFaceB  = assume TypeFace.create(DefaultFontBoldName, DefaultFontBold)
            .defaultTypeFaceI  = assume TypeFace.create(DefaultFontItalicName, DefaultFontItalic)
            .defaultTypeFaceBI = assume TypeFace.create(DefaultFontBoldItalicName, DefaultFontBoldItalic)

            .defaultFsTypeFaceR  = assume TypeFace.create(DefaultFontFsRegularName, DefaultFontFsRegular)
            .defaultFsTypeFaceB  = assume TypeFace.create(DefaultFontFsBoldName, DefaultFontFsBold)
            .defaultFsTypeFaceI  = assume TypeFace.create(DefaultFontFsItalicName, DefaultFontFsItalic)
            .defaultFsTypeFaceBI = assume TypeFace.create(DefaultFontFsBoldItalicName, DefaultFontFsBoldItalic)

            .fontDefault.regular    = Font.create(.defaultTypeFaceR, me.metrics.defaultFontSize)
            .fontDefault.bold       = Font.create(.defaultTypeFaceB, me.metrics.defaultFontSize)
            .fontDefault.italic     = Font.create(.defaultTypeFaceI, me.metrics.defaultFontSize)
            .fontDefault.boldItalic = Font.create(.defaultTypeFaceBI, me.metrics.defaultFontSize)

            .fontDefaultFs.regular    = Font.create(.defaultFsTypeFaceR, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.bold       = Font.create(.defaultFsTypeFaceB, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.italic     = Font.create(.defaultFsTypeFaceI, me.metrics.defaultFixedFontSize)
            .fontDefaultFs.boldItalic = Font.create(.defaultFsTypeFaceBI, me.metrics.defaultFixedFontSize)
        }
    }

    // Create a default font family with the given size
    mtd createDefaultFontfamily(size: u32)->FontFamily
    {
        var result: retval
        result.regular    = Font.create(.res.defaultTypeFaceR, size)
        result.bold       = Font.create(.res.defaultTypeFaceB, size)
        result.italic     = Font.create(.res.defaultTypeFaceI, size)
        result.boldItalic = Font.create(.res.defaultTypeFaceBI, size)
        return result
    }

    // Create a default font with the given size
    mtd createDefaultFont(size: u32, style = FontFamilyStyle.Regular)->*Font
    {
        #[Swag.Complete]
        switch style
        {
        case Regular:
            return Font.create(.res.defaultTypeFaceR, size)
        case Bold:
            return Font.create(.res.defaultTypeFaceB, size)
        case Italic:
            return Font.create(.res.defaultTypeFaceI, size)
        case BoldItalic:
            return Font.create(.res.defaultTypeFaceBI, size)
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
            return Font.create(.res.defaultFsTypeFaceR, size)
        case Bold:
            return Font.create(.res.defaultFsTypeFaceB, size)
        case Italic:
            return Font.create(.res.defaultFsTypeFaceI, size)
        case BoldItalic:
            return Font.create(.res.defaultFsTypeFaceBI, size)
        }

        unreachable
    }
}
