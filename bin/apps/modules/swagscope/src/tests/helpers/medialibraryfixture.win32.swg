#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global internal

using Core, Gui, Pixel, Video, Viewers

// Owns an offline library and the deadline shared by its user journey.
struct MediaLibraryFixture
{
    root:       String
    watch:      Time.Stopwatch
    entryCount: u64 = 12
}

impl MediaLibraryFixture
{
    #[Swag.Propagate]
    mtd create(loc: Swag.SourceCodeLocation = #callerlocation) fail
    {
        .watch.start()
        .root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-library-%", Guid64.random()))
        Path.normalize(&.root)
        let fixtures = Path.combine(testSourceRoot(loc), "datas")
        let films    = Path.combine(.root, "Films")
        let pictures = Path.combine(.root, "Pictures")
        Directory.create(.root, recurse: true)
        Directory.create(films)
        Directory.create(pictures)
        let mjpeg  = File.readAllBytes(Path.combine(fixtures, "glint-aac-mjpeg.mp4"))
        let h264   = File.readAllBytes(Path.combine(fixtures, "ffmpeg-h264-baseline.mp4"))
        let multi  = File.readAllBytes(Path.combine(fixtures, "ffmpeg-h264-two-aac.mkv"))
        let legacy = File.readAllBytes(Path.combine(fixtures, "rv40-legacy-clock.mkv"))
        let png    = File.readAllBytes(Path.combine(fixtures, "appicon.png"))
        let webp   = File.readAllBytes(Path.combine(fixtures, "imageset-real-review.webp"))
        let gif    = File.readAllBytes(Path.combine(fixtures, "imageset-animation.gif"))
        let tiff   = File.readAllBytes(Path.combine(fixtures, "imageset-pages-raw.tiff"))
        for index in .entryCount
        {
            switch index % 4
            {
            case 0: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mp4", index)), mjpeg.toSlice())
            case 1: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mp4", index)), h264.toSlice())
            case 2: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mkv", index)), multi.toSlice())
            case 3: discard File.writeAllBytes(Path.combine(films, Format.toString("Film %{03} (2024).mkv", index)), legacy.toSlice())
            }

            switch index % 4
            {
            case 0: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.png", index)), png.toSlice())
            case 1: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.webp", index)), webp.toSlice())
            case 2: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.gif", index)), gif.toSlice())
            case 3: discard File.writeAllBytes(Path.combine(pictures, Format.toString("Picture %{03}.tiff", index)), tiff.toSlice())
            }
        }
    }

    // Existing online artwork is deterministic and needs no network credentials in this journey.
    #[Swag.Propagate]
    mtd seedPosters(window: *ViewerWindow, films: string) fail
    {
        let settings = ThumbnailSettings.capture(window)
        let entries  = expect Directory.enumerateFiles(films)
        for &entry, index in entries
        {
            // Odd RGB widths expose upload alignment mistakes, with a different color per entry.
            var image = Image.create(37, 53, .RGB8)
            image.fill(Color.fromRgb(cast(u8, index), 127, 241))
            let key = expect ThumbnailCache.key(entry.fullName, settings: settings)
            expect ThumbnailCache.write(key, &image)
        }
    }

    // Compare uploaded pixels too: presentation parity alone cannot expose a damaged texture.
    #[Swag.Propagate]
    mtd verifyPosters(window: *ViewerWindow) fail
    {
        let explorer = unwrap window.explorer
        let settings = ThumbnailSettings.capture(window)
        for &entry in explorer.entries where entry.texture.isValid()
        {
            let key      = ThumbnailCache.key(entry.path, settings: settings)
            let expected = ThumbnailCache.read(key).convertedTo(.RGBA8)
            let pixels   = window.app().renderer.readTexturePixels(entry.texture, .RGBA8)
            Swag.require(entry.texture.width == 37 and entry.texture.height == 53)
            Swag.require(Slice.equals(pixels.toSlice(), expected.pixels.toSlice()))
        }
    }

    // Pump normal events until the stage has both its expected state and completed native pixels.
    #[Swag.Propagate]
    mtd waitFor(window: *ViewerWindow, stage: string, ready: func||()->bool) fail
    {
        Console.println("Swag Scope integration journey: ", stage)
        var stageWatch: Time.Stopwatch
        stageWatch.start()
        while true
        {
            window.app().runFrame()
            if ready() and Testing.verifyNativePresentation(unwrap window.surface) do
                return
            if stageWatch.elapsedMilliseconds() > 10_000 or .watch.elapsedMilliseconds() > 40_000
            {
                if window.explorer
                {
                    let explorer = window.explorer
                    Console.println("exploring=",
                                    window.isExploring(),
                                    " listing=",
                                    explorer.load.started,
                                    " entries=",
                                    explorer.entries.count,
                                    " shown=",
                                    explorer.shown.count,
                                    " workers=",
                                    explorer.previews.count,
                                    " path=",
                                    explorer.listing.path)
                    for preview in explorer.previews do
                        Console.println("preview running=", preview.started, " path=", preview.path, " error=", preview.error)
                    let range = explorer.grid.visibleRange()
                    Console.println("visible=", range.first, "..", range.end)
                    for row in range.first until Math.min(range.end, explorer.shown.count)
                    {
                        let entry = &explorer.entries[explorer.shown[row]]
                        Console.println("tile=", entry.name, " attempted=", entry.attempted, " texture=", entry.texture.isValid())
                    }
                }

                Console.println("file=", window.currentFile, " pending=", window.pendingFile, " render failure=", window.surface!.renderFailure)
                if window.currentView and
                   window.activeChoiceIndex < window.instances.count and
                   window.choices[window.activeChoiceIndex].key == "video"
                {
                    let video = assume cast(*Film.Panel, window.currentView)
                    Console.println("opened=", video.openFinished, " frame=", video.frameIndex, " has frame=", video.hasFrame, " awaiting=", video.awaitingFrame, " playing=", video.playing, " failure=", video.failureText)
                }

                fail Errors.InvalidFormatError{Errors.mkString(Format.toString("Viewer stage '%' exceeded its deadline", stage))}
            }

            Threading.Thread.sleep(10'ms)
        }
    }

    mtd waitForLibrary(window: *ViewerWindow, stage, folder: string) fail
    {
        let ready = func|window, folder, count = me.entryCount|()->bool
        {
            let explorer = window.explorer
            if not window.isExploring() or
               not explorer or
               explorer.load.started or
               explorer.listing.path != folder or
               explorer.shown.count != count do
                return false
            if explorer.isThumbnailView()
            {
                let range = explorer.grid.visibleRange()
                if range.end <= range.first do
                    return false
                for row in range.first until range.end where
                    not explorer.entries[explorer.shown[row]].texture.isValid() do
                    return false
            }

            return true
        }

        try .waitFor(window, stage, ready)
    }

    mtd opDrop()
    {
        if not .root.isEmpty() do
            catch Directory.delete(.root, recurse: true)
    }
}
