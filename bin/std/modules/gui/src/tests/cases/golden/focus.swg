#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A panel may place a button against its own edge without cutting off the focus ring.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 100)

    let panel  = Wnd.create'Wnd(&host.root, {20, 20, 80, 40})
    let button = PushButton.create(panel, "Go", {0, 4, 80, 32})
    let idle   = host.render()

    button.setFocus()
    host.app.setFocusVisible(true)
    let focused = host.render()

    Swag.require(focused.pixelColor(17, 40) != idle.pixelColor(17, 40))
    Swag.require(focused.pixelColor(103, 40) != idle.pixelColor(103, 40))
}

// What the ring looks like on a control that has nothing else to show for the focus.
//
// The image is the contract: a rule inside the button, one accent, and the same visible focus
// only while the keyboard selected it; a pointer press leaves no ring.
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
    Swag.require(button.hasVisibleFocus())

    let ringed = host.render()
    Swag.require(not Slice.equals(ringed.pixels.toSlice(), idle.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.pushbutton")

    // A pointer press clears the keyboard selection, while keeping its own hover state.
    host.clickWnd(button)
    Swag.require(not button.hasFocus() and not button.hasVisibleFocus())
    let pressed = host.render()
    Swag.require(not Slice.equals(pressed.pixels.toSlice(), ringed.pixels.toSlice()))
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
    Swag.require(cancel.hasFocus())
    let onOther = host.renderSettled()
    Swag.require(not Slice.equals(onOther.pixels.toSlice(), onDefault.pixels.toSlice()))
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
    Swag.require(button.hasVisibleFocus())

    let ringed = host.render()
    Swag.require(not Slice.equals(ringed.pixels.toSlice(), idle.pixels.toSlice()))
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
    Swag.require(toggle.hasVisibleFocus())

    let ringed = host.renderSettled()
    Pixel.Testing.assertImageGolden(&ringed, "focus.ring.toggle.on")
}
