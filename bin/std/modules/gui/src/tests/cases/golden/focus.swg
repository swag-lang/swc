#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

const FocusHeadless_Default = "FocusHeadless.Default"
const FocusHeadless_Cancel  = "FocusHeadless.Cancel"

// A form built the way a card is built: a docked action bar created before the content that fills
// what is left over, so creation order and reading order disagree on purpose.
struct FocusHeadlessCard
{
    panel:   *Wnd                 // Raised panel holding the whole card.
    actions: *StackLayoutCtrl     // Action bar docked at the bottom.
    body:    *Wnd                 // Content filling what the bar leaves.
    field:   *EditBox             // Field of the body.
    browse:  *PushButton          // Trailing action on the same line as the field.
    submit:  *PushButton          // Dominant action, in the bar.
}

// Builds a laid-out `FocusHeadlessCard` inside `parent`, at `rect`.
func focusHeadlessCard(parent: *Wnd, rect: Math.Rectangle)->FocusHeadlessCard
{
    var result: #returntype

    result.panel = Wnd.create'Wnd(parent, rect)

    result.actions = StackLayoutCtrl.create(result.panel, .Right, {0, 0, 0, 30})
    result.actions.dockStyle = .Bottom
    result.submit  = PushButton.create(result.actions, "Go")

    result.body           = Wnd.create'Wnd(result.panel)
    result.body.dockStyle = .Center
    result.field          = EditBox.create(result.body, "", {0, 0, 100, 24})
    result.browse         = PushButton.create(result.body, "...", {110, 0, 40, 24})

    result.panel.applyLayout()
    result.actions.computeLayout()
    return result
}

// A canvas has no traversal stop, but its root hook still receives game-style keyboard input.

// The ring reads the way the eye does, not the way the tree was built.

// Two columns keep their own fields together instead of interleaving row by row.

// Tab walks the ring and wraps around, Shift+Tab walks it backwards.

// The ring shows only while the keyboard is what moved the focus.

// Native surface deactivation removes the logical focus and its caret, then activation restores
// the recorded stop instead of leaving a control painted as active in a background application.

// A hidden or disabled control hands the keyboard to what follows it.

// A control taken off the surface hands the keyboard on rather than dropping it.
//
// Destroying is deferred, so a focus left pointing into the window is only cleared a frame later,
// with nothing to say where it should have gone. The next Tab then restarted at the top.

// A Lost callback can dismantle the old focused subtree without recursively losing focus again.
// The new owner is published before that callback runs, so releaseFocus sees that the keyboard
// has already left the subtree being destroyed.

// A composite is one stop, and the focus lands on the part of it that reads the keys.

// A group of options is one stop, entered on the option that is checked.

// Enter and Escape stand for the two standard buttons of the surface.

// The arrows walk the group the focus stands in; Tab is what crosses the whole box.

// A list keeps the keys it reads and hands back the ones it does not.
//
// A control that marks every key handled makes the surface it sits on unanswerable: the box cannot
// be backed out of and the traversal cannot leave the control. A file box opens the keyboard on its
// file list, which is exactly where Escape and Tab have to keep working.

// The accent stands on the action Enter would run, which a focused button is.
//
// A box names one dominant action, and the keyboard can stand on another. Left where it was
// created, the fill said Enter would run something other than what the ring points at.

// A box gives the keyboard back to the control it was opened from.
//
// The surface under a modal keeps its own focus while the box runs, so backing out of the box
// resumes the form where the reader left it instead of restarting the traversal somewhere else.

// A stop alone in its group answers the arrows with the whole ring, and a modified arrow is a
// gesture of the control rather than a traversal.

// A box opens on the action it names as its default, with the ring already showing.

// A callback cannot take the keyboard away from a modal box through its disabled caller.

// A box with something to fill in opens on that instead, and its default still answers Enter.

// A control the reader would act on is passed over, and the box opens on its named default.
//
// A confirmation carrying a `Do not ask again` checkbox reads first, so the box opened with the
// ring on the checkbox: the reader was pointed at a preference instead of at the question, and
// the first Space toggled it rather than answering. The rule is the flag, not the widget, so a
// toggle beside the checkbox is passed over for the same reason and without naming its type.

// What the ring looks like on a control that has nothing else to show for the focus.
//
// The image is the contract: a rule inside the button, one accent, and nothing on the same button
// when the pointer is what pressed it.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 64)

    let button = PushButton.create(&host.root, "Go", {20, 16, 80, 32})
    let idle   = host.render()
    Pixel.Testing.assertImageGolden(&idle, "focus.ring.absent")

    // Tab is what turns the ring on, so this goes through the real navigation.
    host.keyPress(.Tab)
    Swag.assert(button.hasVisibleFocus())

    let ringed = host.render()
    Swag.assert(not Slice.equals(ringed.pixels.toSlice(), idle.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.pushbutton")

    // A press takes the ring away again without taking the focus. The image is not compared
    // against the idle one: the pointer is over the button now, which is a state of its own.
    host.clickWnd(button)
    Swag.assert(button.hasFocus() and not button.hasVisibleFocus())
    let pressed = host.render()
    Swag.assert(not Slice.equals(pressed.pixels.toSlice(), ringed.pixels.toSlice()))
}

// What an action bar looks like when the keyboard has moved off the action the box named.
//
// The image is the contract: one filled action at a time, and it is the one the ring stands on,
// so the bar never shows two answers to the same question.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 64)

    let bar    = Wnd.create'Wnd(&host.root, {0, 0, 240, 64})
    let ok     = PushButton.create(bar, "Ok", {20, 16, 90, 32}, form: .Default)
    let cancel = PushButton.create(bar, "Cancel", {130, 16, 90, 32})

    host.surface.defaultButton = ok
    host.surface.cancelButton  = cancel

    ok.setFocus()
    host.app.setFocusVisible(true)
    let onDefault = host.renderSettled()
    Pixel.Testing.assertImageGolden(&onDefault, "focus.default.on.named.action")

    // The fill crosses the bar as an animation, so the image is taken once it has arrived.
    host.keyPress(.Right)
    Swag.assert(cancel.hasFocus())
    let onOther = host.renderSettled()
    Swag.assert(not Slice.equals(onOther.pixels.toSlice(), onDefault.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&onOther, "focus.default.follows.keyboard")
}

// The same ring on a button filled with the accent, which is the one a box opens on.
//
// The ring points in the accent, so over that fill it has to be drawn in the ink the fill carries
// or there is nothing left to see. The image is the contract.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 64)

    let button = PushButton.create(&host.root, "Go", {20, 16, 80, 32}, form: .Default)
    let idle   = host.render()

    host.keyPress(.Tab)
    Swag.assert(button.hasVisibleFocus())

    let ringed = host.render()
    Swag.assert(not Slice.equals(ringed.pixels.toSlice(), idle.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.pushbutton.default")
}

// The ring on a switch that is on, which is the state a keyboard most often lands on.
//
// A switched-on toggle is filled with the accent, and the accent is what the ring points in, so
// the ring has to be drawn in the ink that fill carries. The image is the contract; before it
// existed the mark simply disappeared on half of the toggles of a surface.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 56)

    let toggle = ToggleButton.create(&host.root, {20, 15, 56, 26})
    toggle.setChecked(true)

    host.keyPress(.Tab)
    Swag.assert(toggle.hasVisibleFocus())

    let ringed = host.renderSettled()
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.toggle.on")
}
