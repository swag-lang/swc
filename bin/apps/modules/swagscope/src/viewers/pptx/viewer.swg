#global internal
#global namespace Viewers.Pptx

using Core, Gui

// Offers ordered slide text before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "pptx"
        .staticName   = "Presentation"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Pptx)
        .create       = &createViewer
        .smokeFixture = "viewer.pptx"
        .addSelectors(".pptx")
    }
    return result
}

struct Panel
{
    using wnd: Wnd

    presentation: Presentation
    load:         Viewer.BackgroundLoad'Presentation
    services:     Viewer.HostServices
    view:         *HtmlView?
    late status:  *Label
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
        let failure = .load.finish(&.presentation)
        if not failure.isEmpty()
        {
            .services.failed(me, failure)
            return
        }
        var style = HtmlStyle.theme()
        style.maxContentWidth = 680
        with .view = HtmlView.createText(me, .presentation.html, style)
        {
            .dockStyle = .Center
        }
        .status.hide()
        .applyLayout()
        .services.showDetails(me, Format.toString(texts().ui_Details, .presentation.slides, .presentation.omittedImages))
        .services.loadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .presentation.slides do
            .services.showDetails(me, Format.toString(texts().ui_Details, .presentation.slides, .presentation.omittedImages))
        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    internal mtd retire()->bool => .load.retire()

    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.pptx")
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
        result.load.start(host.fileName(), &Presentation.load, result)
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
