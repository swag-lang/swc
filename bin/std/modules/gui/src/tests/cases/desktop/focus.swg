#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Two actual surfaces receive their own Tab, printable input and registered shortcuts. A focus
// request before display or on a background surface is remembered without activating it.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var app: Application
    app.setMotionPreference(.Reduced)
    let primary   = expect app.createSurface(40, 52, 260, 175, surfaceId: "desktop-focus-primary")
    let secondary = expect app.createSurface(325, 52, 260, 175, surfaceId: "desktop-focus-secondary")
    let first     = EditBox.create(primary.view(), "", {20, 20, 130, 28})
    let second    = EditBox.create(secondary.view(), "", {20, 20, 130, 28})
    primary.show()
    var firstInput = Testing.DesktopInput.create(&app, primary)
    second.setFocus()
    Swag.require(app.nativeFocusSurface == primary and not second.hasFocus())
    firstInput.shortcut(.Tab, .None)
    Swag.require(first.hasVisibleFocus())

    let commands = Memory.new'u32()
    defer
    {
        secondary.view().hookOnEvent = null
        Memory.delete(commands)
    }

    secondary.view().registerKeyShortcut(.Control, .K, "test.focus.secondary")
    secondary.view().hookOnEvent = func|commands|(_, event)
    {
        if event is CommandEvent as cmd where cmd.id == "test.focus.secondary"
        {
            commands[] += 1
            return true
        }

        return false
    }

    secondary.show()
    var secondInput = Testing.DesktopInput.create(&app, secondary)
    Swag.require(second.hasFocus() and not second.hasVisibleFocus() and not first.hasFocus())
    secondary.clearFocus()
    secondInput.shortcut(.Tab, .None)
    Swag.require(second.hasVisibleFocus() and not first.hasFocus())
    secondInput.shortcut(.B, .None)
    secondInput.shortcut(.K, .Control)
    Swag.require(second.text() == "b" and first.text() == "" and commands[] == 1)

    Swag.require(second.hasVisibleFocus() and not first.hasFocus())
    firstInput.focusNative()
    app.runFrame()
    Swag.require(first.hasFocus() and not first.hasVisibleFocus())
    firstInput.shortcut(.A, .None)
    firstInput.shortcut(.K, .Control)
    Swag.require(first.text() == "a" and second.text() == "b" and commands[] == 1)
}
