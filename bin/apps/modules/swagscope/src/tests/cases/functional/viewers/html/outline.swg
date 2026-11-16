#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// The full outline of a page marks the heading being read as the page moves, without asking
// the page to move again, and keeps the mark through its filter.
#test
{
    let fileName = Testing.tempFilePath("scope-html-follow-", ".html")
    defer discard catch File.delete(fileName)
    var source: String = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body><h1>Guide</h1><p>Opening words.</p>"
    for section in 8
    {
        source += Format.toString("<h2>Part %</h2>", section)

        // The last part is short: it ends the page without room to rise to the top.
        for section == 7 ? 2 : 12 do
            source += "<p>A paragraph that gives the part some height on the page.</p>"
    }

    source += "</body></html>"
    discard expect File.writeAllBytes(fileName, source.toString())

    var host: HeadlessHost
    host.setup(880, 560)
    var result    = openTestViewer(Html.viewerPlugin(), &host.root, fileName)
    let panel     = assume cast(*Html.Panel, result.view)
    let isLoading = unwrap result.isLoading
    for 100 where isLoading()
    {
        Threading.Thread.sleep(5'ms)
        host.app.runFrame()
    }

    Swag.require(not isLoading())
    panel.resize(880, 560)
    panel.applyLayout()

    let outline  = unwrap panel.outline
    let headings = panel.view.headings()
    Swag.require(headings.count == 9 and outline.rows.count == 9)

    var chosen = 0
    outline.sigSelected += func|&chosen|(_, _) { chosen += 1 }
    Swag.require(outline.markedTarget() == Swag.U64.Max)

    Swag.require(panel.view.revealFileOffset(headings[4].sourceOffset, ""))
    Swag.require(outline.markedTarget() == headings[4].sourceOffset and chosen == 0)

    outline.setFilter("Part 1")
    Swag.require(outline.rows.count == 1 and outline.markedTarget() == headings[2].sourceOffset)
    outline.setFilter("")
    Swag.require(outline.markedTarget() == headings[4].sourceOffset)

    // Choosing the last part cannot bring it to the top: it stays the one marked.
    outline.list.selectLine(8)
    Swag.require(chosen == 1 and panel.view.readingProgress() >= 1)
    Swag.require(outline.markedTarget() == headings[8].sourceOffset)

    Swag.require(panel.view.navigateToFragment("#"))
    Swag.require(outline.markedTarget() == headings[0].sourceOffset)
}

// A page announces itself by how it opens, whatever its file is called, and nothing looser does.
#test
{
    var registry = createViewerPluginRegistry()

    const Pages: [4] string = [
        "<!doctype html><html></html>",
        "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"><html></html>",
        "<html lang=\"en\"><body></body></html>",
        "\n  <HTML><body></body></HTML>"]
    for source in Pages
    {
        let fileName = Testing.tempFilePath("scope-html-probe-", ".dat")
        defer discard catch File.delete(fileName)
        discard expect File.writeAllBytes(fileName, source)
        let choices = registry.choices(fileName)
        Swag.require(choices.count > 0 and choices[0].key == "html", source)
    }

    const Others: [3] string = [
        "<?xml version=\"1.0\"?><root><html/></root>",
        "A note that mentions <html> in passing.",
        "{% extends \"base.html\" %}"]
    for source in Others
    {
        let fileName = Testing.tempFilePath("scope-html-other-", ".dat")
        defer discard catch File.delete(fileName)
        discard expect File.writeAllBytes(fileName, source)
        let choices = registry.choices(fileName)
        Swag.require(choices.isEmpty() or choices[0].key != "html", source)
    }
}
