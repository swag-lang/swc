#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func completeBinaryViewerWindow(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)

    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 10_000
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if not instance.view or not instance.isLoading or not instance.isLoading() do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
        steps += 1
    }
}

// The tree the view builds is the report, and the search the host runs lands in it.
#[Swag.TestTag("golden")]
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_view", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1100, 640)

    let view = binaryTestViewer(&host, fileName, 1100, 600)
    Swag.assert(view.rowLines.count == view.doc.report.rows.count)
    Swag.assert(not view.list.iconMarginFirstCol)
    Swag.assert(Utf8.contains(view.details.toSlice(), "PE32+"))

    // The groups the report opened are visible; the ones it did not are folded away.
    let opened = view.list.lineCount()
    Swag.assert(opened > 4 and opened < cast(u32, view.doc.report.rows.count))

    let expandState = view.sendComputeCommandStateEvent(Binary.Action.ExpandAll)
    Swag.assert(expandState.name == Binary.texts().ui_MenuExpand)
    Swag.assert(expandState.shortcut == "Ctrl E")
    Swag.assert(not expandState.updatedFields.has(.Checked))
    let collapseState = view.sendComputeCommandStateEvent(Binary.Action.CollapseAll)
    Swag.assert(collapseState.shortcut == "Ctrl Shift E")
    Swag.assert(not collapseState.updatedFields.has(.Checked))

    view.sendCommandEvent(Binary.Action.ExpandAll)
    Swag.assert(view.list.lineCount() == cast(u32, view.doc.report.rows.count))
    view.sendCommandEvent(Binary.Action.CollapseAll)
    Swag.assert(view.list.lineCount() < opened)

    // An offset inside the code section reveals the section that owns those bytes, opening whatever
    // was folded over it.
    var revealed = view.revealOffset(FixtureTextAt + 0x40)
    Swag.assert(revealed)
    let selected = view.list.selectedLine()
    Swag.assert(selected != null)
    Swag.assert(binaryCellText(selected, .Field) == ".text")

    revealed = view.revealOffset(FixtureSize + 64)
    Swag.assert(not revealed)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.binary.document")
    Testing.assertContentFits(view)
}

// A searchable binary leaves the global action bar to the host and exposes only its compact
// history and structure commands in the centered viewer bar.
#[Swag.TestTag("golden")]
#test
{
    let bytes    = buildPeFixture()
    let fileName = writeFixture("pe_window", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(fileName)
    }

    completeBinaryViewerWindow(&host, window)

    // The bars are photographed over the structure tree: the report page would show the name of
    // the temporary fixture through their corners.
    assume cast(*Binary.Panel, window.currentView).showPage(false)

    // Nothing floats over the report until it is asked for: the find bar by its key, the
    // viewer's commands by the pointer.
    Swag.assert(window.currentActions == null)
    Swag.assert(not window.searchBar.isLocallyVisible() and not window.viewerBar.isLocallyVisible())
    window.showSearch()
    window.revealViewerBar()
    Swag.assert(window.searchBar.isLocallyVisible() and window.searchBox.hasFocus())
    Swag.assert(window.currentCommands != null and window.viewerBar.isLocallyVisible())
    Swag.assert(window.viewerBar.position.height == ViewerWindow.BarHeight)

    host.settleAnimations(window.searchBar, 4)
    var image = host.render(window)
    image.crop(window.searchBar.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "viewer.binary.find-bar")

    image = host.render(window)
    image.crop(window.viewerBar.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "viewer.binary.viewer-bar")

    window.searchFilterMode = true
    window.updateSearchAvailability()
    window.searchBox.setText("header")
    while assume cast(*Binary.Panel, window.currentView).filterTimer do
        host.pump()
    host.settleAnimations(window.searchBar, 4)
    image = host.render(window)
    image.crop(window.searchBar.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "viewer.binary.filter-bar")
}
