#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Reading a short file in one chunk does not mean that all its blocks have been laid out.
// End must reach its last block even when only the first background batch is ready.
#test
{
    let fileName = Testing.tempFilePath("markdown-short-end-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 40 do
        source += Format.toString("Paragraph %.\n\n", index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    view.setFocus()
    host.fireTimer(view.loadTimer)
    Swag.require(view.bytesRead == view.fileSize and view.hasUnloadedSource())
    host.keyPress(.End)
    discard host.render(view)
    Swag.require(not view.hasUnloadedSource() and not view.jumpToEnd and not view.hasPendingTarget)
    Swag.require(view.blocks.backPtr().searchText.toString() == "Paragraph 39.")
    Swag.require(Math.abs(view.scroll.scrollPosition().y + view.scroll.paddedClientRect().height - view.contentHeight - view.documentStyle.bottomInset) <= 1)
}

// A paragraph longer than the source carry remains one paragraph across file-read chunks.
#test
{
    let fileName = Testing.tempFilePath("markdown-long-paragraph-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 220
    {
        source += Format.toString("continuation line %. has enough words to cross the carry limit safely\n", index)
    }

    source += "\nAfter the long paragraph."
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    view.jumpToEnd = true
    for 128 where view.hasUnloadedSource() do
        view.streamStep()

    Swag.require(not view.hasUnloadedSource() and view.blocks.count == 2)
    Swag.require(view.blocks[0].kind == .Paragraph)
    Swag.require(view.blocks[0].inline!.text().toString() == Markdown.parseBlocks(source.toString())[0].text.toString())
    Swag.require(view.blocks[1].searchText.toString() == "After the long paragraph.")
}

// A fence longer than the source carry keeps its closing fence and all code in one block.
#test
{
    let fileName = Testing.tempFilePath("markdown-long-fence-", ".md")
    defer discard catch File.delete(fileName)
    var source = String.from("```swg\n")
    for index in 220 do
        source += Format.toString("let value_% = %\n", index, index)
    source += "```\n\nAfter the fence."
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    view.jumpToEnd = true
    for 128 where view.hasUnloadedSource() do
        view.streamStep()

    Swag.require(not view.hasUnloadedSource() and view.blocks.count == 2)
    Swag.require(view.blocks[0].kind == .Code)
    Swag.require(Utf8.contains(view.blocks[0].searchText.toString(), "let value_219 = 219"))
    Swag.require(view.blocks[1].searchText.toString() == "After the fence.")
}
