#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    Swag.require(workspace.activeDocument().sendComputeCommandStateEvent(ViewerCommands.Print).hidden)

    workspace.openScene([scopeTestDataPath("viewer.pdf"), scopeTestDataPath("viewer.srt")], .SideBySide)
    openViews(&host, workspace)

    for index in 2'u64
    {
        workspace.selectView(index)
        let document = workspace.activeDocument()
        let state    = document.sendComputeCommandStateEvent(ViewerCommands.Print)
        Swag.require(not state.hidden and not state.disabled)
        Swag.require(state.shortcut == Input.formatKeyShortcut(.Control, .P))
        document.lens.open(">")
        var count = 0'u64
        for section in document.lens.results.sections
        {
            for &entry in section!.entries where entry.title == Gui.strings().print_Command do
                count += 1
        }

        Swag.require(count == 1)
        document.lens.close()
    }

    let document = workspace.activeDocument()
    Swag.require(document.currentView is Viewers.Captions.Panel)
    let view  = unwrap document.currentView
    let image = expect renderViewerForPrint(view, &host.surface)
    let scale = view.deviceScale()
    Swag.require(image.width == cast(s32, Math.ceil(view.position.width * scale)))
    Swag.require(image.height == cast(s32, Math.ceil(view.position.height * scale)))

    var sawPrint = false
    host.app.sigFrame += func|host = &host, &sawPrint|(app)
    {
        let surface = app.surfaces.back()
        if surface.isHidden or surface.isDisabled do
            return
        if surface.view() is Dialog as dialog
        {
            if dialog.title.text == Gui.strings().print_Title
            {
                sawPrint = true
                Swag.require(host.clickModalButton(Dialog.BtnCancel))
            }
        }
    }

    host.shortcut(.P, .Control)
    host.app.sigFrame.clear()
    Swag.require(sawPrint and workspace.activeDocument() == document)
}

#test
{
    let fileName = writeStreamedFile(64 * 1024)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    defer host.shutdown()
    for choice, index in window.choices where choice.key == "hex" and index != window.activeChoiceIndex do
        window.selectViewer(cast(u32, index))
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView is Viewers.Hex.Panel)

    var previewed = false
    host.app.sigFrame += func|host = &host, &previewed|(app)
    {
        if not app.isInModalLoop() do
            return
        let surface = app.surfaces.back()
        if surface.isHidden or surface.isDisabled do
            return
        if surface.view() is Dialog as dlg
        {
            let tr    = Gui.strings()
            let title = dlg.title.text.toString()
            switch
            {
            case title == tr.print_FindingPrinters or title == tr.print_Preparing:
                break

            case title == tr.print_Title:
                Swag.require(host.clickModalButton("gui.print.preview"))

            case title == tr.print_Preview:
                previewed = true
                Swag.require(host.clickModalButton(Dialog.BtnCancel))

            default:
                Swag.require(false, title)
            }
        }
    }

    host.shortcut(.P, .Control)
    host.app.sigFrame.clear()
    Swag.require(previewed)
}
