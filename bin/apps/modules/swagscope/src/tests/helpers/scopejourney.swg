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
    mtd setup()
    {
        .root = Testing.tempFilePath("scope-journey-", "")
        expect Directory.create(.root)
        .app.setAppIcon(expect Image.decode(".png", AppIcon))
        .app.setStatePath(Path.combine(.root, "settings.scc"))
        registerAppStrings(&.app.resources)
        .surface = expect .app.createSurface(40, 40, 1100, 790, surfaceId: "scope-test-journey")
        .surface.setTitle(ProductName)
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
        let path = Path.combine(.root, asName)
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
            Swag.require(watch.elapsedMilliseconds() < 10_000, Format.toString("Scope journey timed out at %", stage))
        }
    }

    mtd waitForFile(path: string)
    {
        let window = .window
        .waitFor("file loaded", func|window, path|()->bool
        {
            if window.currentFile != path or window.currentView == null or
               window.activeChoiceIndex >= window.instances.count do
                return false
            let instance = &window.instances[window.activeChoiceIndex]
            Swag.require(instance.failureReason.isEmpty(), instance.failureReason.toString())
            return instance.isLoading == null or not instance.isLoading()
        })
    }
}
