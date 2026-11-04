#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

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
            actions += 1
        }

        Swag.require(actions == 6)
        inspected[] = true
        Swag.require(host.dismissPopupMenu())
    }

    main.libWnd.folderBtn.sigPressed.call(cast(*Button, main.libWnd.folderBtn))
    Swag.require(inspected)
    host.pump()
}
