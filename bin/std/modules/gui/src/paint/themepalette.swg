#global public

using Pixel

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
// separates things (rules), what is written (ink), what matters (accent), and what went
// wrong (status).
struct ThemePalette
{
    // Grounds, from the one furthest behind the reader's attention to the one nearest it.
    // A theme that gives two of them the same value simply flattens that step; nothing
    // downstream has to know.
    ground:  Color     // The application background, and the ground a window sits on.
    view:    Color     // A document, a list, a canvas: the ground content is read on.
    panel:   Color     // A raised band: a dialog, a header, a menu, a tool bar.
    raised:  Color     // The fill of a control that has one: a button, a field, a combo.
    hot:     Color     // The fill of a control under the pointer.
    pressed: Color     // The fill of a control under the press.

    // The ground of a row, an entry or a tab the pointer is over, and of one that is
    // selected. A palette built on a system accent washes them with it; a palette whose
    // accent is a brand color cannot — a row washed in Voltage is unreadable — and repeats
    // `hot` and `pressed` instead. Keeping the two pairs apart is what lets both work.
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

    // The one color the interface spends on what matters, in its two roles, and the ink drawn
    // on a fill of it. Every accented part of every widget comes from these three values.
    //
    // `accent` is what the theme *points* with — a rail, a ring, a rule, a mark — so it has to
    // stay legible as a hairline on the grounds above. `accentGround` is the block it *fills*
    // to say "this is the thing to do", and carries `onAccent` as its ink.
    //
    // Nearly every theme gives the two the same value, and then this is one decision written
    // twice. A brand accent is where they part: Voltage fills beautifully under ink and
    // vanishes as a hairline on paper, so the light Swag palette points in ink and still fills
    // in Voltage. That is what keeps the two modes one identity rather than two.
    accent:       Color     // Accent used for rails, rings, rules, and marks.
    accentGround: Color     // Accent used as a filled ground.
    onAccent:     Color     // Ink drawn on the accent ground.

    // Whether the theme marks the active item — a checked tool, the open menu, the selected
    // row — with a rule in the accent, or by filling the item instead. It is a decision, not
    // a color: a rail drawn in anything other than the accent says the item is active in a
    // language the rest of the interface does not speak. Changing the accent therefore moves
    // the rail with it, which is the whole reason this is not a color of its own.
    railed: bool

    // Status. `error` is ink; the three notice grounds each carry the ink written on them.
    // They are tokens rather than derivations because a notice has to be recognized before
    // it is read, and that recognition is a hue, not a step of lightness.
    error:        Color     // Error ink.
    criticalBk:   Color     // Ground of a critical notice.
    criticalText: Color     // Ink of a critical notice.
    infoBk:       Color     // Ground of an informational notice.
    infoText:     Color     // Ink of an informational notice.
    noticeBk:     Color     // Ground of a general notice.
    noticeText:   Color     // Ink of a general notice.

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

    // How much of the accent the caption band takes at the edge that carries the mark, from
    // zero for a flat band.
    //
    // It is a decision rather than a color, and nothing else predicts it: `railed` says how the
    // active item is marked, not whether the chrome is tinted. A theme that follows the desktop
    // keeps its caption flat; a theme that carries a brand lights the band from its own mark.
    //
    // The band is the one surface of a window with no content to carry, which is what lets it
    // carry the focus instead: an active window glows and an inactive one is flat, where two
    // grounds ten levels apart reported nothing across a desktop.
    captionGlow: f32
}
