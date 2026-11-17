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

    document:     Document
    load:         Viewer.BackgroundLoad'Document
    services:     Viewer.HostServices
    view:         *HtmlView?
    late status:  *Label
    late outline: *DocumentOutline
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
        style.followTheme     = not .document.usePaperColors
        with .view = HtmlView.createText(me, .document.html, style)
        {
            .dockStyle = .Center
        }

        .outline.bindHtml(.view)
        .status.hide()
        .applyLayout()
        .services.showDetails(me, .document.details())
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .document.paragraphs do
            .services.showDetails(me, .document.details())
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

        result.applyLayout()
        return result
    }
}

impl Panel
{
    // Describes the document in the information sheet with what its package says of it, read
    // with the document on the loading worker.
    internal mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        .document.properties.describe(&data)
        data.describe(sheet)
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })
    view.outline = DocumentOutline.create(host)
    view.load.start(host.fileName(), &Document.load, view)
    host.setLifecycle(Viewer.loadLifecycle(view))
}
