#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

// A narrow hosted page keeps a reading inset and retains its own CSS margin beside the outline.
#test
{
    let path = Testing.tempFilePath("scope-html-reading-inset-", ".html")
    defer discard catch File.delete(path)
    let source = "<!doctype html><html><head><style>body { margin: 32px }</style></head><body><h1>Reading together</h1><p>A quiet paragraph.</p></body></html>"
    discard expect File.writeAllBytes(path, source)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, path, true, 880, 520)
    let panel  = assume cast(*Html.Panel, window.currentView)
    window.sendCommandEvent(ViewerCommands.Outline)
    window.applyLayout()
    host.finishAnimations()
    let inset = panel.themeMetrics().floating_Inset
    Swag.require(panel.view.position.x >= inset)
    Swag.require(panel.view.position.right() <= panel.clientRect().width - inset)
    Swag.require(panel.view.findText("A quiet paragraph."))
    var bounds: Math.Rectangle
    Swag.require(panel.view.searchMatchRect(&bounds))
    Swag.require(bounds.x >= panel.view.surfaceRect().x + 31)
}
