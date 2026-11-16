#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Large pages with an implicit head retain their authored reading measure in every resident window.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("html-implicit-head-", ".html")
    defer discard catch File.delete(fileName)
    var source: String = "<!doctype html><html><meta charset='utf-8'><title>Reading</title>"
    source += "<style>body{font:18px/1.55 Georgia,serif;max-width:860px;margin:2rem auto;padding:0 1rem}img{max-width:100%;height:auto;display:block;margin:1rem auto}</style><body id='page'>"
    source += "<h1>A centered reading column</h1><img id='figure' width='1000' height='200'><h2>A section</h2>"
    while source.length < 2 * 1024 * 1024 + 1024 do
        source += "<p>A paragraph keeps the ordinary document larger than one resident window.</p>\n"
    source += "</body></html>"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(1280, 600)
    var style = HtmlStyle.theme()
    style.maxContentWidth = 680
    let view = HtmlView.createFile(&host.root, fileName, style)
    view.resize(1280, 600)
    view.applyLayout()
    Swag.require(view.virtualSource)

    let body   = view.layout.constBox(view.boxOfNode(view.elementById("page"))).content
    let figure = view.layout.constBox(view.boxOfNode(view.elementById("figure"))).content
    Swag.require(Math.abs(body.width - 860) < 1)
    Swag.require(Math.abs(body.center().x - view.scroll.view.clientRect().width * 0.5) < 1)
    Swag.require(figure.width <= body.width and figure.x >= body.x and figure.right() <= body.right())

    let revealed = view.revealFileOffset(source.length / 2, "")
    Swag.require(revealed)
    let middle = view.layout.constBox(view.boxOfNode(view.elementById("page"))).content
    Swag.require(Math.abs(middle.width - body.width) < 1 and Math.abs(middle.x - body.x) < 1)
}
