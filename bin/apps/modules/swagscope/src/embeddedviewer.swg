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
    activeIndex:       u32 = Swag.U32.Max
    currentView:       *Wnd?
    currentActions:    *Wnd?
    currentInfo:       *Wnd?
    currentCommands:   *Wnd?
    currentSidePanel:  *Wnd?
    currentSideButton: *IconButton?
}

private func embeddedViewerFor(view: *Wnd)->*EmbeddedViewer => view.ancestorByType'EmbeddedViewer()!

private func reportEmbeddedFailure(view: *Wnd, reason: string)
{
    embeddedViewerFor(view).replaceFailure(view, reason)
}

private func reportEmbeddedDetails(view: *Wnd, details: string)
{
    for &instance in embeddedViewerFor(view).instances where instance.view == view
    {
        instance.details = details
        return
    }
}

private func reportEmbeddedChromeChanged(view: *Wnd)
{
    with let embedded = embeddedViewerFor(view)
    {
        .commandBar.centerContent()
        .applyLayout()
    }
}

private func reportEmbeddedLoadingChanged(_: *Wnd) {}

// Returns the services a viewer embedded in a document reaches its host through.
private func embeddedHostServices()->Viewer.HostServices
{
    with var result: retval
    {
        .reportFailure        = &reportEmbeddedFailure
        .reportDetails        = &reportEmbeddedDetails
        .reportChromeChanged  = &reportEmbeddedChromeChanged
        .reportLoadingChanged = &reportEmbeddedLoadingChanged
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
        .choices  = .owner.index.choices(fileName)
        if .choices.isEmpty() do
            fail Errors.UnsupportedFormatError{}

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
        if not .activate(0) do
            fail Errors.InvalidFormatError{}
    }

    mtd impl retire()->bool
    {
        for &instance in .instances where not instance.retireView() do
            return false
        for &instance in .instances do
            instance.destroyWindows()

        .instances.clear()
        .choices.clear()
        .fileName.clear()
        .title.clear()
        .viewerCombo.clear()
        .viewerCombo.hide()
        .infoLane.hide()
        .infoLane.position.width = 0
        .titleLabel.setText(Viewers.Archive.texts().ui_Select)
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
        return instance.view and instance.isLoading and instance.isLoading()
    }
}

private impl EmbeddedViewer
{
    // Makes instance `index` the visible one, swapping in its view, actions, information, commands
    // and side panel, and sizes the information lane to what that instance needs.
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
        .commandBar.position.height = .currentCommands ? ViewerWindow.BarHeight : .themeMetrics().panel_GutterSize

        var infoWidth: f32
        if instance.info do
            infoWidth = instance.info.preferredSize.x
        if instance.sidePanelButton
        {
            infoWidth += themeActionButtonSize(.themeMetrics()) + 8
            instance.sidePanelButton.dockStyle = .Right
        }

        .infoLane.position.width = infoWidth
        .infoLane.show(infoWidth > 0)

        .currentView?.show()
        .currentActions?.show()
        .currentInfo?.show()
        .currentCommands?.show()
        .currentSideButton?.show()
        if .currentSideButton do
            .currentSidePanel?.show(.currentSideButton.isChecked)
        .commandBar.centerContent()
        .applyLayout()
        .invalidate()
    }

    // Shows the viewer of `choices[index]`, creating its instance on first use and keeping it for
    // later switches. A viewer that fails becomes the failure surface; returns false when the index
    // is out of range or no view could be made.
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
        var next:      ViewerSession
        with var host: ViewerPluginHost
        {
            .session         = &next
            .documentParent  = me.document
            .sidePanelParent = me
            .actionParent    = me.header
            .infoParent      = me.infoLane
            .commandParent   = me.commandBar
            .sourceFileName  = me.fileName
            .pluginIcon      = me.owner.pluginIcon(plugin, themeActionIconSize(me.themeMetrics()))
            .window          = me.owner
            .hostServices    = embeddedHostServices()
        }

        let pluginHost: Viewer.Host = &host
        catch next.create(plugin, pluginHost) as viewerError
        if viewerError != null do
            next.failureReason = Viewer.failureText(viewerError)
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

    // Builds the embedded viewer: a header holding the entry title, information lane and viewer
    // selector, a bottom command bar, and the document area where the active instance docks.
    func create(parent: *Wnd, owner: *ViewerWindow)->*EmbeddedViewer
    {
        with let result = Wnd.create'EmbeddedViewer(parent, "scope.embedded")
        {
            .backgroundStyle = .View
            .dockStyle       = .Center
            .owner           = owner
        }

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
            .sigChanged += func|embedded = result|(_, index)
            {
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

        with result.titleLabel = Label.create(result.header, Viewers.Archive.texts().ui_Select, {}, null, .Ellipsis)
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
        }

        result.applyLayout()
        return result
    }
}
