#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

#test
{
    var pressedCount: u32
    var host:         Testing.HeadlessHost
    host.setup(400, 200)

    host.root.hookOnEvent = func|&pressedCount|(_, evt)
    {
        if evt is KeyEvent as key where key.kind == .Pressed
        {
            pressedCount += 1
            return true
        }

        return false
    }

    host.keyPress(.Left)
    Swag.assert(pressedCount == 1)
    Swag.assert(host.app.keyboardFocusWnd == &host.root)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let card  = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    let order = FocusOrder.collect(&host.root)

    Swag.assert(order.stops.count == 3)
    Swag.assert(order.stops[0] == cast(*Wnd, card.field))
    Swag.assert(order.stops[1] == cast(*Wnd, card.browse))
    Swag.assert(order.stops[2] == cast(*Wnd, card.submit))
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let left  = focusHeadlessCard(&host.root, {10, 10, 180, 180})
    let right = focusHeadlessCard(&host.root, {200, 10, 180, 180})
    let order = FocusOrder.collect(&host.root)

    Swag.assert(order.stops.count == 6)
    Swag.assert(order.stops[0] == cast(*Wnd, left.field))
    Swag.assert(order.stops[2] == cast(*Wnd, left.submit))
    Swag.assert(order.stops[3] == cast(*Wnd, right.field))
    Swag.assert(order.stops[5] == cast(*Wnd, right.submit))
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    host.root.setInitialFocus()
    Swag.assert(card.field.hasFocus())

    host.keyPress(.Tab)
    Swag.assert(card.browse.hasFocus())
    host.keyPress(.Tab)
    Swag.assert(card.submit.hasFocus())

    // Wraps rather than leaving the surface.
    host.keyPress(.Tab)
    Swag.assert(card.field.hasFocus())

    host.keyPress(.Tab, .Shift)
    Swag.assert(card.submit.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})

    host.clickWnd(card.submit)
    Swag.assert(card.submit.hasFocus())
    Swag.assert(not card.submit.hasVisibleFocus())

    host.keyPress(.Tab)
    Swag.assert(card.field.hasFocus())
    Swag.assert(card.field.hasVisibleFocus())

    host.clickWnd(card.submit)
    Swag.assert(not card.submit.hasVisibleFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let edit = EditBox.create(&host.root, "text", {10, 10, 180, 24})
    var lostCount: u32
    edit.sigFocusLost += func|lostCount = &lostCount|(_)
    {
        lostCount[] += 1
    }

    edit.setFocus()
    Swag.assert(edit.hasFocus())
    Swag.assert(edit.timerCaret != null)

    host.surface.loseKeyboardFocus()
    Swag.assert(host.app.keyboardFocusWnd == null)
    Swag.assert(not edit.hasFocus())
    Swag.assert(edit.timerCaret == null)
    Swag.assert(host.surface.focusWnd == cast(*Wnd?, edit))
    Swag.assert(lostCount == 1)

    let focusRestored = host.surface.restoreFocus()
    Swag.assert(focusRestored)
    Swag.assert(edit.hasFocus())
    Swag.assert(edit.timerCaret != null)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    card.field.setFocus()
    Swag.assert(card.field.hasFocus())

    card.field.hide()
    Swag.assert(card.browse.hasFocus())

    card.browse.disable()
    Swag.assert(card.submit.hasFocus())

    // A whole form going down hands the keyboard to what follows the form.
    let second = focusHeadlessCard(&host.root, {220, 10, 160, 180})
    second.field.setFocus()
    second.body.disable()
    Swag.assert(second.submit.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    card.browse.setFocus()
    Swag.assert(card.browse.hasFocus())

    card.browse.destroy()
    Swag.assert(card.submit.hasFocus())

    host.pump()
    Swag.assert(card.submit.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let panel = Wnd.create'Wnd(&host.root, {10, 10, 180, 60})
    let first = EditBox.create(panel, "", {0, 0, 160, 24})
    let next  = EditBox.create(&host.root, "", {220, 10, 160, 24})

    var lostCount: u32
    first.sigFocusLost += func|panel, lostCount = &lostCount|(_)
    {
        lostCount[] += 1
        panel.destroy()
    }

    first.setFocus()
    next.setFocus()

    Swag.assert(lostCount == 1)
    Swag.assert(next.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let password = PasswordEdit.create(&host.root, {10, 10, 200, 24})
    let list     = ListCtrl.createSimple(&host.root, {10, 50, 200, 100})
    let order    = FocusOrder.collect(&host.root)

    Swag.assert(order.stops.count == 2)
    Swag.assert(order.stops[0] == cast(*Wnd, password))
    Swag.assert(order.stops[1] == cast(*Wnd, list))

    password.setFocus()
    Swag.assert(password.hasFocus())
    Swag.assert(host.app.keyboardFocusWnd == cast(*Wnd?, password.edit))

    host.keyPress(.Tab)
    Swag.assert(list.hasFocus())
    Swag.assert(host.app.keyboardFocusWnd == cast(*Wnd?, list.listView))
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let a     = RadioButton.create(&host.root, "A", {10, 10, 120, 24})
    let b     = RadioButton.create(&host.root, "B", {10, 40, 120, 24})
    let c     = RadioButton.create(&host.root, "C", {10, 70, 120, 24})
    let after = PushButton.create(&host.root, "Go", {10, 110, 80, 24})
    a.groupId, b.groupId, c.groupId = "choice"
    b.setChecked(true)

    let order = FocusOrder.collect(&host.root)
    Swag.assert(order.stops.count == 2)
    Swag.assert(order.stops[0] == cast(*Wnd, b))
    Swag.assert(order.stops[1] == cast(*Wnd, after))

    // The arrows choose inside the group, and Tab is what leaves it.
    b.setFocus()
    host.keyPress(.Down)
    Swag.assert(c.isChecked())
    Swag.assert(c.hasFocus())

    // The group wraps rather than handing the keyboard to the button beside it.
    host.keyPress(.Down)
    Swag.assert(a.isChecked())
    Swag.assert(a.hasFocus())

    host.keyPress(.Tab)
    Swag.assert(after.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    host.recordCommands()

    let ok     = PushButton.create(&host.root, "Ok", {10, 10, 80, 24}, FocusHeadless_Default)
    let cancel = PushButton.create(&host.root, "Cancel", {100, 10, 80, 24}, FocusHeadless_Cancel)
    let field  = EditBox.create(&host.root, "", {10, 50, 200, 24})

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    // A field keeps Enter for its own submitted signal, so the ring stands on something that
    // does not answer keys to see the surface answer for it.
    field.setFocus()
    host.keyPress(.Escape)
    Swag.assert(host.lastCommand == FocusHeadless_Cancel)

    host.focus(&host.root)
    host.keyPress(.Return)
    Swag.assert(host.lastCommand == FocusHeadless_Default)

    // A button that is down does not answer for the surface.
    let previous = host.commandCount
    cancel.disable()
    host.focus(&host.root)
    host.keyPress(.Escape)
    Swag.assert(host.commandCount == previous)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let field = EditBox.create(&host.root, "", {10, 10, 200, 24})
    let bar   = Wnd.create'Wnd(&host.root, {10, 60, 300, 40})
    let yes   = PushButton.create(bar, "Yes", {0, 0, 80, 24})
    let no    = PushButton.create(bar, "No", {90, 0, 80, 24})
    let more  = PushButton.create(bar, "More", {180, 0, 80, 24})

    yes.setFocus()
    host.keyPress(.Right)
    Swag.assert(no.hasFocus())
    host.keyPress(.Down)
    Swag.assert(more.hasFocus())

    // The bar wraps on itself rather than reaching the field above it.
    host.keyPress(.Right)
    Swag.assert(yes.hasFocus())
    host.keyPress(.Left)
    Swag.assert(more.hasFocus())

    host.keyPress(.Tab)
    Swag.assert(field.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 260)
    host.recordCommands()

    let list   = ListCtrl.createSimple(&host.root, {10, 10, 200, 120})
    let ok     = PushButton.create(&host.root, "Ok", {10, 150, 80, 24}, FocusHeadless_Default)
    let cancel = PushButton.create(&host.root, "Cancel", {100, 150, 80, 24}, FocusHeadless_Cancel)
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    // What the list reads stays with the list.
    list.setFocus()
    Swag.assert(list.hasFocus())
    host.keyPress(.Down)
    Swag.assert(list.isLineSelected(0))
    Swag.assert(list.hasFocus())

    // What it does not read goes to the surface.
    host.keyPress(.Escape)
    Swag.assert(host.lastCommand == FocusHeadless_Cancel)
    Swag.assert(list.hasFocus())

    host.keyPress(.Tab)
    Swag.assert(ok.hasFocus())
    host.keyPress(.Tab, .Shift)
    Swag.assert(list.hasFocus())

    // An empty list has nothing to read at all, and still must not eat the way out.
    list.clear()
    host.keyPress(.Tab)
    Swag.assert(ok.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let field  = EditBox.create(&host.root, "", {10, 10, 200, 24})
    let bar    = Wnd.create'Wnd(&host.root, {10, 60, 300, 40})
    let ok     = PushButton.create(bar, "Ok", {0, 0, 80, 24}, form: .Default)
    let cancel = PushButton.create(bar, "Cancel", {90, 0, 80, 24})

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    // The keyboard is in a field, so the box answers Enter with the action it named.
    field.setFocus()
    Swag.assert(ok.paintedForm() == .Default)
    Swag.assert(cancel.paintedForm() == .Normal)

    host.keyPress(.Tab)
    Swag.assert(ok.hasFocus())
    Swag.assert(ok.paintedForm() == .Default)

    // The arrows walk the bar and the fill follows them.
    host.keyPress(.Right)
    Swag.assert(cancel.hasFocus())
    Swag.assert(cancel.paintedForm() == .Default)
    Swag.assert(ok.paintedForm() == .Normal)

    host.keyPress(.Left)
    Swag.assert(ok.hasFocus())
    Swag.assert(ok.paintedForm() == .Default)
    Swag.assert(cancel.paintedForm() == .Normal)

    // Back on the field, the box shows its own default again.
    host.keyPress(.Tab, .Shift)
    Swag.assert(field.hasFocus())
    Swag.assert(ok.paintedForm() == .Default)
    Swag.assert(cancel.paintedForm() == .Normal)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 240)

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    card.browse.setFocus()
    Swag.assert(card.browse.hasFocus())

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Pick")
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.addButton("Cancel", Dialog.BtnCancel)

    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnCancel)
    Swag.assert(host.autoHandled)

    // The box is queued for destruction on the way out; the surface is gone once that is drained.
    host.pump()
    Swag.assert(host.openedSurfaceCount() == 0)

    Swag.assert(card.browse.hasFocus())
    host.keyPress(.Tab)
    Swag.assert(card.submit.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)

    let alone = PushButton.create(&host.root, "A", {10, 10, 80, 24})
    let box   = Wnd.create'Wnd(&host.root, {10, 60, 200, 40})
    let inner = PushButton.create(box, "B", {0, 0, 80, 24})

    inner.setFocus()
    host.keyPress(.Right)
    Swag.assert(alone.hasFocus())

    host.keyPress(.Right, .Shift)
    Swag.assert(alone.hasFocus())
    host.keyPress(.Right, .Control)
    Swag.assert(alone.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Confirm")
    dlg.addButton("Yes", Dialog.BtnYes)
    let no = dlg.addButton("No", Dialog.BtnNo, true)

    var checked: bool
    host.app.sigFrame += func|host = &host, no, checked = &checked|(_)
    {
        if checked[] do
            return
        checked[] = true

        // Reading order would have opened on `Yes`, and a focused button answers Enter itself:
        // the box would have answered yes to a question whose default is no.
        Swag.assert(no.hasFocus())
        Swag.assert(no.hasVisibleFocus())
        let modalButtonClicked = host.clickModalButton(Dialog.BtnNo)
        Swag.assert(modalButtonClicked)
    }

    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnNo)
    Swag.assert(checked)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let caller = EditBox.create(&host.root, "caller", {20, 20, 180, 26})
    caller.setFocus()
    let dlg    = Dialog.create(&host.surface, 260, 150, title: "Confirm")
    let cancel = dlg.addButton("Cancel", Dialog.BtnCancel, true)

    var checked: bool
    host.app.sigFrame += func|host = &host, caller, cancel, checked = &checked|(_)
    {
        if checked[] do
            return
        checked[] = true

        Swag.assert(host.surface.isDisabled and cancel.hasFocus())
        caller.setFocus()
        Swag.assert(cancel.hasFocus() and not caller.hasFocus())
        host.keyPress(.Escape)
    }

    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnCancel)
    Swag.assert(checked and caller.hasFocus())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let dlg   = Dialog.create(&host.surface, 260, 160, title: "Rename")
    let field = EditBox.create(dlg.view(), "name", {20, 20, 180, 26})
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.addButton("Cancel", Dialog.BtnCancel)

    // The bar is docked, so it only stands below the field once the box has been laid out — and
    // reading order is what decides which of the two the keyboard opens on.
    dlg.applyLayout()

    var checked: bool
    host.app.sigFrame += func|host = &host, field, checked = &checked|(_)
    {
        if checked[] do
            return
        checked[] = true

        Swag.assert(field.hasFocus())

        // The field declines Enter, so the box still answers with the action it named.
        host.keyPress(.Return)
    }

    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnOk)
    Swag.assert(checked)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)

    let dlg    = Dialog.create(&host.surface, 260, 170, title: "Confirm")
    let again  = CheckButton.create(dlg.view(), "Do not ask again", {20, 20, 180, 26})
    let toggle = ToggleButton.create(dlg.view(), {20, 56, 56, 26})
    dlg.addButton("Yes", Dialog.BtnYes)
    let no = dlg.addButton("No", Dialog.BtnNo, true)
    dlg.applyLayout()

    // Both read before the action bar, so either is what the box would have opened on.
    Swag.assert(FocusOrder.collect(dlg.surface!.wnd).first() == cast(*Wnd, again))
    Swag.assert(again.wndFlags.has(.ActivatesOnKey) and toggle.wndFlags.has(.ActivatesOnKey))

    var checked: bool
    host.app.sigFrame += func|host = &host, again, toggle, no, checked = &checked|(_)
    {
        if checked[] do
            return
        checked[] = true

        Swag.assert(no.hasFocus())
        Swag.assert(not again.hasFocus() and not toggle.hasFocus())

        // Passed over is not left out: the ring still wraps onto the options.
        host.keyPress(.Tab)
        Swag.assert(again.hasFocus())

        no.setFocus()
        let modalButtonClicked = host.clickModalButton(Dialog.BtnNo)
        Swag.assert(modalButtonClicked)
    }

    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnNo)
    Swag.assert(checked)
}
