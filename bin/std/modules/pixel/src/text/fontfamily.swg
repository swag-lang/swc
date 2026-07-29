#global public

// Fonts that represent the regular, bold, italic, and bold-italic faces of one family.
//
// A style slot may be `null`. [[Pixel.FontFamily.getFont]] falls back to an
// available compatible slot when the requested face is absent.
struct FontFamily
{
    regular:    #null *Font // Regular face, when available.
    bold:       #null *Font // Bold face, when available.
    italic:     #null *Font // Italic face, when available.
    boldItalic: #null *Font // Combined bold and italic face, when available.
}

// Style slot within a [[Pixel.FontFamily]].
enum FontFamilyStyle
{
    Regular    // Upright text with normal weight.
    Bold       // Upright text with bold weight.
    Italic     // Slanted text with normal weight.
    BoldItalic // Slanted text with bold weight.
}

impl FontFamily
{
    // Get the font corresponding to the style.
    // If not evailable, get another one.
    mtd const getFont(style: FontFamilyStyle)->#null *Font
    {
        switch style
        {
        case .Regular:
            if .regular do
                return .regular

        case .Bold:
            if .bold do
                return .bold
            if .regular do
                return .regular

        case .Italic:
            if .italic do
                return .italic
            if .regular do
                return .regular

        case .BoldItalic:
            if .boldItalic do
                return .boldItalic
            if .italic do
                return .italic
            if .bold do
                return .bold
            if .regular do
                return .regular
        }

        return null
    }

    // Set the font corresponding to a given style.
    mtd setFont(fnt: *Font, style: FontFamilyStyle)
    {
        switch style
        {
        case .Regular:    .regular = fnt
        case .Bold:       .bold = fnt
        case .Italic:     .italic = fnt
        case .BoldItalic: .boldItalic = fnt
        }
    }
}
