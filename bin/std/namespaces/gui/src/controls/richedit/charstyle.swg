#global public

using Core, Pixel

// Indexes [[Gui.RichEditCtrl.styles]]; a lexer assigns one to every rune.
alias RichEditStyleRef = u8

// Describes foreground, background, face, and underline styling for one text run.
struct RichEditRuneStyle
{
    public
    {
        colBk: Color                            // Background color, or transparent for none.
        colFg: Color                            // Text color.
        fontMode  = FontFamilyStyle.Regular     // Face the run is drawn with.
        underline = UnderlineStyle.None         // Underline drawn under the run.
    }
}
