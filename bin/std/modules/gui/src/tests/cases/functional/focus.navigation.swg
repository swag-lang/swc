#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A programmatic choice and ordinary keys leave the indicator off. Tab turns it on and a click
// turns it off again, even if the focused window continues to read the keys.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)
    let first = PushButton.create(&host.root, "First", {20, 20, 100, 24})
    let last  = EditBox.create(&host.root, "", {20, 60, 100, 24})

    first.setFocus()
    Swag.require(first.hasFocus() and not first.hasVisibleFocus())
    host.keyPress(.F2)
    Swag.require(not first.hasVisibleFocus())
    Swag.require(first.focusNext() and last.hasFocus() and not last.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(first.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(last.hasVisibleFocus())
    first.setFocus()
    Swag.require(first.hasVisibleFocus())

    host.clickWnd(last)
    Swag.require(last.hasFocus() and not last.hasVisibleFocus())
    first.setFocus()
    Swag.require(first.hasFocus() and not first.hasVisibleFocus())
}

// Restoring a surface restores its recipient. Its prior ring cannot come back after a click
// and later Tab elsewhere.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)
    let first  = PushButton.create(&host.root, "First", {20, 20, 100, 24})
    let other  = expect host.app.createSurface(330, 0, 180, 100)
    let field  = EditBox.create(other.view(), "", {12, 12, 100, 24})
    let button = PushButton.create(other.view(), "Next", {12, 48, 100, 24})
    other.show()

    host.keyPress(.Tab)
    Swag.require(first.hasVisibleFocus())
    host.clickWnd(field)
    Swag.require(field.hasFocus() and not field.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(button.hasVisibleFocus())

    Swag.require(host.surface.restoreFocus())
    Swag.require(first.hasFocus() and not first.hasVisibleFocus())
}

// Closing a dialog with Escape can restore the caller's keys, but its former ring stays off
// until a navigation gesture in that surface.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 280)
    let caller = PushButton.create(&host.root, "Caller", {20, 20, 100, 24})
    host.keyPress(.Tab)
    Swag.require(caller.hasVisibleFocus())

    let dialog = Dialog.create(&host.surface, 220, 140, title: "Dialog")
    let cancel = dialog.addButton("Cancel", Dialog.BtnCancel, true)
    host.app.sigFrame += func|&host, cancel|(_)
    {
        Swag.require(cancel.hasFocus() and not cancel.hasVisibleFocus())
        host.keyPress(.Escape)
    }

    Swag.require(dialog.doModal() == Dialog.BtnCancel)
    Swag.require(caller.hasFocus() and not caller.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(caller.hasVisibleFocus())
}

// Native keyboard messages are admitted only for the confirmed source. Committed text can be
// the first input and must seed that surface's own root.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)
    let first = EditBox.create(&host.root, "", {20, 20, 100, 24})
    let other = expect host.app.createSurface(350, 0, 180, 100)
    let field = EditBox.create(other.view(), "", {12, 12, 100, 24})
    other.show()

    first.setFocus()
    host.app.updateNativeFocus(other)
    Swag.require(host.app.keyboardTarget(other, seed: true) == other.view())
    Swag.require(host.app.keyboardTarget(&host.surface, seed: true) == null)
    field.setFocus()
    host.app.sendRuneEvent(.A, 'a', .None, &host.surface)
    Swag.require(field.text() == "" and first.text() == "")
    host.app.sendRuneEvent(.B, 'b', .None, other)
    Swag.require(field.text() == "b" and not field.hasVisibleFocus())
    host.app.updateNativeFocus(null)
    Swag.require(host.app.keyboardTarget(other, seed: true) == null)
}

// Explicit sibling ranks keep Tab and Shift+Tab inverse when responsive layout moves controls.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 180)
    let first = EditBox.create(&host.root, "", {200, 80, 100, 24})
    let panel = Wnd.create'Wnd(&host.root, {12, 56, 140, 100})
    let inner = PasswordEdit.create(panel, {4, 5, 120, 24})
    let last  = PushButton.create(&host.root, "Finish", {12, 12, 100, 24})
    first.tabIndex = 0
    panel.tabIndex = 1
    last.tabIndex  = 2

    host.keyPress(.Tab)
    Swag.require(first.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(inner.hasVisibleFocus())
    panel.setPosition({190, 6, 140, 100})
    first.setPosition({6, 112, 100, 24})
    host.keyPress(.Tab)
    Swag.require(last.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(inner.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(first.hasVisibleFocus())
    panel.disable()
    host.keyPress(.Tab)
    Swag.require(last.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(first.hasVisibleFocus())
}

// Restacking overlapping siblings and duplicate Tab ranks leave their attachment order intact.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 160)
    let first = PushButton.create(&host.root, "First", {20, 20, 100, 24})
    let last  = PushButton.create(&host.root, "Last", {20, 20, 100, 24})
    first.bringToFront()
    Swag.require(FocusOrder.around(first).first() == cast(*Wnd, first))
    first.tabIndex = 3
    last.tabIndex  = 3
    host.keyPress(.Tab)
    Swag.require(first.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(last.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(first.hasVisibleFocus())
}

// The same radio slot precedes the intervening button regardless of checked or disabled members.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180)
    let first   = RadioButton.create(&host.root, "One", {20, 20, 100, 24})
    let between = PushButton.create(&host.root, "Between", {20, 60, 100, 24})
    let second  = RadioButton.create(&host.root, "Two", {20, 100, 100, 24})
    first.groupId  = "choice"
    second.groupId = "choice"
    second.setChecked(true)

    host.keyPress(.Tab)
    Swag.require(second.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(between.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(second.hasVisibleFocus())
    host.keyPress(.Up)
    Swag.require(first.hasVisibleFocus() and first.isChecked())
    host.keyPress(.Down, .Control)
    Swag.require(first.hasVisibleFocus() and first.isChecked())
    second.setChecked(true)
    first.hide()
    host.surface.clearFocus()
    host.keyPress(.Tab)
    Swag.require(second.hasVisibleFocus())
    host.keyPress(.Tab)
    Swag.require(between.hasVisibleFocus())
}

// Updating action availability preserves the current input mode, including after focus transfer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)
    let first = PushButton.create(&host.root, "First", {20, 20, 100, 24})
    let other = PushButton.create(&host.root, "Other", {20, 60, 100, 24})
    first.setFocus()
    first.disable()
    Swag.require(other.hasFocus() and not other.hasVisibleFocus())
    first.enable()
    host.keyPress(.Tab)
    Swag.require(first.hasVisibleFocus())
    first.disable()
    Swag.require(other.hasVisibleFocus())
}

// A pointer gesture in the innermost dialog clears the indicators remembered by both callers.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    let caller = PushButton.create(&host.root, "Caller", {20, 20, 100, 24})
    host.keyPress(.Tab)
    Swag.require(caller.hasVisibleFocus())

    let outer = Dialog.create(&host.surface, 240, 160, title: "Outer")
    outer.addButton("Other", Dialog.BtnNo)
    let cancel = outer.addButton("Cancel", Dialog.BtnCancel, true)
    var stage: u32
    host.app.sigFrame += func|&host, outer, cancel, &stage|(_)
    {
        if stage == 1
        {
            stage = 2
            Swag.require(host.app.isInModalLoop() and not cancel.hasFocus())
            Swag.require(host.clickModalButton(Dialog.BtnCancel))
            return
        }

        if stage != 0 do
            return

        stage = 1
        Swag.require(cancel.hasFocus() and not cancel.hasVisibleFocus())
        host.keyPress(.Tab)
        host.keyPress(.Tab, .Shift)
        Swag.require(cancel.hasVisibleFocus())
        let inner = Dialog.create(unwrap outer.surface, 220, 140, title: "Inner")
        inner.addButton("Cancel", Dialog.BtnCancel, true)
        Swag.require(inner.doModal() == Dialog.BtnCancel)
        Swag.require(cancel.hasFocus() and not cancel.hasVisibleFocus())
        host.keyPress(.Escape)
    }

    Swag.require(outer.doModal() == Dialog.BtnCancel and stage == 2)
    Swag.require(caller.hasFocus() and not caller.hasVisibleFocus())
}

// A field can accept text with its resting outline. Tab exposes the keyboard outline.
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    let field = EditBox.create(&host.root, "", {20, 20, 145, 32})
    field.setFocus()
    host.sendRune(.A, 'a')
    let editing = host.renderSettled()
    Swag.require(field.text() == "a" and field.hasFocus() and not field.hasVisibleFocus())
    host.keyPress(.Tab)
    let keyboard = host.renderSettled()
    Swag.require(field.hasVisibleFocus())

    var borderChanged: bool
    for x in 12
    {
        let edge   = cast(u32, x) + 154
        let before = editing.pixelColor(edge, 36)
        Swag.require(before != field.themeColors().edit_FocusBorder)
        borderChanged = borderChanged or keyboard.pixelColor(edge, 36) != before
    }

    Swag.require(borderChanged)
}

// An editor's surrounding frame responds to keyboard mode independently of its text recipient.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 150)
    let frame = Wnd.create'FrameWnd(&host.root, {20, 20, 180, 108})
    frame.setFrameForm(.Square)
    frame.setFrameFlags(.FocusBorder)
    let field = EditBox.create(frame, "", {24, 28, 100, 24})
    field.setFocus()
    let quiet = host.renderSettled()
    host.keyPress(.Tab)
    let keyboard = host.renderSettled()
    Swag.require(field.hasVisibleFocus())
    host.clickWnd(field)
    let pointer = host.renderSettled()
    Swag.require(field.hasFocus() and not field.hasVisibleFocus())
    var borderChanged: bool
    for y in 8
    {
        let edge    = 20 + cast(u32, y)
        let resting = quiet.pixelColor(100, edge)
        borderChanged = borderChanged or resting != keyboard.pixelColor(100, edge)
        Swag.require(resting == pointer.pixelColor(100, edge))
    }

    Swag.require(borderChanged)
}

// A destination that declines Tab does not strand traversal in either direction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 160)
    let first  = EditBox.create(&host.root, "", {18, 18, 100, 24})
    let vetoed = PushButton.create(&host.root, "Unavailable", {18, 52, 100, 24})
    let last   = EditBox.create(&host.root, "", {18, 86, 100, 24})
    vetoed.hookOnEvent = func(_, event)
    {
        if event is FocusEvent as focus where focus.kind == .CanGain do
            focus.canChangeFocus = false
        return false
    }

    first.setFocus()
    host.keyPress(.Tab)
    Swag.require(last.hasVisibleFocus())
    host.keyPress(.Tab, .Shift)
    Swag.require(first.hasVisibleFocus())
}

// A control can keep its current editing session by vetoing CanLose.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 160)
    let first = EditBox.create(&host.root, "", {18, 18, 100, 24})
    discard PushButton.create(&host.root, "Second", {18, 52, 100, 24})
    discard PushButton.create(&host.root, "Third", {18, 86, 100, 24})
    first.hookOnEvent = func(_, event)
    {
        if event is FocusEvent as focus where focus.kind == .CanLose do
            focus.canChangeFocus = false
        return false
    }

    first.setFocus()
    host.keyPress(.Tab)
    Swag.require(first.hasFocus() and not first.hasVisibleFocus())
}

// Pointer input delivered by a focus callback takes precedence over the indicator it interrupted.
#test
{
    var host: Testing.HeadlessHost
    host.setup(340, 180)
    let first = EditBox.create(&host.root, "", {18, 18, 100, 24})
    let next  = PushButton.create(&host.root, "Next", {18, 56, 100, 24})
    let blank = Wnd.create'Wnd(&host.root, {150, 20, 140, 100})
    host.keyPress(.Tab)
    Swag.require(first.hasVisibleFocus())

    next.hookOnEvent = func|blank|(_, event)
    {
        if event is FocusEvent as focus where focus.kind == .CanGain do
            blank.app().focusPointerTarget(blank)
        return false
    }

    next.setFocus()
    Swag.require(next.hasFocus() and not next.hasVisibleFocus())
}

// A caller can veto an ordinary transfer. Once a modal starts it must own its keyboard anyway.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 280)
    let caller = EditBox.create(&host.root, "", {20, 20, 160, 26})
    caller.hookOnEvent = func(_, event)
    {
        if event is FocusEvent as focus where focus.kind == .CanLose do
            focus.canChangeFocus = false
        return false
    }

    caller.setFocus()

    let dialog = Dialog.create(&host.surface, 240, 150, title: "Modal")
    let cancel = dialog.addButton("Cancel", Dialog.BtnCancel, true)
    var checked: bool
    host.app.sigFrame += func|&host, caller, cancel, &checked|(_)
    {
        if checked do
            return
        checked = true
        Swag.require(not caller.hasFocus())
        host.keyPress(.Tab)
        Swag.require(cancel.hasVisibleFocus())
        host.keyPress(.Escape)
    }

    Swag.require(dialog.doModal() == Dialog.BtnCancel and checked and caller.hasFocus())
}
