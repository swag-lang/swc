#global internal

using Core, Gui

// A formatted document retains its decoded model while a single reading page presents its HTML.
// Each reader supplies its paper, width and link policy. The host owns the page and its outline.
struct(T) RichDocumentPage
{
    using wnd: Wnd
    document:  T
    load:      Viewer.BackgroundLoad'T
    services:  Viewer.HostServices
    view:      *HtmlView?
    outline:   *DocumentOutline?
    openLink:  (func(string))?
    late
    {
        status:   *Label
        styleFor: func(const *T)->HtmlStyle
    }
}

impl IWnd for RichDocumentPage
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        let failure = .load.finish(&.document)
        if not failure.isEmpty()
        {
            .services.failed(me, failure)
            return
        }

        with .view = HtmlView.createText(me, .document.html, .styleFor(&.document))
        {
            .dockStyle = .Center
        }
        let margin = .themeMetrics().floating_Inset
        .view.margin = {margin, 0, margin, 0}
        if let open = .openLink do
            .view.sigLinkActivated += func|open|(_, url) { open!(url) }
        .outline?.bindHtml(.view)
        .status.hide()
        .applyLayout()
        .services.showDetails(me, .document.details())
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .view do
            .services.showDetails(me, .document.details())
        .wnd.IWnd.onNotifyEvent(evt)
    }
}

impl RichDocumentPage
{
    mtd retire()->bool => .load.retire()

    func create(host: Viewer.Host, id, preparing: string, styleFor: func(const *T)->HtmlStyle,
                withOutline = true)->*RichDocumentPage'T
    {
        with let result = Wnd.create'(RichDocumentPage'T)(host.contentParent(), id)
        {
            .backgroundStyle = .View
            .services        = host.services()
            .styleFor        = styleFor
        }
        result.status = Viewer.createLoadingLabel(result, preparing)
        host.attachView(result)
        if withOutline do
            result.outline = DocumentOutline.create(host)
        result.applyLayout()
        result.load.start(host.fileName(), &T.load, result)
        host.setLifecycle(Viewer.loadLifecycle(result))
        return result
    }
}
