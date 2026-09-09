#global internal

using Core, Gui

// A comparison panel selects a viewer type and owns its independent compilation state.
struct ViewerPanel
{
    using wnd: Wnd
        late
    {
        kindCombo:    *ComboBox
        sourceEditor: *RichEditCtrl
    }

    viewer:       IViewer?
    kind:         ViewerKind
    initialLevel: Swag.BuildCfgBackendOptimLevel
    sigChanged:   SigArray'func||(*ViewerPanel)
}

impl ViewerPanel
{
    const MinWidth = 330.0

    func create(parent: *Wnd, sourceEditor: *RichEditCtrl, level: Swag.BuildCfgBackendOptimLevel)->*ViewerPanel
    {
        let result = Wnd.create'ViewerPanel(parent, "prism.viewerPanel")
        result.backgroundStyle     = .Panel
        result.padding             = 8
        result.sourceEditor        = sourceEditor
        result.initialLevel        = level
        result.kindCombo           = ComboBox.create(result, {}, "prism.viewer.kind")
        result.kindCombo.dockStyle = .Top
        result.kindCombo.margin    = {0, 0, 0, 8}
        result.retranslate()
        result.selectViewer(.Microcode)
        result.kindCombo.sigChanged += func|panel = result|(combo, index)
        {
            discard combo
            panel.selectViewer(cast(ViewerKind) index)
        }
        result.applyLayout()
        return result
    }

    mtd selectViewer(kind: ViewerKind)
    {
        if .viewer and .kind == kind do
            return
        if .viewer
        {
            .viewer!.shutdown()
            .viewer!.window().destroy()
        }

        .kind   = kind
        .viewer = createViewer(me, .sourceEditor, kind, .initialLevel)
        .viewer!.window().dockStyle = .Center
        .viewer!.subscribeChanged(func|panel = me|(sender)
        {
            discard sender
            panel.sigChanged.call(panel)
        })
        .kindCombo.setSelectedIndex(cast(u32) kind, notify: false)
        .applyLayout()
        .sigChanged.call(me)
    }

    mtd compile(source: string) { .viewer!.compile(source) }
    mtd shutdown() { .viewer!.shutdown() }
    mtd isRunning()->bool => .viewer!.isRunning()

    mtd retranslate()
    {
        .kindCombo.toolTip = appStrings().ui_ViewerType
        .kindCombo.clear()
        .kindCombo.addItem(appStrings().ui_Microcode)
        .kindCombo.setSelectedIndex(cast(u32) .kind, notify: false)
        .applyLayout()
    }
}

impl IWnd for ViewerPanel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }
}
