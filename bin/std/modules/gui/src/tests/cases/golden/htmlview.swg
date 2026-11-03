#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// The complete fixture renders, and nothing a document hides reaches the drawn text.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let view = HtmlView.createText(&host.root, (expect File.readAllText(htmlFixturePath())).toString())
    view.resize(960, 680)
    view.applyLayout()
    view.rebuild()

    let text = view.document.textContent(0)
    Swag.assert(Utf8.contains(text.toString(), "Heading level one"))
    Swag.assert(Utf8.contains(text.toString(), "The distant html verification marker"))
    Swag.assert(not Utf8.contains(text.toString(), "must not render"))

    // A hidden container is parsed and then left out of the box tree entirely.
    for index in view.layout.boxes.count
    {
        let node = view.layout.constBox(cast(u32, index)).node
        if node == HtmlNoNode do
            continue
        Swag.assert(view.document.constNode(node).tag != .Script)
        Swag.assert(view.document.constNode(node).tag != .Template)
    }

    Swag.assert(view.layout.documentHeight > 680)

    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.document")
}

// Pins the generated API page in the browser reference's light palette and wide viewport: the
// overview cut, typography, section ornaments, note fills, and table alignment all pass through
// the production HTML view.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(1660, 1324)

    host.theme.setLight()
    host.app.notifyThemeChanged()
    host.notify(.ThemeChanged)

    let view = HtmlView.createFile(&host.root, guiFixturePath("std.pixel.html"))
    view.resize(1660, 1324)
    view.applyLayout()
    view.rebuild()
    var steps: u64
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    Swag.assert(not view.isLoading())

    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.pixel-api")
    view.stopLoading()
}

// Preserved white space draws the indentation of a code block line by line — the shape every
// `.code-block` region of the generated documentation relies on.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)

    var source: String = "<style>body { margin: 0; background: #ffffff }"
    source += ".code { margin: 12px; padding: 10px; background: #eef2f6; border: 1px solid #90a0b0; font-family: monospace; font-size: 14px; white-space: pre; color: #102030 }"
    source += "</style>"
    source += "<div class=\"code\">func demo()\n{\n    if ready\n        run(1)\n}</div>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(360, 220)
    view.applyLayout()
    view.rebuild()

    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.preserved-whitespace")
}

// The tables fixture renders through the production view, so a column-sizing or cell-alignment
// regression lands in this image before any reader sees it.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.tables.html"))
    view.resize(960, 680)
    view.applyLayout()
    view.rebuild()

    var steps: u64
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    Swag.assert(not view.isLoading())
    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.tables")
}

// The flex and grid fixture renders through the production view, pinning wrap, alignment, and
// track sizing as pixels rather than as a handful of sampled rectangles.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 540)

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.flex-grid.html"))
    view.resize(960, 540)
    view.applyLayout()
    view.rebuild()

    var steps: u64
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    Swag.assert(not view.isLoading())
    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.flex-grid")
}

// The classic article arrangement as pixels: a floated figure, the text wrapping beside it and
// returning to the full measure below, and a cleared footer starting under the float.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

    var source: String = "<html><head><style>body { margin: 0; background: #ffffff; color: #102030; font-size: 14px; height: 240px }"
    source += "p { margin: 6px }"
    source += ".fig { float: left; width: 110px; height: 70px; margin: 6px; background: #4a7fb5 }"
    source += ".end { clear: left; background: #dbe6f1 }"
    source += "</style></head><body>"
    source += "<div class=\"fig\"></div>"
    source += "<p>The paragraph wraps beside the floated figure and keeps every line inside the narrowed measure, then returns to the full column width once the flow has passed below the figure's bottom edge.</p>"
    source += "<p class=\"end\">A cleared footer starts below the float.</p>"
    source += "</body></html>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(360, 240)
    view.applyLayout()
    view.rebuild()

    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.floats")
}
