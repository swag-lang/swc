using Core, Gui

// A panel holding a heading, a field form, and one trailing row of actions.
//
// The card is a raised surface, not a framed box: it is told apart from the ground by its own
// fill, so nothing has to be drawn around it or between its parts. The form panels of the main
// window share this shape, and only their fields differ.
struct VaultCard
{
    panel:    *Wnd             = undefined
    body:     *Wnd             = undefined
    form:     *FormLayoutCtrl  = undefined
    actions:  *StackLayoutCtrl = undefined
    title:    *Label           = undefined
    subtitle: *Label           = undefined
}

impl VaultCard
{
    func create(parent: *Wnd, title, subtitle: string)->VaultCard
    {
        let panel = Wnd.create'Wnd(parent)
        panel.backgroundStyle = .Window
        panel.padding         = {28, 24, 28, 24}

        let titleLabel = Label.create(panel, title, {0, 0, 0, 30})
        titleLabel.dockStyle = .Top
        titleLabel.setTextAlignment(.Left, .Center)
        titleLabel.style.setFont(panel.theme().createDefaultFont(20, .Bold), .Regular)

        // The explanation wraps, so its height is the text's to decide: a hand-tuned one
        // cuts the last line off as soon as the sentence is said in more words.
        let subtitleLabel = Label.create(panel, subtitle, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        subtitleLabel.dockStyle = .Top
        subtitleLabel.margin    = {0, 4, 0, 0}
        subtitleLabel.setTextAlignment(.Left, .Top)

        let actions = StackLayoutCtrl.create(panel, .Right, {0, 0, 0, 36})
        actions.dockStyle = .Bottom
        actions.spacing   = 8

        let body = Wnd.create'Wnd(panel)
        body.dockStyle       = .Center
        body.backgroundStyle = .Transparent
        body.margin          = {0, 24, 0, 24}

        // A field label names its field; it is not a heading. Small, bold, and quiet keeps it
        // under the prose above it and under the value the field will hold. The smaller face
        // also needs less room than the theme reserves for a label at body size.
        with var options: FormLayoutOptions
        {
            .labelHeight  = 18
            .labelSpacing = 6
            .rowSpacing   = 22
            .helpHeight   = 40
            .labelFont    = panel.theme().createDefaultFont(12, .Bold)
            .labelFlags   = .SecondaryText
        }

        let form = FormLayoutCtrl.create(body, options)
        form.dockStyle = .Top
        panel.applyLayout()
        return {panel, body, form, actions, titleLabel, subtitleLabel}
    }

    // Replaces the heading and the explanation, then re-arranges what they now need.
    mtd setTexts(title, subtitle: string)
    {
        .title.setText(title)
        .subtitle.setText(subtitle)
        .panel.applyLayout()
    }

    // Arranges the body around the filled form, then the rows inside it.
    //
    // Call it once the fields and the trailing controls of the card are all present, and again
    // after a language switch. The form answers for its own height, so nothing here has to be
    // told what that height is — but a row has to be arranged again even when the form's box did
    // not move, which is exactly what a re-labelled control does: the band stays the same size
    // and the caption inside it needs more room. `FormLayoutCtrl` only re-arranges on a resize,
    // so the pass is asked for here rather than waited for.
    mtd endForm()
    {
        .body.applyLayout()
        .form.computeLayout()
    }
}
