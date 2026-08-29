#global public

using Pixel

// The colors of the Swag identity.
//
// They are constants rather than palette tokens because they are not a decision a theme makes:
// a theme that changes them is a theme of its own, and the shipped Swag palette, the product
// marks and the generated documentation all have to be cut from the same three numbers or the
// family stops being one.
//
// Voltage is the signature and Arc is the second tone; both are blocks that carry Ink, and both
// keep their value whichever way up the theme is read. What a mode changes is only what each
// one may point with — see [[Gui.ThemeTone]].
const Voltage: Color = 0xFFF7F900     // The signature: what to do, what is active, where the focus is.
const Arc:     Color = 0xFF38BDF8     // The second tone: another place, another kind, a link.
const Ink:     Color = 0xFF0B0B0D     // The ink every block of the two carries, and the dark ground.

// One color of a theme, in the three roles a color is ever used in.
//
// A theme never really has "a color". It has something to *point* with — a rail, a ring, a rule,
// a glyph, a word — something to *fill* with, and the ink that fill carries. Asking for the three
// together is what makes a tone impossible to half-answer, and what lets a palette hand the same
// color to all three when it can.
//
// The three parting company is not an edge case: a bright block can vanish as a hairline on a
// bright ground, so [[Gui.ThemeColors.apply]] deepens its mark while leaving the block untouched.
// See [[Gui.ThemeTone.mark]].
struct ThemeTone
{
    public
    {
        // What the tone points with: a rail, a ring, a rule, a mark, a word.
        //
        // A palette normally writes its block here and lets `apply` deepen it until it reads on
        // the grounds of the theme, which is how one written color answers in both modes. Writing
        // a color that already reads keeps it: a status tone whose ink is nothing like its band
        // says so by naming both.
        mark: Color

        ground:   Color     // The block the tone fills.
        onGround: Color     // The ink drawn on that block.
    }
}

impl ThemeTone
{
    // A tone that fills with `block`, writes `ink` on it, and points with `block` until the
    // theme has to deepen it.
    func from(block, ink: Color)->ThemeTone
    {
        return {block, block, ink}
    }
}

// The decisions a theme actually makes.
//
// [[Gui.ThemeColors]] carries one value per painted part, which is what a widget needs and
// what a designer must never be asked to fill in: three hundred values written by hand are
// three hundred chances to answer for a control in one mode and forget it in the other,
// and that is exactly the defect a reader sees — a light theme keeping the blue hover of
// the palette it was derived from.
//
// A palette is the short answer instead. Every semantic color is derived from these tokens
// by [[Gui.ThemeColors.apply]], so a theme is complete by construction: there is no value
// it can leave unanswered, and the same rule produces the same relationship in every theme.
// A theme that wants one part different still says so afterwards, through a theme sheet.
//
// The tokens are grouped by what they decide: where the reader is looking (grounds), what
// separates things (rules), what is written (ink), and which of a closed set of tones a thing
// belongs to.
struct ThemePalette
{
    public
    {
        // Grounds, from the one furthest behind the reader's attention to the one nearest it.
        // A theme that gives two of them the same value simply flattens that step; nothing
        // downstream has to know.
        ground:         Color     // The application background, and the ground a window sits on.
        view:           Color     // A document, a list, a canvas: the ground content is read on.
        panel:          Color     // A dialog, a menu, a side panel, or another structural panel.
        informationBar: Color     // A band reporting identity, context, or status beside the content.
        commandBar:     Color     // The application-wide commands framing the top of the content.
        toolBar:        Color     // Contextual tools framing another edge of the content.
        raised:         Color     // The fill of a control that has one: a button, a field, a combo.
        hot:            Color     // The fill of a control under the pointer.
        pressed:        Color     // The fill of a control under the press.

        // The ground of a row, an entry or a tab the pointer is over, and of one that is
        // selected. These are where a theme spends most of its color, because a list, a menu
        // and a tab bar are where a reader spends most of their time — which is why they are
        // washed with the alternate tone rather than with the signature: a row washed in a
        // color that means "do this" says the wrong thing, and a row washed in Voltage cannot
        // be read at all.
        selectHot:     Color     // Ground of a row, entry, or tab under the pointer.
        selectPressed: Color     // Ground of a selected row, entry, or tab.

        // Rules. `line` divides two blocks of one surface; `controlLine` draws the edge of a
        // control, and is therefore the stronger of the two: a control has to read as an object
        // the reader can act on, a divider only has to be found when looked for.
        line:        Color     // Divider between two blocks of one surface.
        controlLine: Color     // Stronger outline separating an interactive control.

        // Ink, by decreasing emphasis. `disabled` is the ink and the rule of everything the
        // reader cannot act on; it must stay legible, because it says unavailable, not absent.
        text:      Color     // Primary ink.
        softText:  Color     // Secondary ink.
        faintText: Color     // Low-emphasis ink.
        disabled:  Color     // Ink and rules of unavailable controls.

        // The tones, which are the whole color vocabulary of the theme. There are five, there
        // is no sixth, and each one says something no other one says.
        //
        // The two above the line are what the theme is recognized by. Their three roles keep the
        // identity coherent when a mark and its block need different contrast.
        // The three below the line are what happened, and they adapt freely: a notice has to be
        // read before it has to be recognized.
        signature: ThemeTone     // The one tone that says act, active, focused. Spent scarcely.
        alternate: ThemeTone     // The second place, the second kind: a link, a mode, a selection.
        critical:  ThemeTone     // Something stopped.
        caution:   ThemeTone     // Something needs attention.
        info:      ThemeTone     // Something is worth knowing.

        // Whether the theme marks the active item — a checked tool, the open menu, the selected
        // row — with a rule in the signature, or by filling the item instead. It is a decision,
        // not a color: a rail drawn in anything other than the signature says the item is active
        // in a language the rest of the interface does not speak. Changing the signature
        // therefore moves the rail with it, which is the whole reason this is not a color.
        railed: bool

        // The three slots rich text addresses with `<p1>`, `<p2>` and `<p3>`, in labels and in
        // every other rich string the theme formats.
        rich1: Color     // First rich-text palette slot.
        rich2: Color     // Second rich-text palette slot.
        rich3: Color     // Third rich-text palette slot.

        // Ink a translucent veil is made of: white over a dark ground, black over a light one.
        // Every overlay of the theme is this color at one of three strengths, which is why a
        // veil never has to be re-tuned per widget.
        veil: Color

        // Ink of a drop shadow. Its alpha is the darkening the shadow reaches where it meets
        // the body it is cast by, not the alpha of any one ring.
        shadow: Color

        // Chrome of a window. The outline is opaque by contract: the same stroke runs past the
        // caption ground and the body ground, so a translucent value takes both of them on and
        // visibly changes tone at the caption seam.
        caption:         Color     // Caption band of the active window.
        captionInactive: Color     // Caption band of a window that does not have the focus.
        windowBorder:    Color     // Outline separating the whole surface from the desktop.

        // How far the caption band travels toward the signature block at the edge that carries
        // the mark, from zero for a flat band.
        //
        // It is a decision rather than a color, and nothing else predicts it: `railed` says how
        // the active item is marked, not whether the chrome is tinted. A theme that follows the
        // desktop keeps its caption flat; a theme that carries a brand lights the band from its
        // own mark.
        //
        // The band is the one surface of a window with no content to carry, which is what lets
        // it carry the focus instead: an active window glows and an inactive one is flat, where
        // two grounds ten levels apart reported nothing across a desktop.
        //
        // The number is a mix, not a perceived amount, and the two do not track each other: a
        // wash toward a color darker than the band is spent on luminance, which the eye reads at
        // once, and a wash toward one as light as the band is spent on chroma, which costs three
        // times as much mix to reach the same weight. A light theme therefore asks for a much
        // larger number than a dark one for a band of the same strength, and a light theme that
        // copied the dark number shipped a caption nobody could see.
        captionGlow: f32
    }
}
