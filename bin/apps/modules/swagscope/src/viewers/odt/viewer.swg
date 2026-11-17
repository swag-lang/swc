#global internal
#global namespace Viewers.Odt

using Core, Gui

// Offers readable OpenDocument text before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "odt"
        .staticName   = "OpenDocument Text"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Odt)
        .create       = &createViewer
        .smokeFixture = "viewer.odt"
        .addSelectors(".odt")
    }

    return result
}

// The reading page around the OpenDocument text body.
struct Panel
{
    using wnd: Wnd

    properties:     Package.DocumentProperties     // What the package says of the document, once read.
    propertiesRead: bool

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
        style.followTheme     = false
        with .view = HtmlView.createText(me, .document.html, style)
        {
            .dockStyle = .Center
            .margin    = {.themeMetrics().floating_Inset, 0, .themeMetrics().floating_Inset, 0}
        }

        .outline.bindHtml(.view)
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

private impl Panel
{
    internal mtd retire()->bool => .load.retire()

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.odt")
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
    // once, the first time the sheet asks.
    internal mtd describeInformation(sheet: *InfoSheet)
    {
        if not .propertiesRead and not .load.fileName.isEmpty()
        {
            .properties     = Package.DocumentProperties.read(.load.fileName)
            .propertiesRead = true
        }

        var data: MediaInfoData
        .properties.describe(&data)
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
