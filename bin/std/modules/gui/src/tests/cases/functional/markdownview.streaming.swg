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
