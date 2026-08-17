#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

const FocusHeadless_Default = "FocusHeadless.Default"
const FocusHeadless_Cancel  = "FocusHeadless.Cancel"

// A form built the way a card is built: a docked action bar created before the content that fills
// what is left over, so creation order and reading order disagree on purpose.
struct FocusHeadlessCard
{
    panel:   *Wnd             = undefined     // Raised panel holding the whole card.
    actions: *StackLayoutCtrl = undefined     // Action bar docked at the bottom.
    body:    *Wnd             = undefined     // Content filling what the bar leaves.
    field:   *EditBox         = undefined     // Field of the body.
    browse:  *PushButton      = undefined     // Trailing action on the same line as the field.
    submit:  *PushButton      = undefined     // Dominant action, in the bar.
}

func focusHeadlessCard(parent: *Wnd, rect: Math.Rectangle)->FocusHeadlessCard
{
    var result: retval

    result.panel = Wnd.create'Wnd(parent, rect)

    result.actions           = StackLayoutCtrl.create(result.panel, .Right, {0, 0, 0, 30})
    result.actions.dockStyle = .Bottom
    result.submit            = PushButton.create(result.actions, "Go")

    result.body           = Wnd.create'Wnd(result.panel)
    result.body.dockStyle = .Center
    result.field          = EditBox.create(result.body, "", {0, 0, 100, 24})
    result.browse         = PushButton.create(result.body, "...", {110, 0, 40, 24})

    result.panel.applyLayout()
    result.actions.computeLayout()
    return result
}

// A canvas has no traversal stop, but its root hook still receives game-style keyboard input.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    var pressedCount: u32
    host.root.hookOnEvent = func|&pressedCount|(wnd, evt)
    {
        if let key = evt as KeyEvent where key.kind == .Pressed
        {
            pressedCount += 1
            return true
        }

        return false
    }

    host.keyPress(Input.Key.Left)
    @assert(pressedCount == 1)
    @assert(host.app.keyboardFocusWnd == &host.root)
}

// The ring reads the way the eye does, not the way the tree was built.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let card  = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    let order = FocusOrder.collect(&host.root)

    @assert(order.stops.count == 3)
    @assert(order.stops[0] == cast(*Wnd) card.field)
    @assert(order.stops[1] == cast(*Wnd) card.browse)
    @assert(order.stops[2] == cast(*Wnd) card.submit)
}

// Two columns keep their own fields together instead of interleaving row by row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let left  = focusHeadlessCard(&host.root, {10, 10, 180, 180})
    let right = focusHeadlessCard(&host.root, {200, 10, 180, 180})
    let order = FocusOrder.collect(&host.root)

    @assert(order.stops.count == 6)
    @assert(order.stops[0] == cast(*Wnd) left.field)
    @assert(order.stops[2] == cast(*Wnd) left.submit)
    @assert(order.stops[3] == cast(*Wnd) right.field)
    @assert(order.stops[5] == cast(*Wnd) right.submit)
}

// Tab walks the ring and wraps around, Shift+Tab walks it backwards.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    host.root.setInitialFocus()
    @assert(card.field.hasFocus())

    host.keyPress(Input.Key.Tab)
    @assert(card.browse.hasFocus())
    host.keyPress(Input.Key.Tab)
    @assert(card.submit.hasFocus())

    // Wraps rather than leaving the surface.
    host.keyPress(Input.Key.Tab)
    @assert(card.field.hasFocus())

    host.keyPress(Input.Key.Tab, Input.KeyModifiers.Shift)
    @assert(card.submit.hasFocus())
}

// The ring shows only while the keyboard is what moved the focus.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})

    host.clickWnd(card.submit)
    @assert(card.submit.hasFocus())
    @assert(!card.submit.hasVisibleFocus())

    host.keyPress(Input.Key.Tab)
    @assert(card.field.hasFocus())
    @assert(card.field.hasVisibleFocus())

    host.clickWnd(card.submit)
    @assert(!card.submit.hasVisibleFocus())
}

// Native surface deactivation removes the logical focus and its caret, then activation restores
// the recorded stop instead of leaving a control painted as active in a background application.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let edit = EditBox.create(&host.root, "text", {10, 10, 180, 24})
    var lostCount: u32
    edit.sigFocusLost += func|lostCount = &lostCount|(ed)
    {
        discard ed
        lostCount[] += 1
    }

    edit.setFocus()
    @assert(edit.hasFocus())
    @assert(edit.timerCaret != null)

    host.surface.loseKeyboardFocus()
    @assert(host.app.keyboardFocusWnd == null)
    @assert(!edit.hasFocus())
    @assert(edit.timerCaret == null)
    @assert(host.surface.focusWnd == cast(#null *Wnd) edit)
    @assert(lostCount == 1)

    @assert(host.surface.restoreFocus())
    @assert(edit.hasFocus())
    @assert(edit.timerCaret != null)
}

// A hidden or disabled control hands the keyboard to what follows it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    card.field.setFocus()
    @assert(card.field.hasFocus())

    card.field.hide()
    @assert(card.browse.hasFocus())

    card.browse.disable()
    @assert(card.submit.hasFocus())

    // A whole form going down hands the keyboard to what follows the form.
    let second = focusHeadlessCard(&host.root, {220, 10, 160, 180})
    second.field.setFocus()
    second.body.disable()
    @assert(second.submit.hasFocus())
}

// A control taken off the surface hands the keyboard on rather than dropping it.
//
// Destroying is deferred, so a focus left pointing into the window is only cleared a frame later,
// with nothing to say where it should have gone. The next Tab then restarted at the top.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    card.browse.setFocus()
    @assert(card.browse.hasFocus())

    card.browse.destroy()
    @assert(card.submit.hasFocus())

    host.pump()
    @assert(card.submit.hasFocus())
}

// A Lost callback can dismantle the old focused subtree without recursively losing focus again.
// The new owner is published before that callback runs, so releaseFocus sees that the keyboard
// has already left the subtree being destroyed.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let panel = Wnd.create'Wnd(&host.root, {10, 10, 180, 60})
    let first = EditBox.create(panel, "", {0, 0, 160, 24})
    let next  = EditBox.create(&host.root, "", {220, 10, 160, 24})

    var lostCount: u32
    first.sigFocusLost += func|panel, lostCount = &lostCount|(ed)
    {
        discard ed
        lostCount[] += 1
        panel.destroy()
    }

    first.setFocus()
    next.setFocus()

    @assert(lostCount == 1)
    @assert(next.hasFocus())
}

// A composite is one stop, and the focus lands on the part of it that reads the keys.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let password = PasswordEdit.create(&host.root, {10, 10, 200, 24})
    let list     = ListCtrl.createSimple(&host.root, {10, 50, 200, 100})
    let order    = FocusOrder.collect(&host.root)

    @assert(order.stops.count == 2)
    @assert(order.stops[0] == cast(*Wnd) password)
    @assert(order.stops[1] == cast(*Wnd) list)

    password.setFocus()
    @assert(password.hasFocus())
    @assert(host.app.keyboardFocusWnd == cast(#null *Wnd) password.edit)

    host.keyPress(Input.Key.Tab)
    @assert(list.hasFocus())
    @assert(host.app.keyboardFocusWnd == cast(#null *Wnd) list.listView)
}

// A group of options is one stop, entered on the option that is checked.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let a     = RadioButton.create(&host.root, "A", {10, 10, 120, 24})
    let b     = RadioButton.create(&host.root, "B", {10, 40, 120, 24})
    let c     = RadioButton.create(&host.root, "C", {10, 70, 120, 24})
    let after = PushButton.create(&host.root, "Go", {10, 110, 80, 24})
    a.groupId, b.groupId, c.groupId = "choice"
    b.setChecked(true)

    let order = FocusOrder.collect(&host.root)
    @assert(order.stops.count == 2)
    @assert(order.stops[0] == cast(*Wnd) b)
    @assert(order.stops[1] == cast(*Wnd) after)

    // The arrows choose inside the group, and Tab is what leaves it.
    b.setFocus()
    host.keyPress(Input.Key.Down)
    @assert(c.isChecked())
    @assert(c.hasFocus())

    // The group wraps rather than handing the keyboard to the button beside it.
    host.keyPress(Input.Key.Down)
    @assert(a.isChecked())
    @assert(a.hasFocus())

    host.keyPress(Input.Key.Tab)
    @assert(after.hasFocus())
}

// Enter and Escape stand for the two standard buttons of the surface.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()
    host.recordCommands()

    let ok     = PushButton.create(&host.root, "Ok", {10, 10, 80, 24}, FocusHeadless_Default)
    let cancel = PushButton.create(&host.root, "Cancel", {100, 10, 80, 24}, FocusHeadless_Cancel)
    let field  = EditBox.create(&host.root, "", {10, 50, 200, 24})
    discard ok
    discard cancel

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    // A field keeps Enter for its own submitted signal, so the ring stands on something that
    // does not answer keys to see the surface answer for it.
    field.setFocus()
    host.keyPress(Input.Key.Escape)
    @assert(host.lastCommand == FocusHeadless_Cancel)

    host.focus(&host.root)
    host.keyPress(Input.Key.Return)
    @assert(host.lastCommand == FocusHeadless_Default)

    // A button that is down does not answer for the surface.
    let previous = host.commandCount
    cancel.disable()
    host.focus(&host.root)
    host.keyPress(Input.Key.Escape)
    @assert(host.commandCount == previous)
}

// The arrows walk the group the focus stands in; Tab is what crosses the whole box.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let field = EditBox.create(&host.root, "", {10, 10, 200, 24})
    let bar   = Wnd.create'Wnd(&host.root, {10, 60, 300, 40})
    let yes   = PushButton.create(bar, "Yes", {0, 0, 80, 24})
    let no    = PushButton.create(bar, "No", {90, 0, 80, 24})
    let more  = PushButton.create(bar, "More", {180, 0, 80, 24})

    yes.setFocus()
    host.keyPress(Input.Key.Right)
    @assert(no.hasFocus())
    host.keyPress(Input.Key.Down)
    @assert(more.hasFocus())

    // The bar wraps on itself rather than reaching the field above it.
    host.keyPress(Input.Key.Right)
    @assert(yes.hasFocus())
    host.keyPress(Input.Key.Left)
    @assert(more.hasFocus())

    host.keyPress(Input.Key.Tab)
    @assert(field.hasFocus())
}

// A list keeps the keys it reads and hands back the ones it does not.
//
// A control that marks every key handled makes the surface it sits on unanswerable: the box cannot
// be backed out of and the traversal cannot leave the control. A file box opens the keyboard on its
// file list, which is exactly where Escape and Tab have to keep working.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 260)
    defer host.shutdown()
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
    @assert(list.hasFocus())
    host.keyPress(Input.Key.Down)
    @assert(list.isLineSelected(0))
    @assert(list.hasFocus())

    // What it does not read goes to the surface.
    host.keyPress(Input.Key.Escape)
    @assert(host.lastCommand == FocusHeadless_Cancel)
    @assert(list.hasFocus())

    host.keyPress(Input.Key.Tab)
    @assert(ok.hasFocus())
    host.keyPress(Input.Key.Tab, Input.KeyModifiers.Shift)
    @assert(list.hasFocus())

    // An empty list has nothing to read at all, and still must not eat the way out.
    list.clear()
    host.keyPress(Input.Key.Tab)
    @assert(ok.hasFocus())
}

// The accent stands on the action Enter would run, which a focused button is.
//
// A box names one dominant action, and the keyboard can stand on another. Left where it was
// created, the fill said Enter would run something other than what the ring points at.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let field  = EditBox.create(&host.root, "", {10, 10, 200, 24})
    let bar    = Wnd.create'Wnd(&host.root, {10, 60, 300, 40})
    let ok     = PushButton.create(bar, "Ok", {0, 0, 80, 24}, form: .Default)
    let cancel = PushButton.create(bar, "Cancel", {90, 0, 80, 24})

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    // The keyboard is in a field, so the box answers Enter with the action it named.
    field.setFocus()
    @assert(ok.paintedForm() == .Default)
    @assert(cancel.paintedForm() == .Normal)

    host.keyPress(Input.Key.Tab)
    @assert(ok.hasFocus())
    @assert(ok.paintedForm() == .Default)

    // The arrows walk the bar and the fill follows them.
    host.keyPress(Input.Key.Right)
    @assert(cancel.hasFocus())
    @assert(cancel.paintedForm() == .Default)
    @assert(ok.paintedForm() == .Normal)

    host.keyPress(Input.Key.Left)
    @assert(ok.hasFocus())
    @assert(ok.paintedForm() == .Default)
    @assert(cancel.paintedForm() == .Normal)

    // Back on the field, the box shows its own default again.
    host.keyPress(Input.Key.Tab, Input.KeyModifiers.Shift)
    @assert(field.hasFocus())
    @assert(ok.paintedForm() == .Default)
    @assert(cancel.paintedForm() == .Normal)
}

// A box gives the keyboard back to the control it was opened from.
//
// The surface under a modal keeps its own focus while the box runs, so backing out of the box
// resumes the form where the reader left it instead of restarting the traversal somewhere else.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 240)
    defer host.shutdown()

    let card = focusHeadlessCard(&host.root, {10, 10, 200, 180})
    card.browse.setFocus()
    @assert(card.browse.hasFocus())

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Pick")
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.addButton("Cancel", Dialog.BtnCancel)

    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    @assert(dlg.doModal() == Dialog.BtnCancel)
    @assert(host.autoHandled)

    // The box is queued for destruction on the way out; the surface is gone once that is drained.
    host.pump()
    @assert(host.openedSurfaceCount() == 0)

    @assert(card.browse.hasFocus())
    host.keyPress(Input.Key.Tab)
    @assert(card.submit.hasFocus())
}

// A stop alone in its group answers the arrows with the whole ring, and a modified arrow is a
// gesture of the control rather than a traversal.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200)
    defer host.shutdown()

    let alone = PushButton.create(&host.root, "A", {10, 10, 80, 24})
    let box   = Wnd.create'Wnd(&host.root, {10, 60, 200, 40})
    let inner = PushButton.create(box, "B", {0, 0, 80, 24})

    inner.setFocus()
    host.keyPress(Input.Key.Right)
    @assert(alone.hasFocus())

    host.keyPress(Input.Key.Right, Input.KeyModifiers.Shift)
    @assert(alone.hasFocus())
    host.keyPress(Input.Key.Right, Input.KeyModifiers.Control)
    @assert(alone.hasFocus())
}

// A box opens on the action it names as its default, with the ring already showing.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Confirm")
    dlg.addButton("Yes", Dialog.BtnYes)
    let no = dlg.addButton("No", Dialog.BtnNo, true)

    var checked: bool
    host.app.sigFrame += func|host = &host, no, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        checked[] = true

        // Reading order would have opened on `Yes`, and a focused button answers Enter itself:
        // the box would have answered yes to a question whose default is no.
        @assert(no.hasFocus())
        @assert(no.hasVisibleFocus())
        @assert(host.clickModalButton(Dialog.BtnNo))
    }

    @assert(dlg.doModal() == Dialog.BtnNo)
    @assert(checked)
}

// A box with something to fill in opens on that instead, and its default still answers Enter.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let dlg   = Dialog.create(&host.surface, 260, 160, title: "Rename")
    let field = EditBox.create(dlg.view(), "name", {20, 20, 180, 26})
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.addButton("Cancel", Dialog.BtnCancel)

    // The bar is docked, so it only stands below the field once the box has been laid out — and
    // reading order is what decides which of the two the keyboard opens on.
    dlg.applyLayout()

    var checked: bool
    host.app.sigFrame += func|host = &host, field, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        checked[] = true

        @assert(field.hasFocus())

        // The field declines Enter, so the box still answers with the action it named.
        host.keyPress(Input.Key.Return)
    }

    @assert(dlg.doModal() == Dialog.BtnOk)
    @assert(checked)
}

// A control the reader would act on is passed over, and the box opens on its named default.
//
// A confirmation carrying a `Do not ask again` checkbox reads first, so the box opened with the
// ring on the checkbox: the reader was pointed at a preference instead of at the question, and
// the first Space toggled it rather than answering. The rule is the flag, not the widget, so a
// toggle beside the checkbox is passed over for the same reason and without naming its type.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let dlg    = Dialog.create(&host.surface, 260, 170, title: "Confirm")
    let again  = CheckButton.create(dlg.view(), "Do not ask again", {20, 20, 180, 26})
    let toggle = ToggleButton.create(dlg.view(), {20, 56, 56, 26})
    dlg.addButton("Yes", Dialog.BtnYes)
    let no = dlg.addButton("No", Dialog.BtnNo, true)
    dlg.applyLayout()

    // Both read before the action bar, so either is what the box would have opened on.
    @assert(FocusOrder.collect(dlg.surface!.wnd).first() == cast(*Wnd) again)
    @assert(again.wndFlags.has(.ActivatesOnKey) and toggle.wndFlags.has(.ActivatesOnKey))

    var checked: bool
    host.app.sigFrame += func|host = &host, again, toggle, no, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        checked[] = true

        @assert(no.hasFocus())
        @assert(!again.hasFocus() and !toggle.hasFocus())

        // Passed over is not left out: the ring still wraps onto the options.
        host.keyPress(Input.Key.Tab)
        @assert(again.hasFocus())

        no.setFocus()
        @assert(host.clickModalButton(Dialog.BtnNo))
    }

    @assert(dlg.doModal() == Dialog.BtnNo)
    @assert(checked)
}

// What the ring looks like on a control that has nothing else to show for the focus.
//
// The image is the contract: a rule inside the button, one accent, and nothing on the same button
// when the pointer is what pressed it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 64)
    defer host.shutdown()

    let button = PushButton.create(&host.root, "Go", {20, 16, 80, 32})
    let idle   = host.render()
    Pixel.Testing.assertImageGolden(&idle, "focus.ring.absent")

    // Tab is what turns the ring on, so this goes through the real navigation.
    host.keyPress(Input.Key.Tab)
    @assert(button.hasVisibleFocus())

    let ringed = host.render()
    @assert(Memory.compare(ringed.pixels.buffer, idle.pixels.buffer, ringed.byteCount) != 0)
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.pushbutton")

    // A press takes the ring away again without taking the focus. The image is not compared
    // against the idle one: the pointer is over the button now, which is a state of its own.
    host.clickWnd(button)
    @assert(button.hasFocus() and !button.hasVisibleFocus())
    let pressed = host.render()
    @assert(Memory.compare(pressed.pixels.buffer, ringed.pixels.buffer, pressed.byteCount) != 0)
}

// What an action bar looks like when the keyboard has moved off the action the box named.
//
// The image is the contract: one filled action at a time, and it is the one the ring stands on,
// so the bar never shows two answers to the same question.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 64)
    defer host.shutdown()

    let bar    = Wnd.create'Wnd(&host.root, {0, 0, 240, 64})
    let ok     = PushButton.create(bar, "Ok", {20, 16, 90, 32}, form: .Default)
    let cancel = PushButton.create(bar, "Cancel", {130, 16, 90, 32})

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    ok.setFocus()
    host.app.setFocusVisible(true)
    host.settleAnimations()
    let onDefault = host.render()
    Pixel.Testing.assertImageGolden(&onDefault, "focus.default.on.named.action")

    // The fill crosses the bar as an animation, so the image is taken once it has arrived.
    host.keyPress(Input.Key.Right)
    @assert(cancel.hasFocus())
    host.settleAnimations()
    let onOther = host.render()
    @assert(Memory.compare(onOther.pixels.buffer, onDefault.pixels.buffer, onOther.byteCount) != 0)
    Pixel.Testing.assertImageGolden(&onOther, "focus.default.follows.keyboard")
}

// The same ring on a button filled with the accent, which is the one a box opens on.
//
// The ring points in the accent, so over that fill it has to be drawn in the ink the fill carries
// or there is nothing left to see. The image is the contract.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 64)
    defer host.shutdown()

    let button = PushButton.create(&host.root, "Go", {20, 16, 80, 32}, form: .Default)
    let idle   = host.render()

    host.keyPress(Input.Key.Tab)
    @assert(button.hasVisibleFocus())

    let ringed = host.render()
    @assert(Memory.compare(ringed.pixels.buffer, idle.pixels.buffer, ringed.byteCount) != 0)
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.pushbutton.default")
}

// The ring takes the corner of the control, and the corner is a decision the palette makes.
//
// The Swag palettes point a push button at the edit tiles, so the same button is a capsule under
// the neutral theme and a square-cornered tile under theirs. The image is the contract: a mark
// shaped for the capsule and carried onto the tile crosses its own control at all four corners.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 64)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.app.notifyThemeChanged()

    let button = PushButton.create(&host.root, "Go", {20, 16, 80, 32})
    host.keyPress(Input.Key.Tab)
    @assert(button.hasVisibleFocus())

    host.settleAnimations()
    let ringed = host.render()
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.pushbutton.swag")
}

// The ring on a switch that is on, which is the state a keyboard most often lands on.
//
// A switched-on toggle is filled with the accent, and the accent is what the ring points in, so
// the ring has to be drawn in the ink that fill carries. The image is the contract; before it
// existed the mark simply disappeared on half of the toggles of a surface.
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 56)
    defer host.shutdown()

    let toggle = ToggleButton.create(&host.root, {20, 15, 56, 26})
    toggle.setChecked(true)

    host.keyPress(Input.Key.Tab)
    @assert(toggle.hasVisibleFocus())

    host.settleAnimations()
    let ringed = host.render()
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.toggle.on")
}
