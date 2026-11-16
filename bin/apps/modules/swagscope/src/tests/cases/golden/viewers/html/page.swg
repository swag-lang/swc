#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Authored page widths and figures stay centered, with no second outline over the reading column.
#[Swag.TestTag("golden")]
#test
{
    let file = Testing.tempFilePath("scope-html-centered-", ".html")
    defer discard catch File.delete(file)
    const Source = """<!doctype html><html><meta charset='utf-8'><title>Reading</title>
                   <style>
                   body { font:18px/1.55 Georgia,serif; max-width:860px; margin:2rem auto;
                          padding:0 1rem; color:#222; background:#fbf8f1 }
                   img { max-width:100%%; height:auto; display:block; margin:1rem auto }
                   </style><body>
                   <h1>A little room to read</h1><h2>A centered page</h2>
                   <p>The document keeps its own typography, reading measure and illustrations.</p>
                   <img src='%' width='1000'>
                   <h2>Only the document</h2>
                   <p>The full outline is available from its window command.</p>
                   </body></html>
                   """
    let source = Format.toString(Source, scopeTestDataPath("markdown.images.svg"))
    discard expect File.writeAllText(file, source)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, false, 1280, 680)
    host.surface.setTitle("Reading.html")
    let panel = assume cast(*Html.Panel, window.currentView)
    Swag.require(panel.children.count == 1 and panel.children[0] == cast(*Wnd, panel.view))
    Swag.require(not window.currentSidePanelHost!.isLocallyVisible())
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.html.centered.encre")
}
