#global internal
#global namespace Viewers.Rtf

using Core, Gui

// Reads formatted RTF body content before offering its raw source as basic text.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "rtf"
        .staticName   = "Rich text document"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Rtf)
        .create       = &createViewer
        .probe        = func(content: Viewer.ProbeContent)->bool => content.opensWith("{\\rtf")
        .textual      = true
        .smokeFixture = "viewer.rtf"
        .addSelectors(".rtf")
    }
    return result
}

// The reading page around one RTF body.
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
        .showDetails()
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .document.paragraphs do
            .showDetails()
        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    internal mtd retire()->bool => .load.retire()

    mtd showDetails()
    {
        .services.showDetails(me, Format.toString(texts().ui_Details, .document.paragraphs, .document.omittedObjects))
    }

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.rtf")
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
