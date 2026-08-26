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

    let request = ViewerRequest{&host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    createHtmlViewer(&request, &result)
    @assert(result.view != null)
    @assert(result.commands == null and result.revealMatch != null and result.searchBounds != null and result.clearSearch != null and result.isLoading != null)
    @assert(result.isLoading!(result.view!))
    @assert(Utf8.contains(result.details.toString(), "HTML"))

    var attempts: u32
    while result.isLoading!(result.view!) and attempts < 100
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
        attempts += 1
    }

    @assert(!result.isLoading!(result.view!))
}

// File-open failures cross the viewer boundary instead of becoming viewer-specific content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_sfilescope_html_%.html", Guid64.random()).toString())
    let request  = ViewerRequest{&host.root, &host.root, fileName.toString()}
    var result: ViewerResult
    createHtmlViewer(&request, &result)
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}
