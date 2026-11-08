#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Opt-in, read-only source-library probe. The offline journey owns its fixtures; this
// probe exercises a reported library's names, codecs and share latency without copying it.
#[Swag.TestTag("integration.application.library")]
#test
{
    let folder = Env.variable("SWAG_SCOPE_TEST_LIBRARY")
    Swag.require(folder.count and Directory.exists(folder), "set SWAG_SCOPE_TEST_LIBRARY to an existing media folder")
    var app: Application
    app.setAppIcon(expect Image.decode(".png", AppIcon))
    registerAppStrings(&app.resources)
    let surface = expect app.createSurface(40, 40, 1193, 823, surfaceId: "scope-library-probe")
    let window  = ViewerWindow.create(surface.wnd, createViewerPluginRegistry())
    surface.show()
    window.openExplorer(folder)
    let explorer = unwrap window.explorer
    var watch: Time.Stopwatch
    watch.start()
    for stage in 8
    {
        if stage > 0 do
            explorer.setArtworkSource(stage % 2 ? .Local : .Online)
        if stage % 4 == 3 do
            explorer.forceRefresh()
        var elapsed: Time.Stopwatch
        elapsed.start()
        var checked  = false
        let duration = stage == 7 ? 17_000 : 10_000
        while elapsed.elapsedMilliseconds() < duration and watch.elapsedMilliseconds() < 100_000
        {
            app.runFrame()
            if not explorer.load.started and explorer.shown.count
            {
                if expect Testing.verifyNativePresentation(surface) do
                    checked = true
                if stage == 0 and elapsed.elapsedMilliseconds() > 3000 do
                    explorer.scroll.setScrollPos(0, explorer.grid.position.height * 0.8)
            }

            Threading.Thread.sleep(10'ms)
        }

        Swag.require(checked, "the library produced no completed native frame")
        var visible = 0'u64
        var cached  = 0'u64
        let range   = explorer.grid.visibleRange()
        for row in range.first until Math.min(range.end, explorer.shown.count) where
            explorer.entries[explorer.shown[row]].texture.isValid()
        {
            visible += 1
            let entry = &explorer.entries[explorer.shown[row]]

            // An online request may still display its local fallback. Generic icons and
            // previews of archive members need not have a cache entry under this file key.
            if not entry.onlinePending
            {
                let settings = ThumbnailSettings.capture(window, entry, localArtworkOnly: explorer.artworkSource == .Local, previewEpoch: explorer.previewEpoch)
                let key      = expect ThumbnailCache.key(entry.path, settings: settings)
                let image    = ThumbnailCache.read(key)
                if image.isValid()
                {
                    let expected = image.convertedTo(.RGBA8)
                    let pixels   = app.renderer.readTexturePixels(entry.texture, .RGBA8)
                    Swag.require(Slice.equals(pixels.toSlice(), expected.pixels.toSlice()))
                    cached += 1
                }
            }
        }

        Console.println("Library stage ", stage, ": ", explorer.shown.count, " entries; ", visible, " visible previews; ", cached, " cache matches")
        if visible == 0
        {
            Console.println("Preview workers: ", explorer.previews.count)
            for preview in explorer.previews do
                Console.println("preview running=", preview.started, " path=", preview.path, " error=", preview.error)
            for row in range.first until Math.min(range.end, explorer.shown.count)
            {
                let entry = &explorer.entries[explorer.shown[row]]
                Console.println("tile=", entry.name, " attempted=", entry.attempted, " texture=", entry.texture.isValid())
            }
        }
        Swag.require(visible > 0, "the library produced no visible previews")
    }
}
