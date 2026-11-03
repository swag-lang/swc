#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A wheel notch immediately after a distant jump must not wait for background prefetch.
// Both directions keep a complete viewport and respond on the next paint.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("markdown-jump-wheel-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("## Section %\n\nVisible paragraph %.\n\n", index, index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
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
        Swag.require(not view.waitingScroll and not view.hasPendingTarget and view.retainedBlocks.isEmpty(), Format.toString("gesture=% waiting=% pending=% retained=%", index, view.waitingScroll, view.hasPendingTarget, view.retainedBlocks.count).toString())

        // A glide held at a resident boundary resumes after that paint, with its own endpoint.
        for 2
        {
            host.finishAnimations()
            discard host.render(view)
        }

        Swag.require(Math.abs(view.scroll.scrollPosition().y - position + delta * view.scroll.verticalScrollStep * 3) <= 1)
        Swag.require(view.scroll.scrollPosition().y >= view.virtualOrigin - 1)
        Swag.require(view.scroll.scrollPosition().y + viewport.height <= view.contentHeight + 1)
    }
}

// Reaching the streamed end replaces the block under a stationary pointer. The following wheel
// notch must resolve its new target without requiring an intervening mouse move.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("markdown-wheel-end-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 4_000 do
        source += Format.toString("Paragraph % gives the wheel a stable streaming destination.\n\n", index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    host.setReducedMotion(true)
    let view = Markdown.View.createFile(cast(*Wnd, &host.surfaceWnd), fileName)
    defer view.destroy()
    view.resize(720, 480)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()

    host.moveMouse({360, 240})
    Swag.require(host.app.mouseEnterWnd != null and host.app.mouseEnterWnd != view.scroll)
    view.scroll.setScrollPos(0, view.scroll.scrollableClientRect().height)
    discard host.render(view)
    for 1_024 where view.isLoading() do
        host.fireTimers()
    Swag.require(host.app.mouseEnterWnd == null)
    let end = view.scroll.scrollPosition().y
    Swag.require(end > 0)
    host.app.sendMouseWheelEvent(&host.surface, {360, 240}, 1)

    Swag.require(view.scroll.scrollPosition().y < end)
}

// Every document key uses the scrollbar's next-paint loading path, including reversals before
// the pending destination is painted. No loading timer is needed to expose a simple text page.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("markdown-navigation-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("## Section %\n\nVisible paragraph %.\n\n", index, index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
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
        Swag.require(not view.hasUnloadedSource() and not view.jumpToEnd and not view.hasPendingTarget)
        Swag.require(Math.abs(view.scroll.scrollPosition().y + viewport.height - view.contentHeight - view.documentStyle.bottomInset) <= 1)
        host.keyPress(.Home, modifiers)
        discard host.render(view)
        Swag.require(view.residentStart == 0 and view.scroll.scrollPosition().y == 0)
    }

    for key, index in [Input.Key.Down, .Up, .PageDown, .PageUp, .Space, .Space]
    {
        let before = view.scroll.scrollPosition().y
        host.keyPress(key, index == 5 ? .Shift : .None)
        discard host.render(view)
        let distance  = index < 2 ? line : page
        let direction = index % 2 == 0 ? 1 : -1
        Swag.require(Math.abs(view.scroll.scrollPosition().y - before - distance * direction) <= 1)
        Swag.require(not view.waitingScroll and not view.hasPendingTarget)
    }

    host.keyPress(.End)
    host.keyPress(.Home)
    discard host.render(view)
    for 64 where view.isLoading() do
        host.fireTimers()
    Swag.require(view.residentStart == 0 and view.scroll.scrollPosition().y == 0)
}
