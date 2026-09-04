#global internal

using Core, Gui

private const EmbeddedHeaderHeight = 44.0

// Application implementation of [[Viewer.Embedded]].
struct EmbeddedViewer
{
    using wnd: Wnd

        late
    {
        header:      *Wnd
        titleLabel:  *Label
        viewerCombo: *ComboBox
        infoLane:    *Wnd
        document:    *Wnd
        commandBar:  *ViewerActionBar
    }

    late owner:        *ViewerWindow
    fileName:          String
    title:             String
    choices:           Array'ViewerPluginChoice
    instances:         Array'ViewerSession
    activeIndex = Swag.U32.Max
    currentView:       *Wnd?
    currentActions:    *Wnd?
    currentInfo:       *Wnd?
    currentCommands:   *Wnd?
    currentSidePanel:  *Wnd?
    currentSideButton: *IconButton?
}

private func embeddedViewerFor(view: *Wnd)->*EmbeddedViewer
{
    var parent = view.parent
    while parent and !parent.userData do
        parent = parent.parent
    Debug.assert(parent != null and parent.userData != null)
    return cast(*EmbeddedViewer) parent!.userData!
}

private func reportEmbeddedFailure(view: *Wnd, reason: string)
{
    embeddedViewerFor(view).replaceFailure(view, reason)
}

private func reportEmbeddedDetails(view: *Wnd, details: string)
{
    let embedded = embeddedViewerFor(view)
    for &instance in embedded.instances where instance.view == view
    {
        instance.details = details
        return
    }
}

private func reportEmbeddedChromeChanged(view: *Wnd)
{
    let embedded = embeddedViewerFor(view)
    embedded.commandBar.centerContent()
    embedded.applyLayout()
}

private func reportEmbeddedLoadingChanged(view: *Wnd)
{
    discard view
}

impl Viewer.Embedded for EmbeddedViewer
{
    mtd impl open(fileName, title: string) fail
    {
        if !.instances.isEmpty() do
            fail Errors.BadParameterError{"embedded viewer already has an open file"}
        if !File.exists(fileName) do
            fail Errors.FileNotFoundError{fileName: Errors.mkString(fileName)}

        .fileName = fileName
        .title    = title
        .choices  = .owner.index.choices(fileName)
        if .choices.isEmpty() do
            fail Errors.UnsupportedFormatError{"no viewer can show the embedded file"}

        .instances.resize(.choices.count)
        .viewerCombo.clear()
        for choice in .choices
        {
            let plugin = &.owner.index.plugins[choice.pluginIndex]
            .viewerCombo.addItem(plugin.displayName(), icon: .owner.pluginIcon(plugin, themeRowIconSize(.themeMetrics())))
        }

        .titleLabel.setText(title)
        .viewerCombo.show(.choices.count > 1)
        .viewerCombo.setSelectedIndex(0, notify: false)
        if !.activate(0) do
            fail Errors.InvalidFormatError{"embedded viewer could not create its selected view"}
    }

    mtd impl retire()->bool
    {
        for &instance in .instances where !instance.retireView() do
            return false

        for &instance in .instances
        {
            instance.actions?.destroy()
            instance.info?.destroy()
            instance.commands?.destroy()
            instance.sidePanelButton?.destroy()
            instance.sidePanelHost?.destroy()
            instance.view?.destroy()
        }

        .instances.clear()
        .choices.clear()
        .fileName.clear()
        .title.clear()
        .viewerCombo.clear()
        .viewerCombo.hide()
        .infoLane.hide()
        .infoLane.position.width = 0
        .titleLabel.setText(archiveStrings().ui_Select)
        .activeIndex                = Swag.U32.Max
        .currentView                = null
        .currentActions             = null
        .currentInfo                = null
        .currentCommands            = null
        .currentSidePanel           = null
        .currentSideButton          = null
        .commandBar.centerGroup     = null
        .commandBar.position.height = .themeMetrics().panel_GutterSize
        .applyLayout()
        return true
    }

    mtd impl isLoading()->bool
    {
        if .activeIndex >= .instances.count do
            return false
        let instance = &.instances[.activeIndex]
        return instance.view and instance.isLoading and instance.isLoading!(instance.view!)
    }
}

private impl EmbeddedViewer
{
    mtd showInstance(index: u32)
    {
        .currentView?.hide()
        .currentActions?.hide()
        .currentInfo?.hide()
        .currentCommands?.hide()
        .currentSidePanel?.hide()
        .currentSideButton?.hide()

        let instance = &.instances[index]
        .currentView                = instance.view
        .currentActions             = instance.actions
        .currentInfo                = instance.info
        .currentCommands            = instance.commands
        .currentSidePanel           = instance.sidePanelHost
        .currentSideButton          = instance.sidePanelButton
        .activeIndex                = index
        .commandBar.centerGroup     = .currentCommands
        .commandBar.position.height = .currentCommands ? ViewerBarHeight : .themeMetrics().panel_GutterSize

        var infoWidth: f32
        if instance.info do
            infoWidth = instance.info!.preferredSize.x
        if instance.sidePanelButton
        {
            infoWidth += themeActionButtonSize(.themeMetrics()) + 8
            instance.sidePanelButton!.dockStyle = .Right
        }

        .infoLane.position.width = infoWidth
        .infoLane.show(infoWidth > 0)

        .currentView?.show()
        .currentActions?.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .currentSideButton?.show()
        if .currentSideButton do
            .currentSidePanel?.show(.currentSideButton!.isChecked)
        .commandBar.centerContent()
        .applyLayout()
        .invalidate()
    }

    mtd activate(index: u32)->bool
    {
        if index >= .choices.count do
            return false
        if .instances[index].view
        {
            .showInstance(index)
            return true
        }

        let choice = &.choices[index]
        let plugin = &.owner.index.plugins[choice.pluginIndex]
        var next: ViewerSession
        var host   = ViewerPluginHost{
            session: &next,
            documentParent: .document,
            sidePanelParent: me,
            actionParent: .header,
            infoParent: .infoLane,
            commandParent: .commandBar,
            sourceFileName: .fileName.toString(),
            pluginIcon: .owner.pluginIcon(plugin, themeActionIconSize(.themeMetrics())),
            window: .owner,
            hostServices: {
                reportFailure: &reportEmbeddedFailure,
                reportDetails: &reportEmbeddedDetails,
                reportChromeChanged: &reportEmbeddedChromeChanged,
                reportLoadingChanged: &reportEmbeddedLoadingChanged}}
        let pluginHost: Viewer.Host = &host
        catch next.create(plugin, pluginHost) as viewerError
        if viewerError != null do
            next.failureReason = Errors.message(viewerError)
        if !next.failureReason.isEmpty()
        {
            let reason = #move next.failureReason
            next.actions?.destroy()
            next.info?.destroy()
            next.commands?.destroy()
            next.sidePanelButton?.destroy()
            next.sidePanelHost?.destroy()
            next.view?.destroy()
            next               = {}
            next.failureReason = #move reason
            next.view          = ViewerErrorView.create(.document, next.failureReason.toString())
        }

        if !next.view do
            return false

        next.view!.dockStyle = .Center
        if next.actions do
            next.actions!.dockStyle = .Left
        if next.info do
            next.info!.dockStyle = .Center
        next.actions?.hide()
        next.info?.hide()
        next.commands?.hide()
        next.sidePanelButton?.hide()
        next.sidePanelHost?.hide()
        .instances[index] = #move next
        .showInstance(index)
        return true
    }

    mtd replaceFailure(view: *Wnd, reason: string)
    {
        for &instance, index in .instances where instance.view == view
        {
            if !instance.retireView() do
                return
            instance.actions?.destroy()
            instance.info?.destroy()
            instance.commands?.destroy()
            instance.sidePanelButton?.destroy()
            instance.sidePanelHost?.destroy()
            instance.view?.destroy()
            instance[]               = {}
            instance.failureReason   = reason
            instance.view            = ViewerErrorView.create(.document, reason)
            instance.view!.dockStyle = .Center
            if index == .activeIndex do
                .showInstance(cast(u32) index)
            return
        }
    }

    func create(parent: *Wnd, owner: *ViewerWindow)->*EmbeddedViewer
    {
        let result = Wnd.create'EmbeddedViewer(parent, "scope.embedded")
        result.backgroundStyle = .View
        result.dockStyle       = .Center
        result.owner           = owner

        with result.header = Wnd.create'Wnd(result, {0, 0, 0, EmbeddedHeaderHeight})
        {
            .dockStyle       = .Top
            .backgroundStyle = .ToolBar
            .padding         = {12, 4, 12, 4}
        }

        with result.viewerCombo = ComboBox.create(result.header, {0, 0, 176, 36})
        {
            .dockStyle = .Right
            .toolTip   = appStrings().ui_Viewer
            .hide()
            .sigChanged += func|embedded = result|(combo, index)
            {
                discard combo
                if index != Swag.U32.Max do
                    discard embedded.activate(index)
            }
        }

        with result.infoLane = Wnd.create'Wnd(result.header, {0, 0, 0, 36})
        {
            .dockStyle       = .Right
            .backgroundStyle = .Transparent
            .margin.z        = 8
            .hide()
        }

        with result.titleLabel = Label.create(result.header, archiveStrings().ui_Select, {}, null, .Ellipsis)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .setTextAlignment(.Left, .Center)
        }

        with result.commandBar = ViewerActionBar.create(result)
        {
            .position.height = result.themeMetrics().panel_GutterSize
            .dockStyle       = .Bottom
        }

        with result.document = Wnd.create'Wnd(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .userData        = result
        }

        result.applyLayout()
        return result
    }
}
