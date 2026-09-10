using Core, Gui

// A panel holding a heading, a field form, and one trailing row of actions.
//
// The card is a raised surface, not a framed box: [[Gui.BackgroundStyle.Panel]] gives its fill the
// theme's slight standalone corner, so nothing has to be drawn around it or between its parts.
// The form panels of the main window share this shape, and only their fields differ.
struct VaultCard
{
    late panel:    *StackLayoutCtrl
    late body:     *StackLayoutCtrl
    late form:     *FormLayoutCtrl
    late actions:  *StackLayoutCtrl
    late title:    *Label
    late subtitle: *Label
}

impl VaultCard
{
    func create(parent: *Wnd, title, subtitle: string)->VaultCard
    {
        let panel = StackLayoutCtrl.create(parent, .Top)
        panel.spacing         = 0
        panel.backgroundStyle = .Panel
        panel.padding         = {28, 24, 28, 24}

        let titleLabel = Label.create(panel, title, {0, 0, 0, 30})
        titleLabel.setTextAlignment(.Left, .Center)
        titleLabel.style.setFont(panel.theme().createDefaultFont(20, .Bold), .Regular)

        // The explanation wraps, so its height is the text's to decide: a hand-tuned one
        // cuts the last line off as soon as the sentence is said in more words.
        let subtitleLabel = Label.create(panel, subtitle, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
        subtitleLabel.margin = {0, 4, 0, 0}
        subtitleLabel.setTextAlignment(.Left, .Top)
        subtitleLabel.setLineGap(cast(s32) (panel.themeMetrics().dialog_BtnPadding / 2))

        // Center shorter forms and their actions together within the shared page height.
        let body = StackLayoutCtrl.create(panel, .VerticalCenter)
        body.layoutSpec.policyY = .Expand
        body.backgroundStyle    = .Transparent
        body.margin             = {0, panel.themeMetrics().dialog_BtnPadding * 2, 0, 0}
        body.spacing            = panel.themeMetrics().dialog_BtnPadding * 2

        let form    = FormLayoutCtrl.create(body, VaultForm.options(body))
        let actions = StackLayoutCtrl.create(body, .Right, {0, 0, 0, panel.themeMetrics().btnPush_Height})
        form.layoutSpec.policyX    = .Expand
        actions.layoutSpec.policyX = .Expand
        actions.spacing            = panel.themeMetrics().dialog_BtnPadding
        panel.applyLayout()
        return {panel, body, form, actions, titleLabel, subtitleLabel}
    }

    // Replaces the heading and the explanation, then re-arranges what they now need.
    mtd setTexts(title, subtitle: string)
    {
        .title.setText(title)
        .subtitle.setText(subtitle)
        .panel.computeLayout()
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
        .actions.show(not .actions.children.isEmpty())
        .form.show(not .form.rows.isEmpty())
        VaultForm.finish(.form)
        .panel.computeLayout()
        .body.computeLayout()
        .form.computeLayout()
    }
}
