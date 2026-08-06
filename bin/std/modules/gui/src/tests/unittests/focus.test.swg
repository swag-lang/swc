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
        if dref checked do
            return
        dref checked = true

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
        if dref checked do
            return
        dref checked = true

        @assert(field.hasFocus())

        // The field declines Enter, so the box still answers with the action it named.
        host.keyPress(Input.Key.Return)
    }

    @assert(dlg.doModal() == Dialog.BtnOk)
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
