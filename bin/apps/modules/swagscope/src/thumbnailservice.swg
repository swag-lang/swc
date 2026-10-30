#global internal

using Core, Pixel, Gui

private const ThumbnailMaxSize: u32 = 320

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

// Uses a plugin decoder when it has one, otherwise renders a bounded source sample.
func renderThumbnail(registry: const *ViewerPluginRegistry,
                     renderer: *ThumbnailRenderer,
                     settings: *ThumbnailSettings,
                     path: string)->Image fail
{
    var pluginIndex: u64
    let knownPlugin = registry.namePlugin(path, &pluginIndex)
    if knownPlugin and
       registry.plugins[pluginIndex].thumbnail and
       settings.usesDefaultViewer(registry.plugins[pluginIndex].key)
    {
        return try registry.plugins[pluginIndex].thumbnail!(path, ThumbnailMaxSize)
    }

    let viewerName = knownPlugin ? registry.plugins[pluginIndex].staticName : "File"
    let textual    = knownPlugin and registry.plugins[pluginIndex].textual
    return try renderer.render(path, viewerName, textual)
}

// Runs only in the dedicated child process. Its renderer and decoder cache survive between jobs.
func runThumbnailWorker(directory: string) fail
{
    let registry = createViewerPluginRegistry()
    var renderer = try ThumbnailRenderer.create()

    let ready       = Path.combine(directory, "ready")
    let request     = Path.combine(directory, "request")
    let done        = Path.combine(directory, "done")
    let output      = Path.combine(directory, "preview.png")
    var lastRequest = Time.monotonicMicroseconds()
    while Time.monotonicMicroseconds() - lastRequest < 60_000_000
    {
        if not File.exists(ready)
        {
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
            var image        = try renderThumbnail(&registry, &renderer, &settings, path)

            let largest = Math.max(image.width, image.height)
            if largest > ThumbnailMaxSize
            {
                let scale = cast(f32, ThumbnailMaxSize) / cast(f32, largest)
                image.resize(Math.max(1, cast(s32, cast(f32, image.width) * scale)),
                             Math.max(1, cast(s32, cast(f32, image.height) * scale)),
                             .Bilinear)
            }

            try image.save(output)
        }

        discard try File.writeAllText(done, "")
        lastRequest = Time.monotonicMicroseconds()
    }
}
