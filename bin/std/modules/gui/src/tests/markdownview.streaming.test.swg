#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A distant scrollbar jump must paint its destination without waiting for loading timers.
// Reversals before that paint belong to the latest request, and prefetch cannot move it later.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Testing.tempFilePath("markdown-scrollbar-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("## Section %\n\nVisible paragraph %.\n\n", index, index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()
    let viewport = view.scroll.paddedClientRect()

    for ratio, index in [0.8'f32, 0.2'f32, 0.9'f32, 0.4'f32]
    {
        view.scroll.setScrollPos(0, view.virtualHeight * (1 - ratio))
        let destination = view.virtualHeight * ratio
        let offset      = cast(u64) (ratio * cast(f32) source.length)
        view.scroll.setScrollPos(0, destination)
        var image = host.render(view)
        if not index do
            Pixel.Testing.assertImageGolden(&image, "markdownview.scrollbar")
        Swag.assert(not view.hasPendingTarget and view.retainedBlocks.isEmpty())
        Swag.assert(Math.abs(view.scroll.scrollPosition().y - destination) <= 1)
        Swag.assert(view.residentStart <= offset and offset - view.residentStart < 256)
        Swag.assert(view.scroll.scrollPosition().y >= view.virtualOrigin - 1)
        Swag.assert(view.scroll.scrollPosition().y + viewport.height <= view.contentHeight + 1)
        Swag.assert(view.blocks.count < 64)
        let position = view.scroll.scrollPosition()
        for 64 where view.isLoading() do
            host.fireTimers()
        Swag.assert(view.scroll.scrollPosition() == position)
        Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024)
    }

    // The bottom stop needs preceding blocks too, otherwise only the last paragraph appears
    // below an empty viewport. It must settle with the actual end visible.
    view.scroll.setScrollPos(0, view.scroll.scrollableClientRect().height)
    discard host.render(view)
    Swag.assert(not view.jumpToEnd and not view.hasPendingTarget and view.retainedBlocks.isEmpty())
    Swag.assert(not view.hasUnloadedSource())
    Swag.assert(view.scroll.scrollPosition().y >= view.virtualOrigin)
    Swag.assert(Math.abs(view.scroll.scrollPosition().y + viewport.height - view.contentHeight - view.documentStyle.bottomInset) <= 1)
}
