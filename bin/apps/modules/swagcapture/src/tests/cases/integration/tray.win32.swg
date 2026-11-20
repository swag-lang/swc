#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel

// The Shell's version 4 callback posts its action so the Shell can finish the input gesture.
#[Swag.TestTag("integration.capture.tray")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main    = journey.main
    let surface = journey.surface
    let handle  = surface.win32Handle()
    Swag.require(handle != null)
    surface.setTrayIcon(expect Image.decode(".png", AppIcon), ProductName)
    surface.hide()

    let iconId = 1 << 16
    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_RBUTTONDOWN)
    Swag.require(main.residentPanel == null)
    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_CONTEXTMENU)
    Swag.require(main.residentPanel == null)
    journey.waitFor("home at pointer", func|main|()->bool => main.residentPanel != null)
    let menu = unwrap main.residentPanel
    Swag.require(menu.placement == .AtPointer)
    Swag.require(testPanelOffers(menu, ActionGlobal.ShowLibrary))
    Swag.require(not testPanelOffers(menu, ActionGlobal.ShowHub))
    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 120
    {
        journey.app.runFrame()
        Swag.require(main.residentPanel != null, "the tray menu must remain open through its focus watch")
    }

    menu.close()

    main.editorOptions.startup = .Hub
    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_LBUTTONUP)
    Swag.require(main.residentPanel == null)
    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_LBUTTONDBLCLK)
    Swag.require(main.residentPanel == null)
    journey.waitFor("tray hub", func|main|()->bool => main.residentPanel != null)
    let hub = main.residentPanel
    Swag.require(hub.placement == .Centered)
    watch.restart()
    while watch.elapsedMilliseconds() < 120
    {
        journey.app.runFrame()
        Swag.require(main.residentPanel != null, "the tray hub must remain open through its focus watch")
    }

    // Escape from the hub opens one nonmodal notification over the icon. Its checkbox disables
    // later reminders, even when an older saved notice count has reached zero.
    main.editorOptions.residentNotices = 0
    main.editorOptions.language        = .French
    main.setLanguage()
    var escape = KeyEvent{kind: .Pressed, key: .Escape}
    hub.sendEvent(&escape)
    Swag.require(escape.accepted)
    Swag.require(main.residentPanel == null)
    journey.app.runFrame()
    let notice = unwrap main.residentNotice
    Swag.require(journey.app.surfaces.count == 2)
    let choice = unwrap notice.optionCheck
    Swag.require(not choice.isChecked())
    let cardBounds   = notice.children[0].surfaceRect()
    let choiceBounds = choice.surfaceRect()
    Swag.require(choiceBounds.x >= cardBounds.x and
                 choiceBounds.right() <= cardBounds.right() and
                 choiceBounds.y >= cardBounds.y and
                 choiceBounds.bottom() <= cardBounds.bottom(),
                 "the notification checkbox must fit inside its card")
    let closeBounds = notice.closeButton.surfaceRect()
    Swag.require(closeBounds.x >= cardBounds.x and
                 closeBounds.right() <= cardBounds.right() and
                 closeBounds.y >= cardBounds.y and
                 closeBounds.bottom() <= cardBounds.bottom(),
                 "the notification close button must fit inside its card")
    var icon: Math.Rectangle
    if surface.trayIconBounds(&icon) do
        Swag.require(notice.surface!.position.bottom() <= icon.y or notice.surface.position.y >= icon.bottom(),
                     "the notification must stand beside the notification-area icon")
    choice.toggle()
    Swag.require(not main.editorOptions.showResidentNotice)
    watch.restart()
    while watch.elapsedMilliseconds() < 180
    {
        journey.app.runFrame()
        Swag.require(main.residentPanel == null, "Escape must not reopen the tray hub")
    }

    watch.restart()
    while (main.residentNotice != null or journey.app.surfaces.count != 1) and watch.elapsedMilliseconds() < 1000 do
        journey.app.runFrame()
    Swag.require(main.residentNotice == null, "the checked notification must dismiss itself")
    Swag.require(journey.app.surfaces.count == 1, "the checked notification must leave only the hidden editor")
    main.editorOptions.startup = .Editor
    discard Win32.SendMessageW(handle, Win32.WM_USER, 0, iconId | Win32.WM_LBUTTONDBLCLK)
    Swag.require(surface.isHidden)
    journey.waitFor("tray editor", func|surface|()->bool => not surface.isHidden)
    Swag.require(not surface.isHidden)
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
    surface.setTrayIcon(expect Image.decode(".png", AppIcon), ProductName)
    surface.hide()

    main.editorOptions.showResidentNotice = false

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
    Swag.require(main.residentPanel != null, "the desktop double-click must open the hub")
    Swag.require(main.residentPanel.placement == .Centered)
    watch.restart()
    while watch.elapsedMilliseconds() < 180
    {
        journey.app.runFrame()
        Swag.require(main.residentPanel != null, "the desktop tray hub must stay open")
    }

    main.residentPanel.close()
}
