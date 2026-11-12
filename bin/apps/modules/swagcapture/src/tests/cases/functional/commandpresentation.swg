#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The caption menu reads the lens registrations, opens three levels where a family needs them,
// and sends a chosen command through the application's normal route.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, caption: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    Swag.require(main.menuLauncher.name.isEmpty())
    Swag.require(main.menuLauncher.position.x < main.position.width * 0.5)
    let menu = main.lens.createCommandMenu()
    menu.updateState()
    let expected = [appStrings().ui_MenuCapture, appStrings().ui_MenuFile, appStrings().ui_MenuEdit,
                    appStrings().ui_MenuImage, appStrings().ui_MenuView, Gui.strings().lens_Application]
    Swag.require(menu.items.count == expected.count)
    for name, index in expected do
        Swag.require(menu.items[index]!.name.raw == name and menu.items[index]!.popup != null)

    let capture = menu.items[0]!.popup
    let captureDirect = 10 + 2 * main.monitors.count
    Swag.require(capture.items[0]!.id == ActionCapture.Area)
    Swag.require(capture.items[1 + CaptureModeIds.count + main.monitors.count]!.separator)
    Swag.require(capture.items[2 + CaptureModeIds.count + main.monitors.count]!.id == ActionCapture.RecordVideo)
    Swag.require(capture.items[3 + CaptureModeIds.count + main.monitors.count]!.id == ActionCapture.RecordScreen)
    Swag.require(capture.items[4 + CaptureModeIds.count + main.monitors.count]!.id == ActionCapture.RecordActiveWindow)
    Swag.require(capture.items[captureDirect - 2]!.separator)
    Swag.require(capture.items[captureDirect - 1]!.id == ActionCapture.Record)
    Swag.require(capture.items[captureDirect]!.separator)
    var delay: *MenuCtrl?
    for item in capture.items where item and item.name.raw == appStrings().act_DelayBefore do
        delay = item.popup
    Swag.require(delay and delay.items.count == CaptureDelayIds.count)

    let file = menu.items[1]!.popup
    Swag.require(file.items[0]!.id == ActionFile.SaveAsImage and file.items[1 + FileStartIds.count]!.separator)

    let edit = menu.items[2]!.popup
    Swag.require(edit.items[0]!.id == ActionUndo.DoUndo and edit.items[2]!.separator)
    Swag.require(edit.items[3]!.id == ActionCopyPaste.Copy and edit.items[7]!.separator)
    var selection: *MenuCtrl?
    for item in edit.items where item and item.name.raw == appStrings().lens_Selection do
        selection = item.popup
    Swag.require(selection and selection.items.count == EditorSelectionIds.count)

    let image = menu.items[3]!.popup
    Swag.require(image.items[0]!.id == ActionCopyPaste.CopyAsImage)
    Swag.require(image.items[1]!.separator)
    Swag.require(image.items[2 + ImageGeometryIds.count]!.separator)
    Swag.require(image.items[3 + ImageGeometryIds.count + ImageFlattenIds.count]!.separator)
    for item in image.items where item and not item.separator do
        Swag.require(item.popup == null)

    let view = menu.items[4]!.popup
    Swag.require(view.items[0]!.id == ActionView.Inspector)
    Swag.require(view.items[ViewPanelIds.count]!.id == ActionGlobal.ShowLibrary)
    Swag.require(view.items[ViewPanelIds.count + 1]!.separator)
    Swag.require(view.items.count == ViewPanelIds.count + 1 + ViewZoomIds.count + 1)
    for item in view.items where item and not item.separator do
        Swag.require(item.popup == null)

    let application = menu.items[5]!.popup
    Swag.require(application.items.count == 8)
    Swag.require(application.items[1]!.separator and application.items[4]!.separator and application.items[6]!.separator)
    Swag.require(application.items[2]!.name.raw == Gui.strings().appearance_Theme)
    Swag.require(application.items[3]!.name.raw == Gui.strings().appearance_Language)
    Swag.require(application.items[2]!.popup.items.count == 3)
    Swag.require(application.items[3]!.popup.items.count == Gui.languages().count + 1)

    var chosen: bool
    host.app.sigFrame += func|host = &host, chosen = &chosen|(_)
    {
        if chosen[] do
            return
        Swag.require(host.openPopupSubMenu(appStrings().ui_MenuCapture))
        Swag.require(host.openPopupSubMenu(appStrings().act_DelayBefore))
        Swag.require(host.clickPopupMenuItem(ActionCaptureDelay.Delay3))
        chosen[] = true
    }
    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.app.sigFrame.clear()
    host.pump()
    Swag.require(chosen and main.captureOptions.delay == 3)
}

// Theme and language choices are commands in the shared menu, without opening the appearance sheet.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, caption: true)
    defer
    {
        discard catch main.appearanceButton.setAppearanceLanguage(Gui.ReferenceLanguage)
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var selected: bool
    host.app.sigFrame += func|host = &host, selected = &selected|(_)
    {
        if selected[] or not host.capturedPopupMenu() do
            return
        selected[] = true
        Swag.require(host.openPopupSubMenu(Gui.strings().lens_Application))
        Swag.require(host.openPopupSubMenu(Gui.strings().appearance_Theme))
        let theme = unwrap host.capturedPopupMenu()
        Swag.require(host.clickPopupMenuItem(unwrap theme.items[1]!.id))
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.pump()
    host.app.sigFrame.clear()
    Swag.require(selected and main.appearanceButton.appearanceTheme == .Light)
    Swag.require(host.capturedOptionSheet() == null)

    selected = false
    host.app.sigFrame += func|host = &host, selected = &selected|(_)
    {
        if selected[] or not host.capturedPopupMenu() do
            return
        selected[] = true
        Swag.require(host.openPopupSubMenu(Gui.strings().lens_Application))
        Swag.require(host.openPopupSubMenu(Gui.strings().appearance_Language))
        let languages = unwrap host.capturedPopupMenu()
        var french: WndId?
        for item in languages.items where item and item.name.raw == "Français" do
            french = item.id
        Swag.require(french != null)
        Swag.require(host.clickPopupMenuItem(french))
    }

    main.menuLauncher.sigPressed.call(cast(*Button, main.menuLauncher))
    host.pump()
    host.app.sigFrame.clear()
    Swag.require(selected and main.appearanceButton.language == "fr")
    Swag.require(host.capturedOptionSheet() == null)
}

// Audit the live command catalog rather than a second list that could miss a newly added action.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    for library in [false, true]
    {
        if library do
            main.swapLibraryMode()
        main.lens.open(">")
        var commands: u32
        for section in main.lens.results.sections where section
        {
            if section.inline do
                continue
            for &entry in section.entries where (entry.id or entry.run) and entry.lead.isEmpty() and not entry.paint
            {
                Swag.require(entry.glyph.isValid(), entry.title)
                commands += 1
            }
        }

        Swag.require(commands > 20)
        main.lens.close()
    }
}

// The same destructive command reaches menus, sheets, buttons and both lens sources.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    for id in [ActionFile.DeleteCapture, ActionSelection.DeleteSelection, ActionEdit.ClearImageInside, ActionPixSel.Clear]
    {
        let state = main.sendComputeCommandStateEvent(id)
        Swag.require(state.updatedFields.has(.RenderingHint) and state.renderingHint.has(.Critical))
        Swag.require(state.updatedFields.has(.Icon) and state.icon.isValid())
    }

    for id in [ActionLibTrash.Toggle, ActionLibTrash.Empty, ActionLibTrash.Restore, ActionLibTrash.DeleteForever, ActionLibFilter.Reset]
    {
        let state = main.libWnd.sendComputeCommandStateEvent(id)
        let removesContent = id == ActionLibTrash.Empty or id == ActionLibTrash.DeleteForever
        Swag.require(state.renderingHint.has(.Critical) == removesContent)
        Swag.require(state.updatedFields.has(.Icon) and state.icon.isValid())
    }

    var results: Lens.Results
    main.libWnd.describeCommands(&results, "", "Trash", [ActionLibTrash.Toggle, ActionLibTrash.Empty, ActionLibTrash.Restore, ActionLibTrash.DeleteForever])
    Swag.require(results.sections.count == 1 and results.sections[0]!.entries.count == 4)
    for &entry, index in results.sections[0]!.entries
    {
        Swag.require(entry.glyph.isValid())
        Swag.require(entry.critical == (index == 1 or index == 3))
    }

    let menu = MenuCtrl.createPopup(main, owner: main)
    let item = menu.addItem(ActionSelection.DeleteSelection)
    menu.updateState()
    Swag.require(item.critical and item.icon.isValid())
    var page: OptionSheet.Page
    page.addCommand(ActionSelection.DeleteSelection, main)
    Swag.require(page.rows.count == 1 and page.rows[0].critical and page.rows[0].icon.isValid())

    main.lens.open("delete")
    Swag.require(not main.lens.rows.isEmpty())
    for section in main.lens.results.sections where section do
        for &entry in section.entries where entry.id == ActionSelection.DeleteSelection or entry.id == ActionFile.DeleteCapture do
            Swag.require(entry.critical and entry.glyph.isValid())
    main.lens.close()
}

// Exercise the actual folder popup, including actions that are built directly without an id provider.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    g_Library.loaded = true
    main.swapLibraryMode()
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    var inspected: bool
    host.app.sigFrame += func|host = &host, inspected = &inspected|(_)
    {
        if inspected[] do
            return
        let menu = unwrap host.capturedPopupMenu()
        var actions: u32
        for item in menu.items where item and not item.separator
        {
            Swag.require(item.icon.isValid(), item.id)
            Swag.require(item.critical == (item.id == ActionLibTrash.Empty))

            // The recycle bin is a tab of the page: the menu only empties it.
            Swag.require(item.id != ActionLibTrash.Toggle)
            actions += 1
        }

        Swag.require(actions == 5)
        inspected[] = true
        Swag.require(host.dismissPopupMenu())
    }

    main.libWnd.folderBtn.sigPressed.call(cast(*Button, main.libWnd.folderBtn))
    Swag.require(inspected)
    host.pump()
}
