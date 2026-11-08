#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A persistent editor mode is visible beside its operation and can be left by key or pointer.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    let shape = testAddShape(capture, 20, 20, 60, 40)
    Swag.require(main.keyShortcut(.Control, .L) == ActionSelection.Freeze)
    Swag.require(not main.taskStrip.frozenPanel.isLocallyVisible())

    main.editWnd.editView.setFocus()
    host.shortcut(.L, .Control)
    Swag.require(main.freezeSel and shape.freeze)
    Swag.require(main.taskStrip.frozenPanel.isLocallyVisible())
    Swag.require(main.taskStrip.frozenButton.text() == appStrings().ui_Frozen)
    Swag.require(main.taskStrip.frozenButton.iconColor == main.themeColors().arc)

    host.clickWnd(main.taskStrip.frozenButton)
    Swag.require(not main.freezeSel)
    Swag.require(not main.taskStrip.frozenPanel.isLocallyVisible())
}

// A missing capture key remains beside Capture, with the exact unavailable key on request.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    main.takenHotKeys.clear()
    main.taskStrip.showUnavailableShortcuts(false)
    Swag.require(not main.taskStrip.shortcutPanel.isLocallyVisible())
    main.takenHotKeys.add(String.from("PrintScreen"))
    main.taskStrip.showUnavailableShortcuts(true)
    Swag.require(main.taskStrip.shortcutPanel.isLocallyVisible())
    Swag.require(main.taskStrip.shortcutWarning.iconColor == main.themeColors().critical)

    var inspected: bool
    host.app.sigFrame += func|host = &host, inspected = &inspected|(_)
    {
        if inspected[] do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 4)
        Swag.require(menu.items[1]!.name.raw == "PrintScreen" and menu.items[1]!.disabled)
        Swag.require(menu.items[3]!.name.raw == appStrings().msg_ShortcutsUnavailableHelp and menu.items[3]!.disabled)
        inspected[] = true
        Swag.require(host.dismissPopupMenu())
    }

    host.click(main.taskStrip.shortcutWarning.surfaceRect().center())
    Swag.require(inspected)
    Swag.require(main.taskStrip.shortcutPanel.isLocallyVisible())
}

// Both lasting statuses retain distinct controls and leave room between the strip groups in French.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false, caption: true, dpiScale: 1.25)
    defer
    {
        discard catch main.appearanceButton.setAppearanceLanguage(Gui.ReferenceLanguage)
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    expect main.appearanceButton.setAppearanceLanguage("fr")
    main.takenHotKeys.clear()
    main.takenHotKeys.add(String.from("PrintScreen"))
    main.taskStrip.showUnavailableShortcuts(true)
    main.freezeSelection(true)
    main.applyLayout()

    Swag.require(main.taskStrip.frozenButton.text() == appStrings().ui_Frozen)
    Swag.require(main.taskStrip.shortcutWarning.text() == appStrings().ui_ShortcutsUnavailable)
    Swag.require(main.taskStrip.frozenButton.iconColor == main.themeColors().arc)
    Swag.require(main.taskStrip.shortcutWarning.iconColor == main.themeColors().critical)
    Swag.require(main.taskStrip.leading.surfaceRect().right() < main.taskStrip.trailing.surfaceRect().x)
    Swag.require(host.surfaceWnd.captionContentRect().width > 0)
    Swag.require(not main.taskStrip.shortcutPanel.surfaceRect().intersects(main.taskStrip.frozenPanel.surfaceRect()))
    Swag.require(main.taskStrip.shortcutPanel.surfaceRect().y >= host.theme.metrics.wnd_StripHeight)

    let besideInspector = main.taskStrip.frozenPanel.position.x
    main.inspector.setFolded(true)
    Swag.require(main.taskStrip.frozenPanel.position.x > besideInspector)
    main.inspector.setFolded(false)
    Swag.require(main.taskStrip.frozenPanel.position.x == besideInspector)

    host.theme.setDark()
    host.notify(.ThemeChanged)
    Swag.require(main.taskStrip.frozenButton.iconColor == main.themeColors().arc)
    Swag.require(main.taskStrip.shortcutWarning.iconColor == main.themeColors().critical)
}
