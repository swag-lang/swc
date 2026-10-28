#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Asserts the composition every predefined dialog shares, whatever it holds.
//
// A modal box is one composition: a floating sheet holding a title, a body and a row of actions,
// one inset around all three, one gap between two pieces, the primary action rightmost. What
// varies between an error, a prompt, a form and a file browser is the content, and nothing else —
// so every number below comes from the theme and none of them is a dialog's to choose. See
// `.agents/skills/design-swag-dialogs`.
func assertDialogCharter(dlg: *Dialog)
{
    let metrics = dlg.themeMetrics()
    let bar     = dlg.buttonBar
    let srf     = unwrap dlg.surface
    let pad     = metrics.dialog_Padding
    let gap     = metrics.dialog_BtnPadding * 2

    // The charter's measures, where every box takes them from.
    Swag.assert(pad == 28 and gap == 16)
    Swag.assert(metrics.control_DialogHeight == 34)
    Swag.assert(MessageDlg.MinMessageWidth == 440)

    // A floating sheet: the floating corner and shadow, its outline, and no strip or close cross.
    Swag.assert(srf.flags.has(.Sheet) and srf.flags.has(.Border))
    Swag.assert(not srf.flags.has(.SmallCaption) and
                not srf.flags.has(.LargeCaption) and
                not srf.flags.has(.CloseButton))
    Swag.assert(srf.cornerRadius() == metrics.corner_Floating)
    Swag.assert(srf.shadowMargin() == dlg.theme().floatingShadowMargin())
    Swag.assert(srf.wnd.stripHeight() == 0)

    // One inset on every side; the title, when there is one, opens the body above the content.
    Swag.assert(dlg.padding.x == pad and dlg.padding.z == pad and dlg.padding.w == pad)
    if dlg.title.raw.isEmpty() do
        Swag.assert(dlg.padding.y == pad)
    else do
        Swag.assert(dlg.padding.y > pad + gap)

    // The actions end the body: one gap above them, on the body's own ground, as tall as the
    // dialog height and never narrower than a button.
    Swag.assert(bar.backgroundStyle == .Transparent)
    Swag.assert(bar.margin.y == gap)
    Swag.assert(Math.abs(bar.position.bottom() - (dlg.position.height - pad)) < 0.5)
    Swag.assert(Math.abs(bar.position.right() - (dlg.position.width - pad)) < 0.5)
    Swag.assert(not dlg.buttons.isEmpty())
    for btn in dlg.buttons
    {
        Swag.assert(Math.abs(btn.position.height - metrics.control_DialogHeight) < 0.5)
        Swag.assert(btn.position.width >= metrics.btnPush_Width - 0.5)
    }

    // One primary action per box, and it stands rightmost, against the inset.
    var primary: *PushButton?
    for btn in dlg.buttons where btn.form == .Default
    {
        Swag.assert(primary == null)
        primary = btn
    }

    Swag.assert(primary != null)
    for btn in dlg.buttons do
        Swag.assert(btn.position.right() <= primary.position.right())
    Swag.assert(Math.abs(primary.position.right() - bar.position.width) < 0.5)

    // Two actions are parted by one gap and by nothing else; the row reads in the order of the bar.
    for i in 1 until bar.children.count
    {
        let left  = bar.children[i - 1]
        let right = bar.children[i]
        Swag.assert(Math.abs(right.position.x - left.position.right() - metrics.dialog_BtnPadding) < 0.5)
    }

    // The body stands between the title and the actions, on the inset, and nothing of it falls
    // under the actions.
    let body = unwrap dlg.contentView
    Swag.assert(body.position.x == pad and body.position.y == dlg.padding.y)
    Swag.assert(Math.abs(body.position.right() - (dlg.position.width - pad)) < 0.5)
    Swag.assert(body.position.bottom() <= bar.position.y - gap + 0.5)

    // A box opens at least as wide as the family's floor.
    Swag.assert(dlg.position.width >= MessageDlg.MinMessageWidth - 2 * metrics.wnd_BorderSize - 0.5)
}

// Every predefined dialog is the same composition around a different content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1000, 700)

    let message = MessageDlg.create(&host.surface, "The password is incorrect.", {title: "Cannot mount the vault."})
    message.addButton(strings().dlg_Ok, Dialog.BtnOk, true)
    message.adaptSizeToMessage()
    assertDialogCharter(&message.dialog)

    let question = MessageDlg.create(&host.surface, "Reload viewerchrome.swg? The reading position is kept.", {title: "The file changed on disk."})
    question.addButton("Reload", Dialog.BtnOk, true)
    question.addButton("Ignore", Dialog.BtnCancel)
    question.adaptSizeToMessage()
    assertDialogCharter(&question.dialog)
    Swag.assert(question.buttons[0].position.x > question.buttons[1].position.x)

    let editOptions = EditDlgOptions{title: "Go to Address", message: "Decimal, or hexadecimal preceded by 0x.", confirmButtonText: "Go"}
    let editOne     = EditDlg.createSingleLine(&host.surface, editOptions)
    assertDialogCharter(&editOne.dialog)
    Swag.assert(editOne.edit!.position.height == host.theme.metrics.control_DialogHeight)
    Swag.assert(editOne.label.position.y >= editOne.edit.position.bottom())

    let editMany = EditDlg.createMultiLine(&host.surface, editOptions)
    assertDialogCharter(&editMany.dialog)

    let form = FormDlg.create(&host.surface, {title: "Change Password"})
    discard form.form.addTextField("Current password", "Ada")
    form.form.computeLayout()
    assertDialogCharter(&form.dialog)

    let about = AboutDlg.create(&host.surface, {
        surfaceTitle: "About",
        contentTitle: "Swag",
        message: "A systems programming language.",
        surfaceIcon: {},
        contentIcon: {}})
    assertDialogCharter(&about.dialog)
    Swag.assert(about.title.raw.isEmpty())

    let file = FileDlg.create(&host.surface, {mode: .SelectFile})
    assertDialogCharter(&file.dialog)

    message.surface!.destroy()
    question.surface!.destroy()
    editOne.surface!.destroy()
    editMany.surface!.destroy()
    form.surface!.destroy()
    about.surface!.destroy()
    file.surface!.destroy()
    host.pump()
}

// A failure leads its title with the critical dot, carries its technical detail on a mono line,
// and ends on one Close that Escape presses too, with no hint.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let dlg = MessageDlg.create(&host.surface, "The file is damaged.", {title: "Cannot open this file.", failure: true, detail: "Error code: 0x80070017"})
    host.surface.cancelButton = dlg.addButton(strings().dlg_Close, Dialog.BtnOk, true)
    dlg.adaptSizeToMessage()
    assertDialogCharter(&dlg.dialog)

    Swag.assert(dlg.failure)
    Swag.assert(dlg.detailLabel != null and dlg.detailLabel.text() == "Error code: 0x80070017")
    Swag.assert(dlg.detailLabel.position.y >= dlg.label.position.bottom())

    dlg.surface!.destroy()
    host.pump()
}

// A quiet control takes the bottom-left slot of the actions.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let dlg = Dialog.create(&host.surface, 520, 240, title: "Open File")
    dlg.addButton("Open", Dialog.BtnOk, true)
    dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel)

    let filter = Label.create(&dlg.wnd, "All files", {0, 0, 120, 0})
    dlg.setLeadingControl(filter)
    discard dlg.createContentView()
    dlg.fitHeightToContent(120)

    Swag.assert(filter.position.x == host.theme.metrics.dialog_Padding)
    Swag.assert(Math.abs(filter.position.vertCenter() - dlg.buttonBar.position.vertCenter()) < 0.5)

    dlg.surface!.destroy()
    host.pump()
}

// The bands of the file browser share one left edge and one right edge.
//
// Given an inset each they lined up on none: the first tool of the navigation bar, the first
// column of the list and the first label of the name form each started somewhere else, and the
// right edge of a field missed the right edge of the list by the difference between two paddings.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 620)

    let fb = FileBrowserCtrl.create(&host.root, {mode: .SelectFile, showLocationsPane: false}, {0, 0, 860, 580})
    fb.applyLayout()

    let list = fb.listCtrl
    let bar  = unwrap fb.backButton.parent
    let form = unwrap fb.editFile.parent

    Swag.assert(Math.abs(list.position.x - (bar.position.x + bar.padding.x)) < 0.5)
    Swag.assert(Math.abs(list.position.x - (form.position.x + form.padding.x)) < 0.5)
    Swag.assert(Math.abs(list.position.right() - (bar.position.right() - bar.padding.z)) < 0.5)
    Swag.assert(Math.abs(list.position.right() - (form.position.right() - form.padding.z)) < 0.5)
}
