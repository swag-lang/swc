#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Every multi-image codec reaches the same viewer navigation, including unequal image dimensions.
#test
{
    for name in ["imageset-animation.webp", "imageset-animation.apng", "imageset-animation.gif", "imageset-pages-raw.tiff", "imageset-icons.ico", "imageset-array.dds", "imageset-array.ktx2", "imageset-parts.exr", "imageset-layers-0.psd"]
    {
        let fileName = scopeTestDataPath(name)
        var host: Testing.HeadlessHost
        host.setup(960, 540)
        var session = openTestViewer(Picture.viewerPlugin(), &host.root, fileName)
        let view    = assume cast(*Picture.Panel, session.view)
        completeViewerBackgroundLoad(&host, &view.load)
        let movie = &view.imageView.movie
        Swag.require(view.failureReason.isEmpty() and movie.isValid() and movie.frameCount > 1)
        Swag.require(view.timeline.isLocallyVisible() and view.frameLabel.isLocallyVisible())
        Swag.require(view.playButton.isLocallyVisible() == movie.isAnimated())
        Swag.require(movie.isPaused != movie.isAnimated())
        view.imageView.setPaused(true)
        view.imageView.setFrameIndex(movie.frameCount - 1)
        view.refreshFrame()
        Swag.require(movie.frameIndex == movie.frameCount - 1 and movie.frame.isValid())
        view.imageView.setFrameIndex(0)
        Swag.require(movie.frameIndex == 0 and movie.failureReason.isEmpty())
        var information = InfoSheet.create(&host.root)
        view.information.describe(information)
        Swag.require(Utf8.contains(information.text(), Format.toString("%", movie.frameCount).toString()))
    }
}

// Over a set of independent images the summary names the item in view, its size and its place in
// a texture; a paused animation names the delay of its frame.
#test
{
    for name in ["imageset-icons.ico", "imageset-array.dds", "imageset-animation.gif"]
    {
        var host: Testing.HeadlessHost
        host.setup(960, 540)
        var session = openTestViewer(Picture.viewerPlugin(), &host.root, scopeTestDataPath(name))
        let view    = assume cast(*Picture.Panel, session.view)
        completeViewerBackgroundLoad(&host, &view.load)
        let movie = &view.imageView.movie
        view.imageView.setPaused(true)
        view.imageView.setFrameIndex(1)
        view.refreshFrame()
        let info  = unwrap movie.frameInfo()
        let shown = view.shownDetails()
        if info.kind == .Animation
        {
            // Paused, an animation gives how long its frame stays on screen, and the lens steps it
            // by frames; playing, it keeps the summary of the whole.
            let delay = Format.toString(Picture.texts().ui_FrameDelay, cast(u32, Math.round(movie.currentFrameDuration() * 1000)))
            Swag.require(view.itemText() == delay and shown == Format.toString("% · %", view.details, delay), shown.toString())
            var results: Lens.Results
            var entries = Viewer.LensEntries.create(&results, "Image", host.theme)
            view.describeLens(&entries)
            var frames = 0
            for &entry in results.sections[0]!.entries where entry.title == appStrings().cmd_PreviousFrame or entry.title == appStrings().cmd_NextFrame do
                frames += 1
            Swag.require(frames == 2)
            view.imageView.setPaused(false)
            view.refreshFrame()
            Swag.require(view.itemText().isEmpty() and view.shownDetails() == view.details, name)
            continue
        }

        Swag.require(Utf8.startsWith(shown.toString(), view.details.toString()), name)
        Swag.require(Utf8.contains(shown.toString(), Format.toString("% × %", info.width, info.height).toString()), shown.toString())
        if info.kind == .Texture and info.layer do
            Swag.require(Utf8.contains(shown.toString(), Format.toString(Picture.texts().ui_ItemLayer, info.layer).toString()), shown.toString())
    }
}
