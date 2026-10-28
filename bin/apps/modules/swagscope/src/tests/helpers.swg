#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui, Viewers

// Verifies that an information-band control keeps its breathing room outside its own frame.
func assertViewerInfoButton(button: *IconButton, width = Viewer.ZoomButtonWidth)
{
    Swag.assert(button.position.width == width)
    Swag.assert(button.margin.x >= Viewer.ZoomButtonInset)
    Swag.assert(button.margin.z == Viewer.ZoomButtonInset)
}

// Wraps one synthetic creation callback in the descriptor shape the host works with.
func testViewerPlugin(create: Viewer.PluginCreate)->Viewer.Plugin
{
    with var result: #returntype
    {
        .key    = "test"
        .create = create
    }

    return result
}

// Creates one plugin through the same host API used by the application window.
func openTestViewer(plugin: Viewer.Plugin, contentParent: *Wnd, fileName: string, commandParent: *Wnd? = null, actionParent: *Wnd? = null, infoParent: *Wnd? = null, icon: Icon = {}, services: Viewer.HostServices = {}, waitForText = true)->ViewerSession
{
    var result: #returntype
    if plugin.attach do
        plugin.attach(contentParent.app())

    with var pluginHost: ViewerPluginHost
    {
        .thumbnail       = false
        .session         = &result
        .documentParent  = contentParent
        .sidePanelParent = contentParent
        .sideSplitter    = null
        .sidePaneIndex   = 1
        .actionParent    = actionParent orelse contentParent
        .infoParent      = infoParent orelse contentParent
        .commandParent   = commandParent orelse contentParent
        .sourceFileName  = fileName
        .pluginIcon      = icon
        .hostServices    = services
        .window          = null
    }

    let host: Viewer.Host = &pluginHost
    plugin.create(host)
    if waitForText and plugin.key == PlainText.ViewerKey and result.view
    {
        let view = assume cast(*PlainText.Panel, result.view)
        if view.read.started
        {
            view.read.task.wait()
            Swag.assert(not view.read.failed, view.read.error)
            view.loadNextChunk()
        }
    }

    return result
}

// Collects every match a viewer answers for, polling one that reads its document in the background.
func collectViewerMatches(collect: Viewer.CollectSearchMatches, text: string, matches: *Array'Viewer.SearchMatch)
{
    var progress = 0'u64
    while not collect(text, {}, &progress, matches) do
        Threading.Thread.sleep(1'ms)
}

// Completes a viewer worker deterministically, then lets the headless GUI deliver the event that
// publishes its result. A result already delivered by an earlier pump is left as it is.
func(T) completeViewerBackgroundLoad(host: *Testing.HeadlessHost, load: *T)
{
    load.task.wait()
    host.pump()
    Swag.assert(not load.isPending())
}

// Ages the current wait past the delay the activity mark waits for, and lets the window decide again.
func expireViewerLoadingDelay(window: *ViewerWindow)
{
    Swag.assert(window.loadingWantedSince != 0)
    window.loadingWantedSince = 1
    window.updateLoadingIndicator()
}

// Ages the shown activity mark past its minimum visible time, and lets the window decide again.
//
// A wait that ended before the mark could linger has nothing to age; the call is then harmless.
func expireViewerLoadingLinger(window: *ViewerWindow)
{
    if not window.loadingShownSince do
        return
    window.loadingShownSince = 1
    window.updateLoadingIndicator()
}

// Completes file classification without waiting for the selected viewer's own background work.
func completeViewerWindowClassification(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while not window.pendingFile.isEmpty() and steps < 4_096
    {
        // Classification can also be waiting for the previous viewer to retire.
        // Complete worker jobs and deliver the events that report their end before
        // advancing that transition; the new viewer starts its own work only after
        // pendingFile has been cleared.
        Swag.drainWork()
        host.pump()

        if window.startupTimer do
            host.fireTimer(window.startupTimer)
        steps += 1
    }

    Swag.assert(window.pendingFile.isEmpty())
}

// Lets the text viewer's count end and its result reach the viewer, including a count it
// restarted because the interpretation changed meanwhile.
func completeTextStatistics(host: *Testing.HeadlessHost, view: *PlainText.Panel)
{
    for 8
    {
        view.statisticsTask.wait()
        host.pump()
        if not view.statisticsTask.isPending() and not view.statisticsTask.isDone() do
            return
    }

    Swag.assert(false, "text statistics did not settle")
}

// Completes file classification, then the selected viewer's own loading, and lets the activity mark go.
func completeQueuedViewerFile(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)

    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 4_096
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if not instance.view or not instance.isLoading or not instance.isLoading() do
            break
        if window.choices[window.activeChoiceIndex].key == PlainText.ViewerKey
        {
            let view = assume cast(*PlainText.Panel, instance.view)
            completeTextReads(host, view)
            host.fireTimer(view.loadTimer)
        }
        else
        {
            // The end of background work arrives as an event; deliver it before firing the
            // timers, which include the slideshow pace of a picture that is already shown.
            Swag.drainWork()
            host.pump()
            if window.activeChoiceIndex < window.instances.count
            {
                let current = &window.instances[window.activeChoiceIndex]
                if not current.view or not current.isLoading or not current.isLoading() do
                    break
            }

            Threading.Thread.sleep(1'ms)
            host.fireTimers()
        }

        steps += 1
    }

    Swag.assert(steps < 4_096)
    expireViewerLoadingLinger(window)
}

// Completes queued text reads at the GUI publication boundary, including superseded requests.
func completeTextReads(host: *Testing.HeadlessHost, view: *PlainText.Panel)
{
    for 64
    {
        if view.read.started do
            view.read.task.wait()
        view.loadNextChunk()
        discard host.render(view)
        view.updateEstimatedHeight()
        if not view.read.started and not view.pendingSeek and not view.needsMore() do
            return
    }

    Swag.assert(false, "text loading did not settle")
}

// One file of a stored ZIP archive that a test writes.
struct StoredZipFile
{
    name:  string
    bytes: const [..] u8
}

private func appendZipU16(bytes: *Array'u8, value: u16)
{
    bytes.add(cast #bit (u8, value))
    bytes.add(cast #bit (u8, (value >> 8)))
}

private func appendZipU32(bytes: *Array'u8, value: u32)
{
    appendZipU16(bytes, cast #bit (u16, value))
    appendZipU16(bytes, cast #bit (u16, (value >> 16)))
}

// Returns a ZIP archive holding `files` uncompressed and in order, with UTF-8 names.
func storedZipBytes(files: const [..] StoredZipFile)->Array'u8
{
    var result:  #returntype
    var crcs:    Array'u32
    var offsets: Array'u32
    for file in files
    {
        let crc = Hash.Crc32.compute(file.bytes)
        crcs.add(crc)
        offsets.add(cast(u32, result.count))
        appendZipU32(&result, 0x04034B50)
        appendZipU16(&result, 20)
        appendZipU16(&result, 1 << 11)
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU32(&result, crc)
        appendZipU32(&result, cast(u32, file.bytes.count))
        appendZipU32(&result, cast(u32, file.bytes.count))
        appendZipU16(&result, cast(u16, file.name.count))
        appendZipU16(&result, 0)
        result.add(cast(const [..] u8, file.name))
        result.add(file.bytes)
    }

    // The central directory repeats each local header and records where it starts.
    let directoryAt = result.count
    for file, index in files
    {
        appendZipU32(&result, 0x02014B50)
        appendZipU16(&result, 20)
        appendZipU16(&result, 20)
        appendZipU16(&result, 1 << 11)
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU32(&result, crcs[index])
        appendZipU32(&result, cast(u32, file.bytes.count))
        appendZipU32(&result, cast(u32, file.bytes.count))
        appendZipU16(&result, cast(u16, file.name.count))
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU16(&result, 0)
        appendZipU32(&result, 0)
        appendZipU32(&result, offsets[index])
        result.add(cast(const [..] u8, file.name))
    }

    let directorySize = result.count - directoryAt
    appendZipU32(&result, 0x06054B50)
    appendZipU16(&result, 0)
    appendZipU16(&result, 0)
    appendZipU16(&result, cast(u16, files.count))
    appendZipU16(&result, cast(u16, files.count))
    appendZipU32(&result, cast(u32, directorySize))
    appendZipU32(&result, cast(u32, directoryAt))
    appendZipU16(&result, 0)
    return result
}

// The failure text a viewer shows: the plain statement, then the technical detail.
func failureShape(statement, detail: string)->String => Format.toString("%\n\n%", statement, detail)

// Opens `fileName` in a viewer window built inside the frame of the shipped surface, at the size
// of the charter's pictures, in Encre or in Papier, and lets the viewer finish loading.
//
// The strip floats over the document with the glyph, the name and the window buttons, so a
// picture of the window is judged whole against its charter picture.
func framedViewerWindow(host: *Testing.HeadlessHost, fileName: string, light: bool)->*ViewerWindow
{
    host.setup(1280, 800)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)
    host.app.setAppIcon(expect Image.decode(".png", AppIcon))
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName)
    completeQueuedViewerFile(host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)
    return window
}
