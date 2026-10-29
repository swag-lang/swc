#global public

using Pixel

// The colors of the Swag identity.
//
// They are constants rather than palette tokens because they are not a decision a theme makes:
// a theme that changes them is a theme of its own, and the two shipped palettes, the product
// marks and the generated documentation all have to be cut from the same numbers or the family
// stops being one.
//
// Voltage acts and Arc chooses. Voltage keeps its value in both themes, but Papier never writes
// with it: on paper the action is the same button turned over, ink on paper. Arc is deepened on
// paper so that it can be read as a word. See [[Gui.ThemeColors.encrePalette]] and
// [[Gui.ThemeColors.papierPalette]].
const Voltage: Color = 0xFFF7F900     // The signature: what is being done, and where the reader acts.
const Arc:     Color = 0xFF38BDF8     // The second tone: what is chosen, elsewhere, on or in progress.
const Ink:     Color = 0xFF0B0B0D     // The ink tile of the product mark, which its Voltage glyph is cut from.

// One color of a theme, in the three roles a color is ever used in.
//
// A theme never really has "a color". It has something to *point* with — a ring, a rule, a glyph,
// a word — something to *fill* with, and the ink that fill carries. Asking for the three together
// is what makes a tone impossible to half-answer, and what lets a palette hand the same color to
// all three when it can.
//
// The three parting company is not an edge case: a bright block can vanish as a hairline on a
// bright ground, so [[Gui.ThemeColors.apply]] deepens its mark while leaving the block untouched.
// See [[Gui.ThemeTone.mark]].
struct ThemeTone
{
    public
    {
        // What the tone points with: a ring, a rule, a dot, a glyph, a word.
        //
        // A palette normally writes its block here and lets `apply` deepen it until it reads on
        // the grounds of the theme, which is how one written color answers in both modes. Writing
        // a color that already reads keeps it: a status tone whose ink is nothing like its tinted
        // ground says so by naming both.
        mark: Color

        ground:   Color     // The block the tone fills.
        onGround: Color     // The ink drawn on that block.
    }
}

impl ThemeTone
{
    // Returns a tone that fills with `block`, writes `ink` on it, and points with `block` until the theme has to deepen it.
    func from(block, ink: Color)->ThemeTone => ThemeTone{block, block, ink}
}

// The decisions a theme actually makes.
//
// [[Gui.ThemeColors]] carries one value per painted part, which is what a widget needs and
// what a designer must never be asked to fill in: three hundred values written by hand are
// three hundred chances to answer for a control in one mode and forget it in the other.
//
// A palette is the short answer instead. Every semantic color is derived from these tokens by
// [[Gui.ThemeColors.apply]], so a theme is complete by construction: there is no value it can
// leave unanswered, and the same rule produces the same relationship in every theme. A theme
// that wants one part different still says so afterwards, through a theme sheet.
//
// The tokens are the ones the Silence charter names, grouped by what they decide: where the
// reader is looking (grounds), what separates things (the line), what is written (ink), what
// acts and what is chosen (the two identity tones), and what happened (the status tones).
struct ThemePalette
{
    public
    {
        // Grounds, from the one furthest behind the reader's attention to the one nearest it.
        ground:  Color     // The window and the document read in it.
        surface: Color     // Floating surfaces: a lens, a sheet, an inspector, a dialog, a menu, a popover.
        raised:  Color     // The ground under the pointer, a pressed control, the track of a slider or a progress.

        // The hairline edge of a field, a card or a separator. Every stronger rule of the theme —
        // a hovered field, the ring of an unchecked box, a scroll bar thumb — is derived from it
        // and from the faint ink, so the two always travel together.
        line: Color

        // Ink, by decreasing emphasis. Disabled ink is derived: the charter states it as an
        // opacity, not as a fourth color.
        text:      Color     // Body text.
        softText:  Color     // Secondary text and labels.
        faintText: Color     // Captions, units, hints, line numbers in prose.

        // What acts: the primary action, the keyboard focus ring, the caret.
        //
        // On Encre it is a Voltage block carrying ink; on Papier the same button turned over, an
        // ink block carrying paper, because Voltage is never written on paper.
        signature: ThemeTone

        // What is chosen, elsewhere, on or in progress: a checked box, a switch that is on, a
        // slider and a progress fill, the underline of the active tab. Its ink is what a check
        // mark is drawn in on an Arc box.
        alternate: ThemeTone

        link:      Color     // Link text: Arc lifted on Encre, deepened on Papier.
        selection: Color     // Ground of a selected row, thumbnail, segment, or of a menu entry under the pointer.
        highlight: Color     // Ground of search occurrences and matched characters.

        // The occurrence the reader is on. Encre fills it with Voltage; Papier keeps the highlight
        // ground and marks it with an ink underline, because Voltage is never written on paper.
        currentMatch: ThemeTone

        // Ground of the chosen segment of a toggle group. Encre washes it in the selection; Papier
        // lifts it white out of the raised frame, where a blue wash would read as a second accent.
        segment: Color

        // A tool tip: its ground, its ink, and the hairline around it. Encre writes it on the
        // surface; Papier turns it over, ink with paper text, so it never vanishes on white.
        tip: ThemeTone

        // The status tones. Each points with a mark, tints a ground for a notice, and writes the
        // notice in `onGround`. Information uses Arc.
        critical: ThemeTone     // Something stopped.
        caution:  ThemeTone     // Something needs attention.
        info:     ThemeTone     // Something is worth knowing.

        // The mark of something running now, such as a mounted drive: a dot beside its name. It is
        // not a status tone, so it tints no ground and writes no notice; it says "live" where a ring
        // says "at rest".
        live: Color

        // The quiet hue of each kind of file, carried by its glyph alone in a listing, so a reader
        // tells a picture from a film before reading a name. Low in chroma, distinct from Arc and
        // from the status tones; folders and plain files keep the neutral inks.
        kindImage:    Color     // Glyph of a picture.
        kindVideo:    Color     // Glyph of a film.
        kindAudio:    Color     // Glyph of a sound.
        kindCode:     Color     // Glyph of source code or structured data.
        kindDocument: Color     // Glyph of a paged document, such as a PDF.
        kindArchive:  Color     // Glyph of an archive.

        // The three slots rich text addresses with `<p1>`, `<p2>` and `<p3>`, in labels and in
        // every other rich string the theme formats.
        rich1: Color     // First rich-text palette slot.
        rich2: Color     // Second rich-text palette slot.
        rich3: Color     // Third rich-text palette slot.

        // Hues that tell a few series apart — the tracks of a piece, the channels of a recording —
        // where nothing is chosen and nothing acts. The first is Arc; the others keep its weight.
        series: [4] Color

        // Ink a translucent veil is made of: white over a dark ground, black over a light one.
        // Every overlay of the theme is this color at one of three strengths, which is why a
        // veil never has to be re-tuned per widget.
        veil: Color

        // Ink of the shadow a floating surface casts. Its alpha is the darkening the shadow reaches
        // where it meets the surface; nothing but a floating surface casts one.
        shadow: Color
    }
}
