#global internal

using Core, Pixel, Gui

// One reusable, isolated renderer. Only a background task calls this service.
// Viewer globals, font caches and decoder failures cannot interfere with the interactive app.
struct ThumbnailService
{
    process:   Env.Process
    directory: String
}

impl ThumbnailService
{
    mtd reset()
    {
        if .process.isRunning()
        {
            catch .process.kill()
            discard catch .process.waitForExit()
        }

        .process = {}
        if not .directory.isEmpty() do
            catch Directory.delete(.directory, recurse: true)
        .directory.clear()
    }

    mtd render(path: string, settings: string = "")->Image fail
    {
        if .process.isRunning() and (try .process.tryWaitForExit(0'ms)) do
            .reset()
        if not .process.isRunning()
        {
            .directory = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-thumbnails-%", Guid64.random()))
            try Directory.create(.directory)
            let arguments = Format.toString("--thumbnail-worker %", Env.quoteArgument(.directory))
            with var info = Env.StartInfo{fileName: Env.executablePath(), arguments: arguments}
            {
                .consoleWindow = false
            }

            .process = try Env.startProcess(info)
        }

        let request = Path.combine(.directory, "request")
        let done    = Path.combine(.directory, "done")
        let output  = Path.combine(.directory, "preview.png")
        catch File.delete(done)
        catch File.delete(output)
        discard try File.writeAllText(Path.combine(.directory, "settings"), settings)
        discard try File.writeAllText(request, path)
        discard try File.writeAllText(Path.combine(.directory, "ready"), "")
        let started = Time.monotonicMicroseconds()
        while not File.exists(done)
        {
            if Swag.isCancelled() or
               Time.monotonicMicroseconds() - started > 20_000_000 or
               (try .process.tryWaitForExit(0'ms))
            {
                .reset()
                fail Errors.InvalidFormatError{}
            }

            Threading.Thread.sleep(10'ms)
        }

        return try Viewers.Picture.loadViewerImage(output)
    }

    mtd opDrop() { .reset() }
}

// Runs only in the dedicated child process. Its CPU surface and viewer tree survive between jobs.
func runThumbnailWorker(directory: string) fail
{
    Swag.setWorkerCount(2)
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)
    registerAppStrings(&app.resources)
    let registry = createViewerPluginRegistry()
    var window: *ViewerWindow?

    let ready       = Path.combine(directory, "ready")
    let request     = Path.combine(directory, "request")
    let done        = Path.combine(directory, "done")
    let output      = Path.combine(directory, "preview.png")
    var lastRequest = Time.monotonicMicroseconds()
    while Time.monotonicMicroseconds() - lastRequest < 60_000_000
    {
        if not File.exists(ready)
        {
            if window and (window.currentView or not window.pendingEmpty.isEmpty()) do
                app.runFrame()
            Threading.Thread.sleep(10'ms)
            continue
        }

        try File.delete(ready)
        let path = try File.readAllText(request)
        catch
        {
            let settingsPath = Path.combine(directory, "settings")
            let bytes        = File.exists(settingsPath) ? try File.readAllText(settingsPath) : {}
            var settings     = try ThumbnailSettings.decode(bytes)
            var image:       Image
            var pluginIndex: u64
            if registry.namePlugin(path, &pluginIndex) and
               registry.plugins[pluginIndex].thumbnail and
               settings.usesDefaultViewer(registry.plugins[pluginIndex].key)
            {
                image = try registry.plugins[pluginIndex].thumbnail!(path)
            }
            else
            {
                // Image and video decoders do not need a native surface or a complete viewer tree.
                if not window
                {
                    let surface = try app.createSurface(0, 0, 640, 480, .None)
                    app.theme.setSwagDark()
                    window = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
                    window.thumbnailMode = true
                    surface.show()
                }

                settings.apply(window)
                let surface = unwrap window.surface
                window.queueFile(path, remember: false)
                let started = Time.monotonicMicroseconds()
                for
                {
                    app.runFrame()
                    var blocking = false
                    if window.activeChoiceIndex < window.instances.count
                    {
                        let instance = &window.instances[window.activeChoiceIndex]
                        blocking = instance.isLoading and
                                   instance.isLoading() and
                                   (not instance.needsLoadingOverlay or instance.needsLoadingOverlay())
                    }

                    if window.pendingFile.isEmpty() and not blocking do
                        break
                    if Time.monotonicMicroseconds() - started > 15_000_000 do
                        fail Errors.InvalidFormatError{}
                    Threading.Thread.sleep(1'ms)
                }

                if not window.currentView do
                    fail Errors.InvalidFormatError{}
                app.animator.finishAll()
                surface.invalidate()
                app.runFrame()
                image = app.renderer.readRenderTarget(&surface.rt, 0, 0, 640, 480)
                image.crop(window.currentView.surfaceRect())
            }

            let largest = Math.max(image.width, image.height)
            if largest > 256
            {
                let scale = 256.0 / cast(f32, largest)
                image.resize(Math.max(1, cast(s32, cast(f32, image.width) * scale)),
                             Math.max(1, cast(s32, cast(f32, image.height) * scale)),
                             .Bilinear)
            }

            try image.save(output)
        }

        window?.closeFile()
        discard try File.writeAllText(done, "")
        lastRequest = Time.monotonicMicroseconds()
    }
}
