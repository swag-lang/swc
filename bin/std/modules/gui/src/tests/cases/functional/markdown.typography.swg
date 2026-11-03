#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Explicit line boxes and collapsing margins keep the same geometry after append and reflow.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    var style = Markdown.Style.theme()
    style.blockMargins         = {12, 18}
    style.bodyLineHeight       = 28
    style.headingLineHeights   = [48, 36, 30, 26, 24, 24]
    style.headingTopSpacing    = [40, 40, 40, 40, 40, 40]
    style.headingBottomSpacing = [16, 16, 16, 16, 16, 16]
    let view = Markdown.View.createText(&host.root, "First line.\n\nSecond line.\n\n## A heading\n\nAfter the heading.", style)
    view.resize(640, 480)
    view.applyLayout()
    Swag.require(view.blocks.count == 4)
    let first   = view.blocks[0].wnd.position
    let second  = view.blocks[1].wnd.position
    let heading = view.blocks[2].wnd.position
    let last    = view.blocks[3].wnd.position
    Swag.require(first.y == style.topInset + 12 and first.height == 28)
    Swag.require(second.y - first.bottom() == 18)
    Swag.require(heading.y - second.bottom() == 40 and heading.height == 36)
    Swag.require(last.y - heading.bottom() == 16)
    view.layoutDocument()
    Swag.require(view.blocks[3].wnd.position == last)
    Swag.require(view.scroll.verticalScrollStep == 28)

    // Taller glyphs still fit a deliberately undersized line box.
    style.bodyLineHeight = 1
    view.setDocumentStyle(style)
    for atom in view.blocks[0].inline!.atoms where atom.visible do
        Swag.require(atom.position.bottom() <= view.blocks[0].inline!.layoutHeight)
}
