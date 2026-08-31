#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The viewer remains a thin ABI adapter around the reusable GUI control.
#test
{
    let fileName = Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.html")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    var result = openTestViewer(htmlViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.view != null)
    Swag.assert(result.commands == null and result.info != null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null and result.isLoading != null)
    Swag.assert(result.isLoading!(result.view!))
    Swag.assert(Utf8.contains(result.details.toString(), "HTML"))
    let view = cast(*HtmlViewer) result.view!
    view.setZoom(150)
    Swag.assert(view.zoomPercent == 150 and view.view.documentStyle.bodyFontSize == 24)

    var attempts: u32
    while result.isLoading!(result.view!) and attempts < 100
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
        attempts += 1
    }

    Swag.assert(!result.isLoading!(result.view!))
}

// File-open failures cross the viewer boundary instead of becoming viewer-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_scope_html_%.html", Guid64.random()).toString())
    var result   = openTestViewer(htmlViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root)
    Swag.assert(result.view == null and result.commands == null)
    Swag.assert(!result.failureReason.isEmpty())
}
