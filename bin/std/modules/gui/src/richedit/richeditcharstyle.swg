#global public

using Core, Pixel

// Names the rich edit style ref type.
alias RichEditStyleRef = u8

// Describes foreground, background, face, and underline styling for one text run.
struct RichEditRuneStyle
{
    colBk: Color                            // Col bk associated with this value.
    colFg: Color                            // Col fg associated with this value.
    fontMode  = FontFamilyStyle.Regular     // Font mode associated with this value.
    underline = UnderlineStyle.None         // Underline associated with this value.
}
