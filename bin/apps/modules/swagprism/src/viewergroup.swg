#global internal

using Core, Gui

// One comparison column hosts independently configured viewer tabs.
struct ViewerGroup
{
    using wnd: Wnd
        late
    {
        tabs:         *Tab
        sourceEditor: *RichEditCtrl
        addButton:    *PushButton
        closeButton:  *IconButton
    }

    viewers:      Array'IViewer
    initialLevel: Swag.BuildCfgBackendOptimLevel
    sigChanged:   SigArray'func||(*ViewerGroup)
}

impl ViewerGroup
{
    const MinWidth = 330.0

    func create(parent: *Wnd, sourceEditor: *RichEditCtrl, level: Swag.BuildCfgBackendOptimLevel)->*ViewerGroup
    {
        let result = Wnd.create'ViewerGroup(parent, "prism.viewerGroup")
        result.sourceEditor = sourceEditor
        result.initialLevel = level
        let actions = Wnd.create'Wnd(result, {0, 0, 0, 44})
        actions.dockStyle           = .Top
        actions.backgroundStyle     = .ToolBar
        actions.padding             = {8, 4, 8, 4}
        result.addButton            = PushButton.create(actions, appStrings().ui_AddViewer, {0, 0, 150, 36}, "prism.viewer.add")
        result.addButton.dockStyle  = .Left
        result.addButton.sigPressed += func|group = result|(button)
        {
            discard button
            group.addViewer(.Microcode)
        }
        result.closeButton = IconButton.create(actions, result.theme().icon(.WndClose, 16), {0, 0, 36, 36}, "prism.viewer.close")
        result.closeButton.setIconSize(16, 16)
        result.closeButton.dockStyle  = .Right
        result.closeButton.sigPressed += func|group = result|(button)
        {
            discard button
            group.closeSelected()
        }
        result.tabs           = Tab.create(result, {}, "prism.viewer.tabs")
        result.tabs.dockStyle = .Center
        result.tabs.setForms(.Flat, .Flat, .None)
        result.tabs.setLayout(.Equal, minimumItemWidth: 25)
        result.tabs.sigSelectionChanged += func|group = result|(tabs)
        {
            discard tabs
            group.sigChanged.call(group)
        }
        result.addViewer(.Microcode)
        result.retranslate()
        result.applyLayout()
        return result
    }

    mtd addViewer(kind: ViewerKind)
    {
        let viewer = createViewer(.tabs, .sourceEditor, kind, .initialLevel)
        viewer.subscribeChanged(func|group = me|(sender)
        {
            discard sender
            group.refreshTabs()
            group.sigChanged.call(group)
        })
        .viewers.add(viewer)
        .tabs.addItem(viewer.title().toString(), view: viewer.window())
        .tabs.setSelectedIndex(cast(u32) .viewers.count - 1)
        .closeButton.enable(.viewers.count > 1)
        .applyLayout()
        .sigChanged.call(me)
    }

    // A group keeps one page so its add action and comparison column always remain usable.
    mtd closeSelected()
    {
        if .viewers.count <= 1 do
            return
        let index = .tabs.selectedIndex
        .viewers[index].shutdown()
        .viewers.removeAtOrdered(index)
        .tabs.removeItemAt(index)
        .closeButton.enable(.viewers.count > 1)
        .sigChanged.call(me)
    }

    mtd compile(source: string)
    {
        if .tabs.selectedIndex < .viewers.count do
            .viewers[.tabs.selectedIndex].compile(source)
    }

    mtd shutdown()
    {
        for viewer in .viewers do
            viewer.shutdown()
    }

    mtd refreshTabs()
    {
        for viewer, index in .viewers do
            .tabs.setItemName(cast(u32) index, viewer.title().toString())
    }

    mtd retranslate()
    {
        .addButton.setText(appStrings().ui_AddViewer)
        .closeButton.toolTip = appStrings().ui_CloseViewer
        .refreshTabs()
        .applyLayout()
    }
}

impl IWnd for ViewerGroup
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }
}
