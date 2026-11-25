#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Pixel

// A private library, native window and event loop for one reader journey.
struct ScopeJourney
{
    app:          Application
    root:         String
    late surface: *Surface
    late window:  *ViewerWindow
    started:      bool
}

impl ScopeJourney
{
    mtd setup(withWorkspace = false)
    {
        .root = Testing.tempFilePath("scope-journey-", "")
        expect Directory.create(.root)
        .app.setAppIcon(expect Image.decode(".png", AppIcon))
        .app.setStatePath(Path.combine(.root, "settings.scc"))
        registerAppStrings(&.app.resources)
        .surface = expect .app.createSurface(40, 40, 1100, 790, surfaceId: "scope-test-journey")
        .surface.setTitle(ProductName)
        if withWorkspace do
            .window = ViewerWorkspace.create(.surface.wnd, createViewerPluginRegistry()).primary
        else do
            .window = ViewerWindow.create(.surface.wnd, createViewerPluginRegistry())
        .window.onlineMovies = false
        .window.onlineMusic  = false
        .surface.show()
        .started = true
    }

    mtd opDrop()
    {
        if .started do
            .surface.destroy()
        if not .root.isEmpty() do
            discard catch Directory.delete(.root, recurse: true)
    }

    mtd copyData(name: string, asName: string, loc: Swag.SourceCodeLocation = #callerlocation)->String
    {
        let path  = Path.combine(.root, asName)
        let bytes = expect File.readAllBytes(scopeTestDataPath(name, loc))
        expect File.writeAllBytes(path, bytes.toSlice())
        return path
    }

    // Pump native events until the state and rendered surface agree.
    mtd waitFor(stage: string, ready: func||()->bool)
    {
        Console.println("Swag Scope journey: ", stage)
        var watch: Time.Stopwatch
        watch.start()
        while true
        {
            .app.runFrame()
            Swag.require(.surface.renderFailure.isEmpty(), .surface.renderFailure.toString())
            if ready() and expect Testing.verifyNativePresentation(.surface) do
                return
            Swag.require(watch.elapsedMilliseconds() < 30_000, Format.toString("Scope journey timed out at %", stage))
        }
    }

    mtd waitForFile(path: string, document: *ViewerWindow? = null)
    {
        let window = document orelse .window
        .waitFor("file loaded", func|window, path|()->bool
        {
            if window.currentFile != path or not window.pendingFile.isEmpty() or window.outgoingView or
               window.currentView == null or
               window.activeChoiceIndex >= window.instances.count do
                return false
            let instance = &window.instances[window.activeChoiceIndex]
            Swag.require(instance.failureReason.isEmpty(), instance.failureReason.toString())
            return instance.isLoading == null or not instance.isLoading()
        })
    }

    mtd chooseFile(document: *ViewerWindow, path: string, command: WndId = ViewerCommands.Open,
                   cancel = false, input: *Testing.DesktopInput? = null)
    {
        var answered: bool
        var watch: Time.Stopwatch
        watch.start()
        let folder = Path.directoryName(path) orelse ""
        let name   = Path.fileName(path) orelse ""
        .app.sigFrame += func|folder, name, cancel, &answered, &watch|(app)
        {
            if answered do
                return
            Swag.require(watch.elapsedMilliseconds() < 5_000, "The file dialog did not become ready")
            for surface in app.surfaces
            {
                if surface.view() is FileDlg as dialog where not surface.isHidden
                {
                    if not cancel
                    {
                        Swag.require(dialog.browser.setCurrentFolder(folder))
                        dialog.browser.setFileName(name)
                        if not dialog.browser.hasValidSelection() do
                            return
                    }

                    answered = dialog.closeWithResult(cancel ? Dialog.BtnCancel : Dialog.BtnOk)
                    return
                }
            }
        }
        defer .app.sigFrame.clear()
        if input do
            input.shortcut(.O, .Control)
        else do
            document.sendCommandEvent(command)
        Swag.require(answered, "The command did not open a file dialog")
    }
}
