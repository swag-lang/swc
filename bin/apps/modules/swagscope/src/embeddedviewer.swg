#global internal

using Core, Gui

private const EmbeddedHeaderHeight = ViewerReadingLine.Height

// Application implementation of [[Viewer.Embedded]].
//
// Entries use the same bottom readings and reserved command area as the main window.
// The enclosing archive supplies the entry name and the return action.
struct EmbeddedViewer
{
    using wnd:        Wnd
    informationOnly:  bool
    externalReadings: bool

    late
    {
        header:             *Wnd
        titleLabel:         *Label
        viewerMenu:         *IconButton
        infoLane:           *Wnd
        sideSplitter:       *SplitterCtrl
        outlinePlaceholder: *Wnd
        document:           *Wnd
        sidePlaceholder:    *Wnd
    }

    commandBar: *FloatingPanel?     // Made with the viewer; a resize may reach it before.

    late owner:        *ViewerWindow
    fileName:          String
    title:             String
    choices:           Array'ViewerPluginChoice
    instances:         Array'ViewerSession
    activeIndex:       u32 = Swag.U32.Max
    currentView:       *Wnd?
    currentActions:    *Wnd?
    currentInfo:       *Wnd?
    currentCommands:   *Wnd?
    currentSidePanel:  *Wnd?
    currentSideButton: *IconButton?
}

private func embeddedViewerFor(view: *Wnd)->*EmbeddedViewer => unwrap view.ancestorByType'EmbeddedViewer()

private func reportEmbeddedFailure(view: *Wnd, reason: string)
{
    embeddedViewerFor(view).replaceFailure(view, reason)
}

private func reportEmbeddedDetails(view: *Wnd, details: string)
{
    for &instance in embeddedViewerFor(view).instances where instance.view == view
    {
        // The sheet gives the summary, so only a new one is worth describing it again.
        let changed = instance.details != details
        instance.details = details
        let embedded = embeddedViewerFor(view)
        if embedded.currentView == view
        {
            embedded.titleLabel.setText(details)
            embedded.titleLabel.toolTip = details
        }

        if changed and embedded.informationOnly
        {
            let information = embedded.owner.information
            information.postRefresh()
        }

        return
    }
}

// Describes the owner's sheet again when it presents this viewer's contribution.
private func reportEmbeddedInformationChanged(view: *Wnd)
{
    let embedded = embeddedViewerFor(view)
    if embedded.informationOnly
    {
        let information = embedded.owner.information
        information.postRefresh()
    }
}

private func reportEmbeddedChromeChanged(view: *Wnd)
{
    with let embedded = embeddedViewerFor(view)
    {
        .applyLayout()
        .layoutCommands()
    }
}

private func reportEmbeddedLoadingChanged(view: *Wnd)
{
    let embedded = embeddedViewerFor(view)
    if embedded.informationOnly
    {
        let information = embedded.owner.information
        information.postRefresh()
    }
}

// Returns the services a viewer embedded in a document reaches its host through.
private func embeddedHostServices()->Viewer.HostServices
{
    with var result: #returntype
    {
        .reportFailure            = &reportEmbeddedFailure
        .reportDetails            = &reportEmbeddedDetails
        .reportInformationChanged = &reportEmbeddedInformationChanged
        .reportChromeChanged      = &reportEmbeddedChromeChanged
        .reportLoadingChanged     = &reportEmbeddedLoadingChanged
    }

    return result
}

impl Viewer.Embedded for EmbeddedViewer
{
    mtd impl open(fileName, title: string) fail
    {
        if not .instances.isEmpty() do
            fail Errors.BadParameterError{}
        if not File.exists(fileName) do
            fail Errors.FileNotFoundError{fileName: Errors.mkString(fileName)}

        .fileName = fileName
        .title    = title
        var choices = .owner.index.choices(fileName)
        if choices.count > 1 and choices[0].key == "image"
        {
            // A picture preview already has its intended presentation. Raw-byte readers add no
            // useful choice there, whether the picture came from a comic page or an archive.
            .choices.add(choices[0])
        }
        else
        {
            .choices = #move choices
        }

        if .choices.isEmpty() do
            fail Errors.UnsupportedFormatError{}

        .instances.resize(.choices.count)
        .titleLabel.toolTip = title
        .viewerMenu.show(.choices.count > 1)
        if not .activate(0) do
            fail Errors.InvalidFormatError{}
    }

    mtd impl retire()->bool
    {
        for &instance in .instances where not instance.retireView() do
            return false
        .sideSplitter.items[0]!.view = .outlinePlaceholder
        .sideSplitter.items[2]!.view = .sidePlaceholder
        .sideSplitter.setPaneVisible(0, false)
        .sideSplitter.setPaneVisible(2, false)
        for &instance in .instances do
            instance.destroyWindows()

        .instances.clear()
        .choices.clear()
        .fileName.clear()
        .title.clear()
        .viewerMenu.hide()
        .infoLane.hide()
        .infoLane.position.width = 0
        .titleLabel.setText(Viewers.Archive.texts().ui_Select)
        .activeIndex       = Swag.U32.Max
        .currentView       = null
        .currentActions    = null
        .currentInfo       = null
        .currentCommands   = null
        .currentSidePanel  = null
        .currentSideButton = null
        .commandBar?.hide()
        .applyLayout()
        return true
    }

    mtd impl isLoading()->bool
    {
        if .activeIndex >= .instances.count do
            return false
        let instance = &.instances[.activeIndex]
        return instance.view and instance.isLoading and instance.isLoading()
    }
}

private impl EmbeddedViewer
{
    // Makes instance `index` the visible one, swapping in its view, actions, information, commands
    // and side panel, and sizes the information lane to what that instance needs.
    mtd showInstance(index: u32)
    {
        if .currentSideButton
        {
            let oldLeft        = .currentSideButton.id == OutlineToggleId
            let oldIndex       = oldLeft ? 0 : 2
            let oldPlaceholder = oldLeft ? .outlinePlaceholder : .sidePlaceholder
            .sideSplitter.items[oldIndex]!.view.hide()
            .sideSplitter.items[oldIndex]!.view = oldPlaceholder
            .sideSplitter.setPaneVisible(oldIndex, false)
        }

        .currentView?.hide()
        .currentActions?.hide()
        .currentInfo?.hide()
        .currentCommands?.hide()
        .currentSidePanel?.hide()
        .currentSideButton?.hide()

        let instance = &.instances[index]
        .currentView       = instance.view
        .currentActions    = instance.actions
        .currentInfo       = instance.info
        .currentCommands   = instance.commands
        .currentSidePanel  = instance.sidePanelHost
        .currentSideButton = instance.sidePanelButton
        .activeIndex       = index
        .titleLabel.setText(instance.details)
        .titleLabel.toolTip = instance.details
        let plugin = &.owner.index.plugins[.choices[index].pluginIndex]
        .viewerMenu.setQuietText(plugin.displayName())

        var infoWidth: f32
        if instance.info do
            infoWidth = instance.info.preferredSize.x
        if instance.sidePanelButton
        {
            infoWidth += themeActionButtonSize(.themeMetrics()) + 8
            instance.sidePanelButton.dockStyle = .Left
        }

        .infoLane.position.width = infoWidth
        .infoLane.show(infoWidth > 0)

        .currentView?.show()
        .currentActions?.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .currentSideButton?.show()
        let sideVisible = .currentSideButton?.isChecked orelse false
        let left        = .currentSideButton and .currentSideButton.id == OutlineToggleId
        let paneIndex   = left ? 0 : 2
        let placeholder = left ? .outlinePlaceholder : .sidePlaceholder
        .sideSplitter.items[paneIndex]!.view = .currentSidePanel orelse placeholder
        .sideSplitter.items[paneIndex]!.view.show(sideVisible)
        .sideSplitter.setPaneVisible(paneIndex, sideVisible)
        .sideSplitter.applyLayout()
        .applyLayout()
        .layoutCommands()
        .invalidate()
    }

    // Shows the viewers the entry can be seen in under their menu, the one in use checked.
    mtd showViewerMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        for choice, index in .choices
        {
            let plugin = &.owner.index.plugins[choice.pluginIndex]
            let item   = menu.addRadioItem(plugin.displayName(), Format.toString("scope.embedded.viewer.%", index), checked: index == .activeIndex)
            item.icon = .owner.pluginIcon(plugin, themeRowIconSize(.themeMetrics()))
        }

        let chosen = menu.doModal(.viewerMenu, autoDestroy: true) orelse ""
        for index in .choices.count where chosen == Format.toString("scope.embedded.viewer.%", index).toString() do
            discard .activate(cast(u32, index))
    }

    // Stands the viewer's commands on their mini-bar at the foot of the document, as wide as they
    // ask and never wider than the document.
    mtd layoutCommands()
    {
        let bar = .commandBar
        if not bar do
            return
        let commands = visibleViewerCommands(.currentCommands)
        bar.show(commands != null)
        let reserve = commands ? commands.position.height + bar.padding.y + bar.padding.w + 2 * .themeMetrics().miniBar_Distance : 0
        if .sideSplitter.margin.w != reserve
        {
            .sideSplitter.margin.w = reserve
            .applyLayout()
        }

        if not commands do
            return

        let metrics = .themeMetrics()
        var area    = .clientRect()
        area.height = Math.max(area.height - (.externalReadings ? 0 : .header.position.height), 0)
        let inset  = metrics.floating_Inset
        let pad    = bar.padding
        let room   = Math.max(area.width - 2 * inset - pad.x - pad.z, 0)
        let wanted = commands.preferredSize.x > 0 ? commands.preferredSize.x : room
        let width  = Math.min(wanted, room)
        let height = commands.position.height + pad.y + pad.w
        bar.setPosition(Math.Rectangle{Math.round(area.x + area.width * 0.5 - (width + pad.x + pad.z) * 0.5), area.bottom() - inset - height, width + pad.x + pad.z, height}, computeLayout: false)
        commands.dockStyle = .None
        commands.setPosition(Math.Rectangle{pad.x, pad.y, width, commands.position.height}, computeLayout: false)
        commands.applyLayout()
    }

    // Shows the viewer of `choices[index]`, creating its instance on first use and keeping it for
    // later switches. A viewer that fails becomes the failure surface; returns false when the index
    // is out of range or no view could be made.
    internal mtd activate(index: u32)->bool
    {
        if index >= .choices.count do
            return false
        if .instances[index].view
        {
            .showInstance(index)
            return true
        }

        let choice       = &.choices[index]
        let plugin       = &.owner.index.plugins[choice.pluginIndex]
        let sideSplitter = .sideSplitter
        var next:      ViewerSession
        with var host: ViewerPluginHost
        {
            .thumbnail       = me.informationOnly or me.owner.thumbnailMode
            .embedded        = true
            .session         = &next
            .documentParent  = me.document
            .sideSplitter    = sideSplitter
            .sidePanelParent = sideSplitter
            .sidePaneIndex   = 2
            .actionParent    = me.header
            .infoParent      = me.infoLane
            .commandParent   = unwrap me.commandBar
            .sourceFileName  = me.fileName
            .pluginIcon      = me.owner.pluginIcon(plugin, themeActionIconSize(me.themeMetrics()))
            .window          = me.owner
            .hostServices    = embeddedHostServices()
        }

        let pluginHost: Viewer.Host = &host
        catch next.create(plugin, pluginHost) { next.failureReason = Viewer.failureText(Swag.err) }
        if not next.failureReason.isEmpty() do
            next.replaceWithFailure(.document)

        if not next.view do
            return false

        next.view.dockStyle = .Center
        if next.actions do
            next.actions.dockStyle = .Left
        if next.info do
            next.info.dockStyle = .Center
        next.actions?.hide()
        next.info?.hide()
        next.commands?.hide()
        next.sidePanelButton?.hide()
        next.sidePanelHost?.hide()
        .instances[index] = #move next
        .showInstance(index)
        return true
    }

    // Replaces the instance showing `view` with an error view stating `reason`, showing it at once
    // when it is the active instance. Does nothing while `view` cannot retire yet.
    mtd replaceFailure(view: *Wnd, reason: string)
    {
        for &instance, index in .instances where instance.view == view
        {
            if not instance.retireView() do
                return
            instance.destroyWindows()
            instance[]              = {}
            instance.failureReason  = reason
            instance.view           = ViewerErrorView.create(.document, reason)
            instance.view.dockStyle = .Center
            if index == .activeIndex do
                .showInstance(cast(u32, index))
            return
        }
    }

    // Builds the entry document with bottom readings and a reserved command panel.
    // The enclosing archive owns the name and return action.
    internal func create(parent: *Wnd, owner: *ViewerWindow, readings: *Wnd? = null)->*EmbeddedViewer
    {
        with let result = Wnd.create'EmbeddedViewer(parent, "scope.embedded")
        {
            .backgroundStyle = .View
            .dockStyle       = .Center
            .owner           = owner
        }

        // The mini-bar the commands float on comes first: every resize places it again.
        with let commandBar = FloatingPanel.create(result, {0, 0, 0, ViewerWindow.BarHeight}, "scope.embedded.commands")
        {
            let pad = result.themeMetrics().miniBar_Padding
            .corner  = result.themeMetrics().miniBar_Corner
            .padding = Math.Vector4{x: pad * 2, y: pad, z: pad * 2, w: pad}
            .hide()
        }

        result.commandBar = commandBar

        result.externalReadings = readings != null
        with result.header = Wnd.create'ViewerInfoGroup(readings orelse cast(*Wnd, result), {0, 0, 0, EmbeddedHeaderHeight})
        {
            .dockStyle       = readings ? .Center : .Bottom
            .backgroundStyle = .Transparent
            if not readings do
                .margin = {result.themeMetrics().floating_Inset, 0, result.themeMetrics().floating_Inset, 4}
        }

        with result.viewerMenu = IconButton.createQuiet(result.header)
        {
            .dockStyle = .Left
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigPressed += func|embedded = result|(_) { embedded.showViewerMenu() }
        }

        with result.infoLane = Wnd.create'Wnd(result.header, {0, 0, 0, 32})
        {
            .dockStyle       = .Right
            .backgroundStyle = .Transparent
            .hide()
        }

        with result.titleLabel = Label.create(result.header, Viewers.Archive.texts().ui_Select, {}, null, .Ellipsis)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .style.addStyleSheetColors("label_Text $label_TextFaint")
            .setTextAlignment(.Left, .OpticalCenter)
        }

        result.titleLabel.show(not result.externalReadings)
        with result.sideSplitter = SplitterCtrl.create(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with result.document = Wnd.create'Wnd(result.sideSplitter)
        {
            .backgroundStyle = .View
        }

        with result.outlinePlaceholder = Wnd.create'Wnd(result.sideSplitter)
        {
            .backgroundStyle = .Transparent
            .hide()
        }

        let gutter        = result.themeMetrics().floating_Inset
        let leftWidth     = (owner.leftPanelWidth > 0 ? owner.leftPanelWidth : ViewerWindow.RightPanelDefaultWidth) + gutter
        with let leftItem = result.sideSplitter.addPane(result.outlinePlaceholder, leftWidth)
        {
            .minimumSize  = ViewerWindow.RightPanelMinWidth + gutter
            .maximumSize  = ViewerWindow.RightPanelMaxWidth + gutter
            .preserveSize = true
        }

        result.sideSplitter.addPane(result.document).minimumSize = ViewerWindow.DocumentMinWidth
        with result.sidePlaceholder = Wnd.create'Wnd(result.sideSplitter)
        {
            .backgroundStyle = .Transparent
            .hide()
        }

        let rightWidth    = owner.rightPanelWidth > 0 ? owner.rightPanelWidth : ViewerWindow.RightPanelDefaultWidth
        with let sideItem = result.sideSplitter.addPane(result.sidePlaceholder, rightWidth + gutter)
        {
            .minimumSize  = ViewerWindow.RightPanelMinWidth + gutter
            .maximumSize  = ViewerWindow.RightPanelMaxWidth + gutter
            .preserveSize = true
        }

        result.sideSplitter.setPaneVisible(0, false)
        result.sideSplitter.setPaneVisible(2, false)

        result.applyLayout()
        return result
    }
}

private impl IWnd for EmbeddedViewer
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .sideSplitter != null do
            ViewerWindow.fitDocumentPanes(.sideSplitter, .clientRect().width)
        .layoutCommands()
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        if evt.serializer.isReading()
        {
            if .owner.leftPanelWidth > 0
            {
                let width = .owner.leftPanelWidth + .themeMetrics().floating_Inset
                if .sideSplitter.items[0]!.view.isLocallyVisible()
                    do
                    .sideSplitter.setPaneSize(0, width)
                else do
                    .sideSplitter.items[0]!.size = width
            }

            if .owner.rightPanelWidth > 0
            {
                let width = .owner.rightPanelWidth + .themeMetrics().floating_Inset
                if .sideSplitter.items[2]!.view.isLocallyVisible()
                    do
                    .sideSplitter.setPaneSize(2, width)
                else do
                    .sideSplitter.items[2]!.size = width
            }

            if .owner.leftPanelWidth > 0 or .owner.rightPanelWidth > 0 do
                .sideSplitter.sendResizeEvent()

            return
        }

        if .sideSplitter.items[0]!.view != .outlinePlaceholder do
            .owner.leftPanelWidth = .sideSplitter.items[0]!.size - .themeMetrics().floating_Inset
        if .sideSplitter.items[2]!.view != .sidePlaceholder do
            .owner.rightPanelWidth = .sideSplitter.items[2]!.size - .themeMetrics().floating_Inset
    }
}
