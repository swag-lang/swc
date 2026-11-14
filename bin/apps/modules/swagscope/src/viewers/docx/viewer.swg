#global internal
#global namespace Viewers.Docx

using Core, Gui

// Offers readable Word text before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "docx"
        .staticName   = "Word document"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Docx)
        .create       = &createViewer
        .smokeFixture = "viewer.docx"
        .addSelectors(".docx")
    }
    return result
}

// The reading page around the main WordprocessingML body.
struct Panel
{
    using wnd: Wnd

    document: Document
    load:     Viewer.BackgroundLoad'Document
    services: Viewer.HostServices
    view:     *HtmlView?
    late status: *Label
}

private impl IWnd for Panel
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

        var style = HtmlStyle.theme()
        style.maxContentWidth = 680
        with .view = HtmlView.createText(me, .document.html, style)
        {
            .dockStyle = .Center
        }
        .status.hide()
        .applyLayout()
        .services.showDetails(me, Format.toString(texts().ui_Details, .document.paragraphs, .document.tables, .document.omittedImages))
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .document.paragraphs do
            .services.showDetails(me, Format.toString(texts().ui_Details, .document.paragraphs, .document.tables, .document.omittedImages))
        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    internal mtd retire()->bool => .load.retire()

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.docx")
        {
            .backgroundStyle = .View
            .services        = host.services()
        }
        with result.status = Label.create(result, texts().ui_Preparing, {}, null, .WordWrap)
        {
            .dockStyle       = .Center
            .backgroundStyle = .View
            .setTextAlignment(.Center, .Center)
        }
        result.load.start(host.fileName(), &Document.load, result)
        result.applyLayout()
        return result
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setLifecycle(Viewer.loadLifecycle(view))
}
