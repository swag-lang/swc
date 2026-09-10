#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A wheel notch immediately after a distant jump must not wait for background prefetch.
// Both directions keep a complete viewport and respond on the next paint.
#test
{
    let fileName = Testing.tempFilePath("markdown-jump-wheel-", ".md")
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

    for delta, index in [1, -1, 1, -1, 1, -1, 1, -1]
    {
        host.setReducedMotion(index % 4 < 2)
        view.scroll.setScrollPos(0, view.virtualHeight * (index % 2 == 0 ? 0.7 : 0.3))
        if index < 4 do
            discard host.render(view)
        let position = view.scroll.scrollPosition().y
        host.mouseWheel({360, 240}, delta)
        if index % 4 >= 2 do
            host.advanceAnimations(0.04)
        discard host.render(view)
        Swag.assert(not view.waitingScroll and not view.hasPendingTarget and view.retainedBlocks.isEmpty(), Format.toString("gesture=% waiting=% pending=% retained=%", index, view.waitingScroll, view.hasPendingTarget, view.retainedBlocks.count).toString())

        // A glide held at a resident boundary resumes after that paint, with its own endpoint.
        for 2
        {
            host.finishAnimations()
            discard host.render(view)
        }

        Swag.assert(Math.abs(view.scroll.scrollPosition().y - position + delta * view.scroll.verticalScrollStep * 3) <= 1)
        Swag.assert(view.scroll.scrollPosition().y >= view.virtualOrigin - 1)
        Swag.assert(view.scroll.scrollPosition().y + viewport.height <= view.contentHeight + 1)
    }
}

// Reading a short file in one chunk does not mean that all its blocks have been laid out.
// End must reach its last block even when only the first background batch is ready.
#test
{
    let fileName = Testing.tempFilePath("markdown-short-end-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 40 do
        source += Format.toString("Paragraph %.\n\n", index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    view.setFocus()
    host.fireTimer(view.loadTimer)
    Swag.assert(view.bytesRead == view.fileSize and view.hasUnloadedSource())
    host.keyPress(.End)
    discard host.render(view)
    Swag.assert(not view.hasUnloadedSource() and not view.jumpToEnd and not view.hasPendingTarget)
    Swag.assert(view.blocks.backPtr().searchText.toString() == "Paragraph 39.")
    Swag.assert(Math.abs(view.scroll.scrollPosition().y + view.scroll.paddedClientRect().height - view.contentHeight - view.documentStyle.bottomInset) <= 1)
}

// Every document key uses the scrollbar's next-paint loading path, including reversals before
// the pending destination is painted. No loading timer is needed to expose a simple text page.
#test
{
    let fileName = Testing.tempFilePath("markdown-navigation-", ".md")
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
    view.setFocus()
    for 64 where view.isLoading() do
        host.fireTimers()
    let viewport = view.scroll.paddedClientRect()
    let line     = view.scroll.verticalScrollStep
    let page     = Math.max(viewport.height - line, line)

    for modifiers in [Input.KeyModifiers.None, Input.KeyModifiers.Control]
    {
        host.keyPress(.End, modifiers)
        discard host.render(view)
        Swag.assert(not view.hasUnloadedSource() and not view.jumpToEnd and not view.hasPendingTarget)
        Swag.assert(Math.abs(view.scroll.scrollPosition().y + viewport.height - view.contentHeight - view.documentStyle.bottomInset) <= 1)
        host.keyPress(.Home, modifiers)
        discard host.render(view)
        Swag.assert(view.residentStart == 0 and view.scroll.scrollPosition().y == 0)
    }

    for key, index in [Input.Key.Down, .Up, .PageDown, .PageUp, .Space, .Space]
    {
        let before = view.scroll.scrollPosition().y
        host.keyPress(key, index == 5 ? .Shift : .None)
        discard host.render(view)
        let distance  = index < 2 ? line : page
        let direction = index % 2 == 0 ? 1 : -1
        Swag.assert(Math.abs(view.scroll.scrollPosition().y - before - distance * direction) <= 1)
        Swag.assert(not view.waitingScroll and not view.hasPendingTarget)
    }

    host.keyPress(.End)
    host.keyPress(.Home)
    discard host.render(view)
    for 64 where view.isLoading() do
        host.fireTimers()
    Swag.assert(view.residentStart == 0 and view.scroll.scrollPosition().y == 0)
}

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
