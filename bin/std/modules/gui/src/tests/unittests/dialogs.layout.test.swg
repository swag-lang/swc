#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Predefined dialogs fit their common chrome around the content instead of keeping stale blank rows.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    var options: EditDlgOptions
    options.title   = "Rename"
    options.message = "Enter the new name."
    let dlg = EditDlg.createSingleLine(&host.surface, options)

    @assert(dlg.surface!.flags.has(.SmallCaption))
    @assert(dlg.label.preferredSize.y < 40)
    @assert(Math.abs(dlg.label.margin.w - dlg.themeMetrics().dialog_BtnPadding) < 0.5)
    let metrics       = dlg.themeMetrics()
    let contentHeight = dlg.edit!.position.height + dlg.label.position.height + dlg.label.margin.w
    var expected      = contentHeight + 2 * metrics.dialog_Padding + dlg.buttonBar.position.height + 2 * metrics.wnd_BorderSize
    expected += metrics.wnd_SmallCaptionCY + 2 * dlg.surface!.shadowMargin()
    @assert(Math.abs(dlg.surface!.position.height - Math.ceil(expected) * dlg.surface!.dpiScale) < 1.5)
}

// A prompt is as tall as its explanation, not as tall as the shell it opened in.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    var options: EditDlgOptions
    options.title   = "Rename"
    options.message = "Enter the new name."
    let short = EditDlg.createSingleLine(&host.surface, options)

    options.message = "Enter the new name. It has to be unique inside this folder, and it keeps the extension the file already carries, so a name typed without one is completed."
    let long = EditDlg.createSingleLine(&host.surface, options)

    @assert(long.surface!.position.height > short.surface!.position.height)
    @assert(long.label.itf.measureContent({long.label.position.width, 0}).y <= long.label.position.height + 0.5)

    short.surface!.destroy()
    long.surface!.destroy()
    host.pump()
}

// Fitting a resizable editor preserves the authored editor height and makes it the minimum.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    var options: EditDlgOptions
    options.title        = "Description"
    options.editorHeight = 150
    let dlg = EditDlg.createMultiLine(&host.surface, options)

    @assert(dlg.label.name.raw == strings().dlg_MultiLineHint)
    @assert(dlg.label.position.bottom() <= dlg.richEdit!.position.y + 0.5)
    let metrics       = dlg.themeMetrics()
    let contentHeight = dlg.richEdit!.position.height + dlg.label.position.height + dlg.label.margin.w
    let visibleHeight = contentHeight + 2 * metrics.dialog_Padding + dlg.buttonBar.position.height + 2 * metrics.wnd_BorderSize + metrics.wnd_SmallCaptionCY
    let outerHeight   = visibleHeight + 2 * dlg.surface!.shadowMargin()
    @assert(Math.abs(dlg.richEdit!.position.height - cast(f32) options.editorHeight) < 0.5)
    @assert(Math.abs(dlg.surface!.position.height - Math.ceil(outerHeight) * dlg.surface!.dpiScale) < 1.5)
    @assert(Math.abs(dlg.surface!.minSize.y - dlg.surface!.position.height / dlg.surface!.dpiScale) < 0.5)
}

// The default about box measures its identity block instead of retaining the old 300-unit shell.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let params = AboutDlgParams{
        surfaceTitle: "About",
        contentTitle: "Swag",
        message: "A systems programming language.",
        surfaceIcon: {},
        contentIcon: {}}
    let dlg = AboutDlg.create(&host.surface, params)

    let metrics       = dlg.themeMetrics()
    var contentHeight = dlg.labelMessageTitle.measure({dlg.labelMessageTitle.position.width, 0}).preferred.y
    contentHeight += dlg.labelMessage.measure({dlg.labelMessage.position.width, 0}).preferred.y
    contentHeight += metrics.dialog_BtnPadding * 2
    var expected = contentHeight + 2 * metrics.dialog_Padding + dlg.buttonBar.position.height + 2 * metrics.wnd_BorderSize
    expected += metrics.wnd_SmallCaptionCY + 2 * dlg.surface!.shadowMargin()
    @assert(Math.abs(dlg.surface!.position.height - Math.ceil(expected) * dlg.surface!.dpiScale) < 0.5)
}

// A question is as wide as its actions need, and never narrower than the family's floor.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    // Short actions: the box opens at the floor instead of closing in on three small buttons
    // until the bar is the whole box.
    let small = MessageDlg.create(&host.surface, "Save changes?")
    small.addButton("Yes", Dialog.BtnYes)
    small.addButton("No", Dialog.BtnNo)
    small.addButton("Cancel", Dialog.BtnCancel, true)
    small.adaptSizeToMessage()
    @assert(Math.abs(small.surface!.size().x - (MessageDlg.MinMessageWidth + 2 * small.surface!.shadowMargin())) < 1)

    // Long actions: the bar decides, and no invisible button is reserved beside them.
    let wide = MessageDlg.create(&host.surface, "Save changes?")
    wide.addButton("Save the document", Dialog.BtnYes)
    wide.addButton("Discard the changes", Dialog.BtnNo)
    wide.addButton("Keep editing", Dialog.BtnCancel, true)
    wide.adaptSizeToMessage()

    let metrics  = wide.themeMetrics()
    var expected = 2 * metrics.dialog_Padding + 2 * metrics.wnd_BorderSize
    for btn in wide.buttons do
        expected += btn.position.width
    expected += cast(f32) (wide.buttons.count - 1) * metrics.dialog_BtnPadding
    @assert(expected > MessageDlg.MinMessageWidth)
    @assert(Math.abs(wide.surface!.size().x - (expected + 2 * wide.surface!.shadowMargin())) < 1)

    small.surface!.destroy()
    wide.surface!.destroy()
    host.pump()
}

// A message box holds the message it was fitted to, whatever that message measures.
//
// The box takes the extent of its own text as its width, and that extent is fractional: the
// window tree is laid out on whole logical units and the window itself is placed on whole
// physical pixels. Committed as measured, the width came back a fraction short, the message
// wrapped one line more than the box had been made tall for, and the box clipped the very text
// it was fitted to. Only some lengths land on a losing fraction, so the case is swept instead
// of picked — a two-sentence error box was one of them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600, 1.5)
    defer host.shutdown()

    // One glyph more each round, which walks the fractional part of the measured width across
    // the whole range a rounding can lose.
    var tail: String
    while tail.length < 12
    {
        var message = String.from("Unable to mount the virtual disk.\n\nThe password is incorrect or the container is damaged")
        message += tail
        message += "."

        let dlg = MessageDlg.create(&host.surface, message.toString())
        dlg.addButton("Ok", Dialog.BtnOk, true)

        // A headless surface has no monitor to take a scale from, so the dialog would measure at
        // one and never meet the rounding a scaled display makes it face.
        dlg.surface!.setDpiScaleRaw(1.5)
        dlg.adaptSizeToMessage()

        let needed = dlg.label.itf.measureContent({dlg.label.position.width, 0}).y
        @assert(needed <= dlg.label.position.height + 0.5)

        dlg.surface!.destroy()
        host.pump()
        tail += "!"
    }
}
