#global internal

using Core, Gui, Pixel

// The quiet controls standing above the columns: words with no ground of their own until the
// pointer comes. A menu ends on a faint chevron; a button acts at once.

// Height of the quiet controls of a column header.
const QuietHeight = 32.0

// Creates a quiet menu; a heading menu names what its column shows, in the text ink and bold.
func createQuietMenu(parent: *Wnd, id: WndId? = null, heading = false)->*IconButton
{
    with let result = IconButton.create(parent, {}, Math.Rectangle{0, 0, 0, QuietHeight}, id, flags: .CenterContent)
    {
        .setArrowPosition(.RightDownward)
        .setForm(.RoundedRectangle)
        if heading
        {
            .style.setFont(parent.theme().createDefaultFont(parent.themeMetrics().defaultFontSize, .Bold), .Regular)
            .style.addStyleSheetColors("btnIcon_Text $label_Text")
        }
    }

    return result
}

// Creates a quiet button: its words, acting at once.
func createQuietButton(parent: *Wnd, id: WndId? = null)->*IconButton
{
    with let result = IconButton.create(parent, {}, Math.Rectangle{0, 0, 0, QuietHeight}, id, flags: .CenterContent)
    {
        .setForm(.RoundedRectangle)
    }

    return result
}

// Writes `text` on a quiet menu or button and fits it to its words.
func setQuietText(control: *IconButton, text: string)
{
    control.setText(text)
    let metrics = control.themeMetrics()
    var width   = Painter.measureString(text, unwrap control.font().regular).width + 2 * metrics.btnIcon_SpacingTextH
    if control.arrowPosition != .None do
        width += themeDropDownButtonWidth(metrics) - themeActionButtonSize(metrics)
    control.resize(Math.ceil(width), control.position.height)
}
