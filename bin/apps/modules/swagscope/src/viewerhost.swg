#global internal

using Core, Gui

// One plugin instance and every contribution the host owns with it.
struct ViewerSession
{
    view:                #null *Wnd
    actions:             #null *Wnd
    info:                #null *Wnd
    commands:            #null *Wnd
    sidePanelHost:       #null *Wnd
    sidePanel:           #null *Wnd
    sidePanelButton:     #null *IconButton
    revealMatch:         #null Viewer.RevealSearchMatch
    searchBounds:        #null Viewer.SearchMatchBounds
    clearSearch:         #null Viewer.ClearSearch
    collectMatches:      #null Viewer.CollectSearchMatches
    filterSearch:        #null Viewer.ApplySearchFilter
    describeSearch:      #null Viewer.DescribeSearch
    prepareSearch:       #null Viewer.PrepareSearch
    collectFileMatches:  #null Viewer.CollectFileMatches
    useSearchMatches:    #null Viewer.UseSearchMatches
    isLoading:           #null Viewer.IsLoading
    needsLoadingOverlay: #null Viewer.NeedsLoadingOverlay
    retire:              #null Viewer.Retire
    details:             String
    failureReason:       String
}

impl ViewerSession
{
    // Creates one selected plugin and verifies the common session contract.
    mtd create(plugin: const *Viewer.Plugin, host: Viewer.Host) fail
    {
        plugin.create(host)
        if .view and !.failureReason.isEmpty() do
            fail Errors.InvalidFormatError{"viewer plugin returned both a document view and a rejection reason"}
        if !.view and .failureReason.isEmpty() do
            fail Errors.InvalidFormatError{"viewer plugin returned neither a document view nor a rejection reason"}
        if !.view and (.actions or .info or .commands) do
            fail Errors.InvalidFormatError{"viewer plugin returned chrome without a document view"}
    }

    // Requests resource release and reports whether GUI destruction may proceed.
    mtd retireView()->bool
    {
        if !.view or !.retire do
            return true
        if !.retire!(.view!) do
            return false
        .retire = null
        return true
    }
}

// Implements the plugin API for one Swag Scope viewer instance.
struct ViewerPluginHost
{
    session:         *ViewerSession = undefined
    documentParent:  *Wnd           = undefined
    sidePanelParent: *Wnd           = undefined
    actionParent:    *Wnd           = undefined
    infoParent:      *Wnd           = undefined
    commandParent:   *Wnd           = undefined
    sourceFileName:  string
    pluginIcon:      Icon
    hostServices:    Viewer.HostServices
    window:          #null *ViewerWindow
}

// One group a viewer contributes to the information band, sized to what it actually shows.
//
// The band lays the general details and this group out as one right-aligned run, so a group
// that always answered the width its author reserved would push the general details left by
// the room it is not using. That width stays the maximum; the content decides the rest.
struct ViewerInfoGroup
{
    using wnd: Wnd
}

impl IWnd for ViewerInfoGroup
{
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        var result:     retval
        var horizontal: f32
        var center:     f32
        for child in .children where child.isLocallyVisible()
        {
            let size  = child.itf.measureContent(available)
            let width = size.x + child.margin.x + child.margin.z
            if child.dockStyle == .Left or child.dockStyle == .Right do
                horizontal += width
            else do
                center = Math.max(center, width)
            result.y = Math.max(result.y, size.y + child.margin.y + child.margin.w)
        }

        result.x = horizontal + center
        return result
    }
}

private impl ViewerPluginHost
{
    mtd createGroup(parent: *Wnd, width: f32)->*Wnd
    {
        let result = Wnd.create'Wnd(parent, {0, 0, width, 36})
        result.backgroundStyle = .Transparent
        result.preferredSize.x = width
        return result
    }

    mtd createInfoWnd(parent: *Wnd, width: f32)->*Wnd
    {
        let result = Wnd.create'ViewerInfoGroup(parent, {0, 0, width, 36})
        result.backgroundStyle = .Transparent

        // The width the plugin asks for is the most this group may take, and the band shrinks the
        // group to what it shows. Recording it as the preferred size is what keeps the maximum
        // available after the first pass has already narrowed the group.
        result.preferredSize.x = width
        return result
    }
}

impl Viewer.Host for ViewerPluginHost
{
    mtd impl application()->*Application     => .documentParent.app()
    mtd impl contentParent()->*Wnd           => .documentParent
    mtd impl fileName()->string              => .sourceFileName
    mtd impl icon()->Icon                    => .pluginIcon
    mtd impl services()->Viewer.HostServices => .hostServices

    mtd impl createEmbedded(parent: *Wnd)->Viewer.Embedded
    {
        Debug.assert(.window != null, "embedded viewers need an application window")
        let embedded                = EmbeddedViewer.create(parent, .window!)
        let result: Viewer.Embedded = embedded
        return result
    }

    mtd impl createActionGroup(width: f32)->*Wnd
    {
        Debug.assert(.session.actions == null)
        .session.actions = .createGroup(.actionParent, width)
        return .session.actions!
    }

    mtd impl createInfoGroup(width: f32)->*Wnd
    {
        Debug.assert(.session.info == null)
        .session.info = .createInfoWnd(.infoParent, width)
        .session.info!.style.addStyleSheetColors("label_TextLight $label_TextFaint")
        .session.info!.computeStyle()
        return .session.info!
    }

    mtd impl createCommandGroup(width: f32)->*Wnd
    {
        Debug.assert(.session.commands == null)
        .session.commands = .createGroup(.commandParent, width)
        return .session.commands!
    }

    mtd impl createSidePanel(width: f32, icon: Icon, toolTip: string)->Viewer.SidePanel
    {
        Debug.assert(.session.sidePanelHost == null)
        Debug.assert(width > 0)

        let gutter = .sidePanelParent.themeMetrics().panel_GutterSize
        with .session.sidePanelHost = Wnd.create'Wnd(.sidePanelParent, {0, 0, width + gutter, 0})
        {
            .dockStyle       = .Right
            .backgroundStyle = .ToolBar

            // The information lane already owns the seam above. The viewer bar owns the chrome
            // below, so the side panel meets it directly instead of accumulating a second edge.
            .padding = {0, 0, gutter, 0}
            .hide()
        }

        with .session.sidePanel = Wnd.create'Wnd(.session.sidePanelHost!)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Panel
        }

        let panelParent = .sidePanelParent
        let panelHost   = .session.sidePanelHost!
        let actionSize  = themeActionButtonSize(.infoParent.themeMetrics())
        with .session.sidePanelButton = IconButton.create(.infoParent, icon, {0, 0, actionSize, actionSize}, flags: .Toggle)
        {
            .toolTip = toolTip
            .setCheckIndicator(.Frame)
            .hide()
            .sigCheckedChanged += func|parent = panelParent, panel = panelHost|(button)
            {
                panel.show(button.isChecked)
                parent.applyLayout()
                parent.invalidate()
            }
        }

        return {.session.sidePanel!, .session.sidePanelButton!}
    }

    mtd impl attachView(view: *Wnd)
    {
        Debug.assert(.session.view == null)
        .session.view = view
    }

    mtd impl setDetails(details: string)
    {
        .session.details = details
    }

    mtd impl reject(reason: string)
    {
        Debug.assert(.session.view == null)
        .session.actions?.destroy()
        .session.info?.destroy()
        .session.commands?.destroy()
        .session.sidePanelButton?.destroy()
        .session.sidePanelHost?.destroy()
        .session.actions         = null
        .session.info            = null
        .session.commands        = null
        .session.sidePanelHost   = null
        .session.sidePanel       = null
        .session.sidePanelButton = null
        .session.failureReason   = reason
    }

    mtd impl setSearch(api: Viewer.SearchApi)
    {
        .session.revealMatch        = api.revealMatch
        .session.searchBounds       = api.matchBounds
        .session.clearSearch        = api.clear
        .session.collectMatches     = api.collectMatches
        .session.filterSearch       = api.filter
        .session.describeSearch     = api.describe
        .session.prepareSearch      = api.prepare
        .session.collectFileMatches = api.collectFileMatches
        .session.useSearchMatches   = api.useMatches
    }

    mtd impl setLifecycle(api: Viewer.LifecycleApi)
    {
        .session.isLoading           = api.isLoading
        .session.needsLoadingOverlay = api.needsLoadingOverlay
        .session.retire              = api.retire
    }
}
