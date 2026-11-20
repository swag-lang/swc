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
        Swag.require(view.failureReason.isEmpty() and movie.isValid() and movie.frameCount > 1,
                     Format.toString("%: %", name, view.failureReason).toString())
        Swag.require(view.frameLabel.isLocallyVisible())
        Swag.require(view.timeline.isLocallyVisible() == movie.isAnimated())
        Swag.require(view.itemSelector.isLocallyVisible() != movie.isAnimated())
        if not movie.isAnimated()
        {
            let count = Math.min(movie.frameCount, 128)
            Swag.require(view.itemSelector.items.count == count)
            let firstInfo = movie.frameInfo(view.selectorStart)
            let firstLabel = view.itemSelector.items[0]!.name.text
            Swag.require(firstInfo and Utf8.contains(firstLabel, Format.toString("% × %", firstInfo.width, firstInfo.height).toString()))
            if firstInfo.kind == .Texture do
                Swag.require(Utf8.contains(firstLabel, Format.toString(Picture.texts().ui_ItemLevel, firstInfo.level).toString()))
            let currentInfo = movie.frameInfo(movie.frameIndex)
            Swag.require(currentInfo and currentInfo.width > 0 and currentInfo.height > 0)
            Swag.require(not movie.frameInfo(movie.frameCount))
            view.itemSelector.setSelectedIndex(1)
            Swag.require(movie.frameIndex == view.selectorStart + 1)
            Swag.require(Utf8.startsWith(view.itemSelector.items[view.itemSelector.selectedIndex]!.name.text,
                                         Viewer.pageText(cast(u64, movie.frameIndex), cast(u64, movie.frameCount)).toString()))
            Swag.require(view.itemSelectorStart(129, 256) == 65)
            Swag.require(view.itemSelectorStart(255, 256) == 128)
        }
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

// A temporary synthetic array crosses the bounded selector's 128-entry window without adding a
// permanent fixture. Selecting after the boundary recenters the list and keeps its selection tied
// to the actual movie index.
#test
{
    var source = Image.create(1, 1, .RGBA8)
    source.fill(Argb.White)
    var encoded = expect source.encode("selector-window.ktx2")
    encoded.makeLinear()
    var bytes = unwrap encoded.toSlice()
    let dataOffset = cast(const *u64, bytes.buffer + 80)[]
    cast(*u32, bytes.buffer + 32)[] = 256
    cast(*u64, bytes.buffer + 88)[] = 1024
    cast(*u64, bytes.buffer + 96)[] = 1024
    var array: ConcatBuffer
    array.addBytes(bytes[until dataOffset])
    for _ in range(0, 256) do
        array.addBytes(bytes[dataOffset until dataOffset + 4])

    let fileName = Testing.tempFilePath("scope-image-selector-window-", ".ktx2")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, array)

    var host: Testing.HeadlessHost
    host.setup(960, 540)
    var session = openTestViewer(Picture.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*Picture.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    let movie = &view.imageView.movie
    Swag.require(movie.frameCount == 256 and view.itemSelector.items.count == 128)

    view.imageView.setFrameIndex(127)
    view.refreshFrame()
    Swag.require(view.selectorStart == 0 and view.itemSelector.selectedIndex == 127,
                 Format.toString("window %, selected %, frame %, failure %", view.selectorStart,
                                 view.itemSelector.selectedIndex, movie.frameIndex, movie.failureReason).toString())
    view.imageView.setFrameIndex(128)
    view.refreshFrame()
    Swag.require(view.selectorStart == 64 and view.itemSelector.selectedIndex == 64)
    view.itemSelector.setSelectedIndex(65)
    Swag.require(movie.frameIndex == 129 and view.itemSelector.selectedIndex == 65)

    // No pixels are decoded while the metadata chooser is being built. Opening it asks for
    // just one visible row, into a fixed 128-cell atlas; closing invalidates the in-flight result.
    view.imageView.setFrameIndex(0)
    view.refreshFrame()
    for index in 128 do
        Swag.require(not view.thumbnailReady[index] and not view.thumbnailRequested[index])
    let selectorRect = view.itemSelector.surfaceRect()
    host.click({selectorRect.x + selectorRect.width / 2, selectorRect.y + selectorRect.height / 2})
    let popup = unwrap view.thumbnailPopup
    let visible = popup.visibleItemRange()
    Swag.require(visible.first == 0 and visible.end > 0)
    Swag.require(view.thumbnailRequestLocalIndex >= visible.first and view.thumbnailRequestLocalIndex < visible.end)
    for index in 128
    {
        if view.thumbnailRequested[index] do
            Swag.require(index >= visible.first and index < visible.end)
    }
    Swag.require(view.thumbnailPixels.width == 256 and view.thumbnailPixels.height == 384)
    Swag.require(view.thumbnailPixels.byteCount == 393216 and view.thumbnailList.frameCount == 128)

    let staleIndex = view.thumbnailRequestLocalIndex
    view.itemSelector.closePopup()
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(not view.thumbnailReady[staleIndex], "thumbnail completed after its popup generation was retired")

    let oldGeneration = view.thumbnailGeneration
    view.imageView.setFrameIndex(129)
    view.refreshFrame()
    Swag.require(view.selectorStart == 65 and view.thumbnailGeneration > oldGeneration)
    for index in 128 do
        Swag.require(not view.thumbnailReady[index] and not view.thumbnailRequested[index])
    let nextSelectorRect = view.itemSelector.surfaceRect()
    host.click({nextSelectorRect.x + nextSelectorRect.width / 2, nextSelectorRect.y + nextSelectorRect.height / 2})
    let nextPopup = view.thumbnailPopup
    let nextVisible = nextPopup.visibleItemRange()
    Swag.require(view.thumbnailRequestLocalIndex >= nextVisible.first and view.thumbnailRequestLocalIndex < nextVisible.end)
    Swag.require(view.selectorStart + cast(s32, view.thumbnailRequestLocalIndex) < movie.frameCount)
    view.itemSelector.closePopup()
    view.thumbnailTask.wait()
    host.pump()
    Swag.require(not view.thumbnailReady[view.thumbnailRequestLocalIndex], "recentered thumbnail outlived the popup generation")
    var retired = view.retire()
    if not retired
    {
        view.thumbnailTask.wait()
        host.pump()
        retired = view.retire()
    }
    Swag.require(retired and not view.thumbnailList.isValid(), "retired image panel retained thumbnail work or texture")
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
