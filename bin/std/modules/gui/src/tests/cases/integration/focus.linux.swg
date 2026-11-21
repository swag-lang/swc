#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

// X11 can queue a complete focus round trip before Swag next reads it. Reconciliation preserves
// the actual recipient, its ring and its edit session throughout those stale notifications.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var app: Application
    app.setMotionPreference(.Reduced)
    let primary   = expect app.createSurface(40, 52, 260, 175, surfaceId: "x11-focus-primary")
    let secondary = expect app.createSurface(325, 52, 260, 175, surfaceId: "x11-focus-secondary")
    let first     = EditBox.create(primary.view(), "", {20, 20, 125, 28})
    let second    = EditBox.create(secondary.view(), "", {20, 20, 125, 28})
    secondary.show()
    second.setFocus()
    primary.show()
    var input = Testing.DesktopInput.create(&app, primary)
    input.shortcut(.Tab, .None)
    Swag.require(first.hasVisibleFocus())

    var losses: u32
    first.sigFocusLost += func|&losses|(_) { losses += 1 }
    let context    = expect LinuxDesktop.ensure()
    let connection = unwrap context.connection
    expect LinuxDesktop.check(context, context.xcb_set_input_focus_checked(connection, 2, secondary.windowId, 0))
    expect LinuxDesktop.check(context, context.xcb_set_input_focus_checked(connection, 2, primary.windowId, 0))
    app.runFrame()
    Swag.require(app.nativeFocusSurface == primary and first.hasVisibleFocus() and not second.hasFocus() and losses == 0)
    input.shortcut(.A, .None)
    Swag.require(first.text() == "a" and second.text() == "")
}

// An activation request can be ignored by a window manager. Install an isolated owner marker
// with no manager listening and verify that the rejected request cannot publish logical focus.
#[Swag.TestTag("integration.desktop.no-window-manager")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var app: Application
    app.setMotionPreference(.Reduced)
    let primary   = expect app.createSurface(40, 52, 260, 175, surfaceId: "x11-focus-accepted")
    let secondary = expect app.createSurface(325, 52, 260, 175, surfaceId: "x11-focus-deferred")
    let first     = EditBox.create(primary.view(), "", {20, 20, 125, 28})
    let second    = EditBox.create(secondary.view(), "", {20, 20, 125, 28})
    secondary.show()
    primary.show()
    var input = Testing.DesktopInput.create(&app, primary)
    input.shortcut(.Tab, .None)

    let context = expect LinuxDesktop.ensure()
    let root    = context.screen.root
    let marker  = expect LinuxDesktop.atom(context, "_NET_SUPPORTING_WM_CHECK")
    let prior   = expect LinuxDesktop.readProperty(context, root, marker)
    Swag.require(prior.isEmpty(), "this focus denial scenario needs an X11 server without a window manager")
    let deleteProperty = expect LinuxDesktop.symbol'Linux.xcb_delete_property_checked_fn(unwrap context.library, "xcb_delete_property_checked")
    let owner = primary.windowId
    expect LinuxDesktop.property(context, root, marker, 33, 32, 1, &owner)
    defer expect LinuxDesktop.check(context, deleteProperty(unwrap context.connection, root, marker))
    secondary.requestNativeFocus()
    second.setFocus()
    app.runFrame()
    input.requireNativeFocus()
    Swag.require(first.hasVisibleFocus() and not second.hasFocus())
    input.shortcut(.A, .None)
    Swag.require(first.text() == "a" and second.text() == "")
}
