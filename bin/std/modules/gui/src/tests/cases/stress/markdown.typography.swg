#global if #command == Swag.CompilerCommand.Test
#global private
using Core

#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("markdown-margins-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 2_000 do
        source += Format.toString("## Section %\n\nA manuscript keeps its reading position after earlier sections retire.\n\n", index)
    discard expect File.writeAllText(fileName, source)
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    var style = Markdown.Style.theme()
    style.blockMargins      = {12, 18}
    style.headingTopSpacing = [40, 40, 40, 40, 40, 40]
    let view = Markdown.View.createFile(&host.root, fileName, style)
    view.resize(640, 480)
    view.applyLayout()
    for 80
    {
        view.scroll.setScrollPos(0, view.scroll.scrollPosition().y + 240)
        host.fireTimers()
    }

    view.retireDistantBlocks()
    Swag.assert(view.residentStart > 0)
    let first  = view.blocks[0].wnd.position
    let scroll = view.scroll.scrollPosition()
    view.layoutDocument(preservePosition: true)
    Swag.assert(view.blocks[0].wnd.position == first)
    Swag.assert(view.scroll.scrollPosition() == scroll)
}
