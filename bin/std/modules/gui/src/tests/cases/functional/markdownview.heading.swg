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

    Swag.require(view.revealHeading(closingOffset))
    for 1_024 where view.isLoading() do
        host.fireTimers()
    discard host.render(view)

    let viewport = view.scroll.paddedClientRect()
    let position = view.scroll.scrollPosition().y
    let end      = view.contentHeight + view.documentStyle.bottomInset - viewport.height
    Swag.require(not view.hasUnloadedSource() and view.retainedBlocks.isEmpty())
    Swag.require(Math.abs(position - end) <= 1, Format.toString("position=%, end=%, origin=%, height=%", position, end, view.virtualOrigin, view.virtualHeight).toString())
    Swag.require(view.blocks[0].wnd.position.y - position <= view.documentStyle.topInset + 1,
                 Format.toString("first=%, position=%, inset=%", view.blocks[0].wnd.position.y, position, view.documentStyle.topInset).toString())
}

// A reading offset is a place to return to: the block it names comes back to the top reading
// inset, whether it is still laid out or far outside the resident window, and whatever its kind.
#test
{
    let fileName = Testing.tempFilePath("markdown-reveal-block-", ".md")
    defer discard catch File.delete(fileName)
    var source: String = "# Opening\n\n"
    for index in 12 do
        source += Format.toString("Near paragraph %, long enough to take a line of the reading column.\n\n", index)
    let nearOffset = source.length
    source += "The near paragraph the reader stopped on.\n\n"
    for index in 1200 do
        source += Format.toString("Filler paragraph %, with enough text to fill the reading column.\n\n", index)
    let farOffset = source.length
    source += "The far paragraph the reader stopped on.\n\n"
    for 40 do
        source += "A paragraph after the far place.\n\n"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()
    discard host.render(view)

    // A paragraph still laid out is scrolled to, exactly as a heading is.
    Swag.require(view.revealBlock(nearOffset))
    discard host.render(view)
    Swag.require(view.readingOffset() == nearOffset)

    Swag.require(view.revealBlock(farOffset))
    discard host.render(view)
    Swag.require(view.readingOffset() == farOffset)
    Swag.require(view.blocks.count < 64, "a block jump prepares its viewport, not the preceding document")
    for 256 where view.isLoading() do
        host.fireTimers()
    Swag.require(view.readingOffset() == farOffset)

    Swag.require(view.revealBlock(nearOffset))
    for 256 where view.isLoading() do
        host.fireTimers()
    discard host.render(view)
    Swag.require(view.readingOffset() == nearOffset)
    Swag.require(not view.revealBlock(source.length + 10))
}

// An in-memory document has no file to read from another boundary: a block reveal lands on a
// laid-out block of any kind and refuses an offset that starts none.
#test
{
    var source: String = "# Title\n\n"
    for 30 do
        source += "A paragraph that gives the document some height.\n\n"
    let offset = source.length
    source += "The paragraph to return to.\n\n"
    for 30 do
        source += "A paragraph after it.\n\n"

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(640, 360)
    view.applyLayout()
    for 256 where view.isLoading() do
        host.fireTimers()
    discard host.render(view)

    Swag.require(view.revealBlock(offset) and view.readingOffset() == offset)
    Swag.require(not view.revealHeading(offset))
    Swag.require(not view.revealBlock(offset + 3))
}
