#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Asserts the geometry every predefined dialog shares, whatever it holds.
//
// A modal box is one composition: a body over an action bar, one inset, one gap, one row of
// actions ending on one edge. What varies between an error, a prompt, a form and a file browser
// is the content, and nothing else — so every number below comes from the theme and none of them
// is a dialog's to choose. See the charter in `.agents/skills/design-swag-dialogs`.
//
// `bodyInset` is the air the box keeps around its content: the standard inset for a box holding
// loose content, and none for a box whose body is one panel carrying its own edges.
func assertDialogCharter(dlg: *Dialog, bodyInset: f32)
{
    let metrics = dlg.themeMetrics()
    let bar     = dlg.buttonBar

    // The bar is one row of actions and the air above and below it, and never a hand-set band.
    @assert(Math.abs(bar.position.height - (metrics.btnPush_Height + 2 * metrics.dialog_BtnPadding)) < 0.5)

    // Every action is at least the theme button and they all read as one row.
    @assert(!dlg.buttons.isEmpty())
    for btn in dlg.buttons
    {
        @assert(Math.abs(btn.position.height - metrics.btnPush_Height) < 0.5)
        @assert(btn.position.width >= metrics.btnPush_Width - 0.5)
        @assert(Math.abs(btn.position.y - dlg.buttons[0].position.y) < 0.5)
    }

    // One gap between two actions, and it is the bar's own.
    for i in 1 until dlg.buttons.count
    {
        let gap = dlg.buttons[i].position.x - dlg.buttons[i - 1].position.right()
        @assert(Math.abs(gap - metrics.dialog_BtnPadding) < 0.5)
    }

    // The row ends on the inset the body keeps, so the last action and whatever the box holds
    // read on one right edge instead of on two that nearly agree.
    let last = dlg.buttons[dlg.buttons.count - 1]
    @assert(Math.abs(bar.position.width - last.position.right() - metrics.dialog_Padding) < 0.5)

    // One dominant action, so the bar says what Enter decides.
    var defaults = 0
    for btn in dlg.buttons where btn.form == .Default do
        defaults += 1
    @assert(defaults == 1)

    // The body keeps one inset, the same on all four sides, and the box owns it rather than
    // each dialog restating it.
    let body = dlg.contentView!
    @assert(Math.abs(body.padding.x - bodyInset) < 0.5)
    @assert(Math.abs(body.padding.y - bodyInset) < 0.5)
    @assert(Math.abs(body.padding.z - bodyInset) < 0.5)
    @assert(Math.abs(body.padding.w - bodyInset) < 0.5)

    // A box names itself: the caption takes its band whether or not anything is written in it.
    @assert(!dlg.surface!.wnd.name.isEmpty())

    // And it is as tall as what it holds: nothing of the body falls under the action bar.
    @assert(body.position.bottom() <= bar.position.y + 0.5)
}

// Every predefined dialog is the same composition around a different content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1000, 700)
    defer host.shutdown()

    let message = MessageDlg.create(&host.surface, "The password is incorrect.", {title: "Error"})
    message.addButton(strings().dlg_Ok, Dialog.BtnOk, true)
    message.adaptSizeToMessage()
    assertDialogCharter(&message.dialog, host.theme.metrics.dialog_Padding)

    var editOptions: EditDlgOptions
    editOptions.title   = "Rename"
    editOptions.message = "Enter the new name."
    let editOne = EditDlg.createSingleLine(&host.surface, editOptions)
    assertDialogCharter(&editOne.dialog, host.theme.metrics.dialog_Padding)

    let editMany = EditDlg.createMultiLine(&host.surface, editOptions)
    assertDialogCharter(&editMany.dialog, host.theme.metrics.dialog_Padding)

    var formOptions: FormDlgOptions
    formOptions.title = "Profile"
    let form = FormDlg.create(&host.surface, formOptions)
    discard form.form.addTextField("NAME", "Ada")
    form.form.computeLayout()
    assertDialogCharter(&form.dialog, host.theme.metrics.dialog_Padding)

    let about = AboutDlg.create(&host.surface, {
        surfaceTitle: "About",
        contentTitle: "Swag",
        message: "A systems programming language.",
        surfaceIcon: {},
        contentIcon: {}})
    assertDialogCharter(&about.dialog, host.theme.metrics.dialog_Padding)

    // The file browser carries its own grounds and its own edges, so the box keeps no inset
    // around it and the browser's bands are what reach the frame.
    var fileOptions: FileDlgOptions
    fileOptions.mode = .SelectFile
    let file = FileDlg.create(&host.surface, fileOptions)
    assertDialogCharter(&file.dialog, 0)

    message.surface!.destroy()
    editOne.surface!.destroy()
    editMany.surface!.destroy()
    form.surface!.destroy()
    about.surface!.destroy()
    file.surface!.destroy()
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
    defer host.shutdown()

    var opt: FileDlgOptions
    opt.mode              = .SelectFile
    opt.showLocationsPane = false

    let fb = FileBrowserCtrl.create(&host.root, opt, {0, 0, 860, 580})
    fb.applyLayout()

    let list = fb.listCtrl
    let bar  = fb.backButton.parent!
    let form = fb.editFile.parent!

    @assert(Math.abs(list.position.x - (bar.position.x + bar.padding.x)) < 0.5)
    @assert(Math.abs(list.position.x - (form.position.x + form.padding.x)) < 0.5)
    @assert(Math.abs(list.position.right() - (bar.position.right() - bar.padding.z)) < 0.5)
    @assert(Math.abs(list.position.right() - (form.position.right() - form.padding.z)) < 0.5)
}
