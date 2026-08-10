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
    let metrics       = dlg.themeMetrics()
    let contentHeight = dlg.edit!.position.height + dlg.label.position.height + dlg.label.margin.w
    var expected      = contentHeight + 2 * metrics.dialog_Padding + dlg.buttonBar.position.height + 2 * metrics.wnd_BorderSize
    expected += metrics.wnd_SmallCaptionCY + 2 * dlg.surface!.shadowMargin()
    @assert(Math.abs(dlg.surface!.position.height - expected * dlg.surface!.dpiScale) < 1.5)
}

// Fitting a resizable editor preserves the authored editor height and makes it the minimum.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    var options: EditDlgOptions
    options.title        = "Description"
    options.message      = "Describe the change."
    options.editorHeight = 150
    let dlg = EditDlg.createMultiLine(&host.surface, options)

    let metrics       = dlg.themeMetrics()
    let contentHeight = dlg.richEdit!.position.height + dlg.label.position.height + dlg.label.margin.w
    let visibleHeight = contentHeight + 2 * metrics.dialog_Padding + dlg.buttonBar.position.height + 2 * metrics.wnd_BorderSize + metrics.wnd_SmallCaptionCY
    let outerHeight   = visibleHeight + 2 * dlg.surface!.shadowMargin()
    @assert(Math.abs(dlg.richEdit!.position.height - cast(f32) options.editorHeight) < 0.5)
    @assert(Math.abs(dlg.surface!.position.height - outerHeight * dlg.surface!.dpiScale) < 1.5)
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
        message:      "A systems programming language.",
        surfaceIcon:  {},
        contentIcon:  {},
    }
    let dlg = AboutDlg.create(&host.surface, params)

    let metrics = dlg.themeMetrics()
    var contentHeight = dlg.labelMessageTitle.measure({dlg.labelMessageTitle.position.width, 0}).preferred.y
    contentHeight += dlg.labelMessage.measure({dlg.labelMessage.position.width, 0}).preferred.y
    contentHeight += metrics.dialog_BtnPadding * 2
    var expected = contentHeight + 2 * metrics.dialog_Padding + dlg.buttonBar.position.height + 2 * metrics.wnd_BorderSize
    expected += metrics.wnd_SmallCaptionCY + 2 * dlg.surface!.shadowMargin()
    @assert(Math.abs(dlg.surface!.position.height - expected * dlg.surface!.dpiScale) < 0.5)
}

// A short question is only as wide as its actions; no invisible button is reserved beside them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let dlg = MessageDlg.create(&host.surface, "Save changes?")
    dlg.addButton("Yes", Dialog.BtnYes)
    dlg.addButton("No", Dialog.BtnNo)
    dlg.addButton("Cancel", Dialog.BtnCancel, true)

    let metrics = dlg.themeMetrics()
    var expected = 2 * metrics.dialog_Padding + 2 * metrics.wnd_BorderSize + 2 * dlg.surface!.shadowMargin()
    for btn in dlg.buttons do
        expected += btn.position.width
    expected += cast(f32) (dlg.buttons.count - 1) * metrics.dialog_BtnPadding
    expected *= dlg.surface!.dpiScale

    var measured = 0'f32
    host.app.sigFrame += func|host = &host, dlg, measured = &measured|(app)
    {
        discard app
        if dref measured != 0 do
            return
        dref measured = dlg.surface!.position.width
        @assert(host.clickModalButton(Dialog.BtnCancel))
    }

    @assert(dlg.doModal() == Dialog.BtnCancel)
    @assert(Math.abs(measured - expected) < 0.5)
}
