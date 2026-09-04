#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Gui

// Verifies that an information-band control keeps its breathing room outside its own frame.
func assertViewerInfoButton(button: *IconButton, width = ViewerZoomButtonWidth)
{
    Swag.assert(button.position.width == width)
    Swag.assert(button.margin.x >= ViewerInfoControlInset)
    Swag.assert(button.margin.z == ViewerInfoControlInset)
}

// Wraps one synthetic creation callback in the descriptor shape the host works with.
func testViewerPlugin(create: Viewer.PluginCreate)->Viewer.Plugin
{
    var result: retval
    result.key    = "test"
    result.create = create
    return result
}

// Creates one plugin through the same host API used by the application window.
func openTestViewer(plugin: Viewer.Plugin, contentParent: *Wnd, fileName: string, commandParent: *Wnd? = null, actionParent: *Wnd? = null, infoParent: *Wnd? = null, icon: Icon = {}, services: Viewer.HostServices = {})->ViewerSession
{
    var result: retval
    if plugin.attach do
        plugin.attach!(contentParent.app())
    var pluginHost = ViewerPluginHost{
        session: &result,
        documentParent: contentParent,
        sidePanelParent: contentParent,
        actionParent: actionParent orelse contentParent,
        infoParent: infoParent orelse contentParent,
        commandParent: commandParent orelse contentParent,
        sourceFileName: fileName,
        pluginIcon: icon,
        window: null,
        hostServices: services}
    let host: Viewer.Host = &pluginHost
    plugin.create(host)
    return result
}

// Collects every match a viewer answers for, polling one that reads its document in the background.
func collectViewerMatches(collect: Viewer.CollectSearchMatches, view: *Wnd, text: string, matches: *Array'Viewer.SearchMatch)
{
    var progress = 0'u64
    while !collect(view, text, {}, &progress, matches) do
        Threading.Thread.sleep(1'ms)
}

// Completes a viewer worker deterministically, then lets the headless GUI publish its result.
func completeViewerBackgroundLoad(host: *Testing.HeadlessHost, load: *Viewer.BackgroundOperation, timer: *Timer?)
{
    Swag.assert(load.started and timer != null)
    Jobs.wait(&load.job)
    host.fireTimer(timer)
}

// Completes file classification without waiting for the selected viewer's own background work.
func completeViewerWindowClassification(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while !window.pendingFile.isEmpty() and steps < 4_096
    {
        if window.choiceLoad.started and !window.choiceLoad.isDone() do
            Threading.Thread.sleep(1'ms)
        if window.startupTimer do
            host.fireTimer(window.startupTimer)
        steps += 1
    }

    Swag.assert(window.pendingFile.isEmpty())
}
