#global public

// Fonts that represent the regular, bold, italic, and bold-italic faces of one family.
//
// A style slot may be `null`. [[Pixel.FontFamily.getFont]] falls back to an
// available compatible slot when the requested face is absent.
struct FontFamily
{
    public
    {
        regular:    *Font?     // Regular face, when available.
        bold:       *Font?     // Bold face, when available.
        italic:     *Font?     // Italic face, when available.
        boldItalic: *Font?     // Combined bold and italic face, when available.
        light:      *Font?     // Light face, for a large figure read at a glance, when available.
        semiBold:   *Font?     // Semibold face, for a name that leads a row, when available.
    }
}

// Style slot within a [[Pixel.FontFamily]].
enum FontFamilyStyle
{
    Regular        // Upright text with normal weight.
    Bold           // Upright text with bold weight.
    Italic         // Slanted text with normal weight.
    BoldItalic     // Slanted text with bold weight.
    Light          // Upright text lighter than regular.
    SemiBold       // Upright text between regular and bold.
}

// Font-family styles in enum order, for settings and other ordinal-indexed mappings.
const FontFamilyStyleValues: [6] FontFamilyStyle = [
    .Regular, .Bold, .Italic, .BoldItalic, .Light, .SemiBold]

impl FontFamily
{
    // Returns the font of the requested style, falling back to the closest available face.
    //
    // Bold-italic falls back to italic, then bold, then regular; semibold falls back to bold,
    // then regular; bold, italic and light fall back to regular. Returns `null` when no candidate
    // slot is set.
    mtd const getFont(style: FontFamilyStyle)->*Font?
    {
        switch style
        {
        case .Regular:
            if .regular
            {
                return .regular
            }

        case .Bold:
            if .bold
            {
                return .bold
            }

            if .regular
            {
                return .regular
            }

        case .Italic:
            if .italic
            {
                return .italic
            }

            if .regular
            {
                return .regular
            }

        case .BoldItalic:
            if .boldItalic
            {
                return .boldItalic
            }

            if .italic
            {
                return .italic
            }

            if .bold
            {
                return .bold
            }

            if .regular
            {
                return .regular
            }

        case .Light:
            if .light
            {
                return .light
            }

            if .regular
            {
                return .regular
            }

        case .SemiBold:
            if .semiBold
            {
                return .semiBold
            }

            if .bold
            {
                return .bold
            }

            if .regular
            {
                return .regular
            }
        }

        return null
    }

    // Assigns a font to the given style slot.
    mtd setFont(fnt: *Font, style: FontFamilyStyle)
    {
        switch style
        {
        case .Regular:    .regular = fnt
        case .Bold:       .bold = fnt
        case .Italic:     .italic = fnt
        case .BoldItalic: .boldItalic = fnt
        case .Light:      .light = fnt
        case .SemiBold:   .semiBold = fnt
        }
    }
}
