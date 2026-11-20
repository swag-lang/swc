#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// The notification icon belongs to explicit resident mode, and both gestures open a popup.
#[Swag.TestTag("integration.capture.tray")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let app     = journey.app
    let surface = journey.surface
    let handle  = surface.win32Handle()
    Swag.require(handle != null)
    main.showHub()
    let initial = main.residentPanel
    let hub     = unwrap initial
    Swag.require(hub.surface!.flags.has(.SmallCaption) and not surface.hasTrayIcon())

    let iconId = 1 << 16
    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_CONTEXTMENU)
    app.runFrame()
    Swag.require(main.residentPanel == hub and main.workspace == .Hub)

    hub.choose(ActionGlobal.Minimize)
    journey.waitFor("notification icon", func|main|()->bool => main.workspace == .Resident)
    Swag.require(surface.isHidden and surface.hasTrayIcon())

    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_CONTEXTMENU)
    journey.waitFor("context menu", func|main|()->bool => main.residentPanel != null)
    let contextMenu = main.residentPanel
    let menu = unwrap contextMenu
    Swag.require(menu.placement == .AtPointer and testPanelOffers(menu, ActionGlobal.ShowHub))
    var escape = KeyEvent{kind: .Pressed, key: .Escape}
    menu.sendEvent(&escape)
    Swag.require(escape.accepted and main.residentPanel == null and surface.hasTrayIcon())

    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_LBUTTONDBLCLK)
    journey.waitFor("activation menu", func|main|()->bool => main.residentPanel != null)
    let activationMenu = main.residentPanel
    Swag.require(activationMenu!.placement == .AtPointer)
    activationMenu.choose(ActionGlobal.ShowHub)
    journey.waitFor("capture window", func|main|()->bool => main.workspace == .Hub)
    Swag.require(not surface.hasTrayIcon() and surface.isHidden)

    main.sendCommandEvent(ActionGlobal.ShowEditor)
    Swag.require(main.workspace == .Editor and not surface.isHidden and main.residentPanel == null)
    var close = SysCommandEvent{kind: .Close}
    main.sendEvent(&close)
    Swag.require(close.accepted and not surface.hasTrayIcon())
    let frameLimit = cast(u32, app.timing.frameCount) + 15
    app.maxRunFrame = frameLimit
    Swag.require(app.run() == 0 and app.timing.frameCount < frameLimit)
    Swag.require(not surface.hasTrayIcon())
}

// Exercise the actual Shell icon with desktop input; the callback-only test above cannot
// observe Windows foreground changes or a missing notification-area registration.
#[Swag.TestTag("integration.capture.tray.desktop")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let surface = journey.surface
    main.sendCommandEvent(ActionGlobal.Minimize)
    Swag.require(main.workspace == .Resident and surface.hasTrayIcon())

    // An icon in the closed overflow area first exposes the chevron's bounds. Open it only
    // when needed: clicking the chevron again would close a flyout left open by another test.
    if not Gui.Testing.isTrayIconInOverflow(surface)
    {
        Gui.Testing.clickTrayIcon(journey.app, surface, .Left)
        var opened: Time.Stopwatch
        opened.start()
        while not Gui.Testing.isTrayIconInOverflow(surface) and opened.elapsedMilliseconds() < 500 do
            journey.app.runFrame()
    }

    var settle: Time.Stopwatch
    settle.start()
    while settle.elapsedMilliseconds() < 500 do
        journey.app.runFrame()
    Gui.Testing.clickTrayIcon(journey.app, surface, .Right)
    var watch: Time.Stopwatch
    watch.start()
    while main.residentPanel == null and watch.elapsedMilliseconds() < 3000 do
        journey.app.runFrame()
    Swag.require(main.residentPanel != null, "the desktop right-click must open the home")
    let menu = main.residentPanel
    Swag.require(menu.placement == .AtPointer)
    watch.restart()
    while watch.elapsedMilliseconds() < 180
    {
        journey.app.runFrame()
        Swag.require(main.residentPanel == menu, "the desktop tray menu must stay open")
    }

    // Cursor and delay share one row and keep the pointer home open while they are chosen.
    scope
    {
        var input          = Gui.Testing.DesktopInput.create(journey.app, unwrap menu.surface)
        let choices        = assume cast(*StackLayoutCtrl, menu.menu.children[1])
        let cursor         = assume cast(*IconButton, choices.children[0])
        let previousCursor = main.captureOptions.captureCursor
        input.click(cursor)
        journey.waitFor("cursor toggle", func|main, previousCursor|()->bool =>
                        main.captureOptions.captureCursor != previousCursor)
        let delay = assume cast(*IconButton, choices.children[3])
        input.click(delay)
        journey.waitFor("capture delay", func|main|()->bool => main.captureOptions.delay == 5)
        Swag.require(main.residentPanel == menu and cursor.isChecked != previousCursor)

        // The same home owns Escape when opened as a pointer menu.
        input.shortcut(.Escape, .None)
    }

    watch.restart()
    while main.residentPanel != null and watch.elapsedMilliseconds() < 3000 do
        journey.app.runFrame()
    Swag.require(main.residentPanel == null and surface.isHidden,
                 "Escape must dismiss the home without opening the editor")
    journey.app.runFrame()

    Gui.Testing.clickTrayIcon(journey.app, surface, .Left, 2)
    watch.restart()
    while main.residentPanel == null and watch.elapsedMilliseconds() < 3000 do
        journey.app.runFrame()
    Swag.require(main.residentPanel != null, "the desktop double-click must open the tray menu")
    Swag.require(main.residentPanel.placement == .AtPointer)
    watch.restart()
    while watch.elapsedMilliseconds() < 180
    {
        journey.app.runFrame()
        Swag.require(main.residentPanel != null, "the desktop tray hub must stay open")
    }

    main.residentPanel.choose(ActionGlobal.ShowHub)
    journey.waitFor("capture window", func|main|()->bool => main.workspace == .Hub)
    Swag.require(not surface.hasTrayIcon() and main.residentPanel.surface!.flags.has(.SmallCaption))
    main.residentPanel.close()
}
