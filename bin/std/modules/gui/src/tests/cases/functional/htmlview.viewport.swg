#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// The HTML canvas reflows into the real viewport when the vertical bar reserves its gutter.
#test
{
    var source: String = "<html><body>"
    for index in 35 do
        source += Format.toString("<p>Paragraph %. A little air makes the chapter pleasant to read.</p>", index)
    source += "</body></html>"
    var host: Testing.HeadlessHost
    host.setup(560, 400)
    var style = HtmlStyle.theme()
    style.bodyFontSize = 18
    let view = HtmlView.createText(&host.root, source, style)
    view.resize(510, 191)
    view.applyLayout()
    Swag.require(view.scroll.needV and view.scroll.view.position.width < view.scroll.position.width)
    Swag.require(view.canvas.position.width == view.scroll.view.position.width,
                 Format.toString("canvas %; visible %", view.canvas.position.width, view.scroll.view.position.width))
    for box in view.layout.boxes do
        for item in box.items where item.visible and item.kind == .Text do
            Swag.require(item.x + item.width <= view.scroll.view.position.width + 0.6)
    view.resize(510, 5000)
    view.applyLayout()
    Swag.require(not view.scroll.needV and view.canvas.position.width == view.scroll.view.position.width)
    Swag.require(view.canvas.position.width == 510)
}
