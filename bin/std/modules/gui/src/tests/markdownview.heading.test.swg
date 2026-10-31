#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A short final section reached from the outline settles at the document end immediately.
#test
{
    let fileName = Testing.tempFilePath("markdown-final-heading-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 160 do
        source += Format.toString("## Section %\n\nA long paragraph keeps the reader far from the final section. This sentence repeats its content so the initial viewport cannot contain the closing heading.\n\n", index)
    let closingOffset = source.length
    source += "## Closing\n\nDone.\n"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()

    Swag.assert(view.revealHeading(closingOffset))
    for 1_024 where view.isLoading() do
        host.fireTimers()
    discard host.render(view)

    let viewport = view.scroll.paddedClientRect()
    let position = view.scroll.scrollPosition().y
    let end      = view.contentHeight + view.documentStyle.bottomInset - viewport.height
    Swag.assert(not view.hasUnloadedSource() and view.retainedBlocks.isEmpty())
    Swag.assert(Math.abs(position - end) <= 1, Format.toString("position=%, end=%, origin=%, height=%", position, end, view.virtualOrigin, view.virtualHeight).toString())
    Swag.assert(view.blocks[0].wnd.position.y - position <= view.documentStyle.topInset + 1,
                Format.toString("first=%, position=%, inset=%", view.blocks[0].wnd.position.y, position, view.documentStyle.topInset).toString())
}
