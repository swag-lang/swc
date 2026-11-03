#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("markdown-continuous-scroll-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 8_000 do
        source += Format.toString("## Section %\n\nA paragraph gives each source block a stable identity during scrolling.\n\n", index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()
    let viewport = view.scroll.paddedClientRect()
    Swag.assert(view.contentHeight >= viewport.height * 6)

    // Withhold every loading timer while enough wheel-sized steps exhaust the reserve.
    for 80
    {
        view.scroll.setScrollPos(0, view.scroll.scrollPosition().y + viewport.height / 4)
        Swag.assert(view.scroll.scrollPosition().y + viewport.height <= view.contentHeight + 1)
    }

    Swag.assert(view.waitingScroll and view.isLoading())
    host.setReducedMotion(true)
    host.mouseWheel({360, 240}, -100)
    Swag.assert(view.scroll.scrollPosition().y + viewport.height <= view.contentHeight + 1)
    host.setReducedMotion(false)
    let held = view.scroll.scrollPosition().y
    for 64 where view.isLoading() do
        host.fireTimers()
    host.settleAnimations(view, 12)
    Swag.assert(not view.waitingScroll and view.scroll.scrollPosition().y > held)

    Swag.assert(view.revealFileOffset(source.length / 2, ""))
    for 1_024 where view.hasPendingTarget do
        host.fireTimers()
    Swag.assert(not view.hasPendingTarget and view.retainedBlocks.isEmpty())
    view.scroll.setScrollPos(0, view.virtualOrigin + viewport.height * 7)
    for 8 where not view.pendingSeek do
        view.scroll.setScrollPos(0, view.scroll.scrollPosition().y - viewport.height / 4)
    Swag.assert(view.pendingSeek and view.pendingSeekPreservesPosition)
    host.fireTimer(view.loadTimer)
    Swag.assert(not view.retainedBlocks.isEmpty())
    view.beginSelection(unwrap view.retainedBlocks[0].inline, 0)
    view.selectAll()
    Swag.assert(not view.isSelecting() and not view.hasSelection())
    let anchorOffset = view.replacementAnchorOffset
    let anchorY      = view.replacementAnchorY
    for 1_024 where not view.retainedBlocks.isEmpty()
    {
        Swag.assert(view.retainedBlocks[0].wnd.isVisible())
        Swag.assert(view.scroll.scrollPosition().y >= view.retainedOrigin)
        Swag.assert(view.scroll.scrollPosition().y + viewport.height <= view.retainedHeight + 1)
        host.fireTimer(view.loadTimer)
    }

    Swag.assert(view.retainedBlocks.isEmpty())
    var matched: bool
    for block in view.blocks where block.sourceOffset == anchorOffset
    {
        Swag.assert(Math.abs(block.wnd.position.y - anchorY) <= 1)
        Swag.assert(block.wnd.isVisible())
        matched = true
    }

    Swag.assert(matched)

    // A context window that reaches byte zero must retain the beginning. Dropping its first
    // chunk makes a reverse prefetch repeatedly reopen the same window without reaching Home.
    Swag.assert(view.revealFileOffset(12 * 1024, ""))
    Swag.assert(view.residentStart == 0)
    for 1_024 where view.isLoading() do
        host.fireTimers()
    for 80 do
        view.scroll.setScrollPos(0, view.scroll.scrollPosition().y + viewport.height / 4)
    Swag.assert(view.waitingScroll)

    // A search supersedes a wheel gesture held at the loading boundary. Once its match is
    // visible, an old waiting destination must not pull the reader away from that match.
    let found = view.revealFileOffset(source.indexOf("Section 2"), "Section 2")
    Swag.assert(found)
    for 1_024 where view.isLoading() do
        host.fireTimers()
    host.finishAnimations()
    var searchRect: Math.Rectangle
    let hasSearchRect = view.searchMatchRect(&searchRect)
    Swag.assert(hasSearchRect and not view.waitingScroll)
    Swag.assert(searchRect.y >= 0 and searchRect.bottom() <= viewport.height)
}
#[Swag.TestTag("stress")]
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("gui_markdown_resident_cap_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 16_000 do
        source += Format.toString("## Bounded section %\n\nA paragraph is evicted after the resident source budget.\n\n", index)
    Swag.assert(source.length > 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 360)
    view.applyLayout()

    let viewport = view.scroll.paddedClientRect()
    for 64 where view.isLoading() do
        host.fireTimer(view.loadTimer)
    for 512
    {
        let previous = view.scroll.scrollPosition().y
        view.scroll.setScrollPos(0, previous + viewport.height / 4)
        if view.loadTimer do
            host.fireTimer(view.loadTimer)
        Swag.assert(view.scroll.scrollPosition().y >= previous)
        Swag.assert(view.scroll.scrollPosition().y + viewport.height <= view.contentHeight + 1)
        Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 8 * 1024)
        Swag.assert(view.blocks.count < 256)
    }

    Swag.assert(view.residentStart > 0)
    Swag.assert(view.hasUnloadedSource())
    let anchor  = view.blocks.back().wnd
    let anchorY = anchor.position.y
    view.retireDistantBlocks()
    Swag.assert(anchor.position.y == anchorY)

    let firstStart = view.residentStart
    view.scroll.setScrollPos(0, view.virtualHeight * 0.75)
    Swag.assert(view.pendingSeek)
    host.fireTimers()
    Swag.assert(view.residentStart > firstStart)
    Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 8 * 1024)
    Swag.assert(view.blocks.count < 10_000)
}
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_markdown_stream_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 40_000 do
        source += "## Streamed heading\n\nA paragraph stays on disk until navigation requests it.\n\n"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    let view = Markdown.View.createFile(&host.root, fileName)
    Swag.assert(view.loadTimer != null)
    view.resize(720, 360)
    view.applyLayout()
    host.fireTimer(view.loadTimer)

    Swag.assert(view.hasUnloadedSource())
    Swag.assert(view.loadedDocumentHeight() > view.documentStyle.topInset)
    view.setInitialFocus(view)
    Swag.assert(view.hasFocus())
    let expectedLine = view.theme().createDefaultFont(view.documentStyle.bodyFontSize).height * view.documentStyle.lineHeight
    Swag.assert(view.scroll.verticalScrollStep == expectedLine)
    host.keyPress(Input.Key.Down)
    discard host.render(view)
    Swag.assert(not view.hasPendingTarget and not view.waitingScroll)
    Swag.assert(Math.abs(view.scroll.scrollPosition().y - expectedLine) <= 1)
    host.keyPress(Input.Key.Up)
    Swag.assert(view.scroll.scrollPosition().y == 0)
    host.keyPress(Input.Key.PageDown)
    discard host.render(view)
    Swag.assert(not view.hasPendingTarget and not view.waitingScroll)
    let pagePosition = view.scroll.scrollPosition().y
    Swag.assert(pagePosition > expectedLine)
    host.keyPress(Input.Key.PageUp)
    Swag.assert(view.scroll.scrollPosition().y == 0)

    let before = view.scroll.scrollPosition()
    host.keyPress(Input.Key.End)
    discard host.render(view)
    Swag.assert(not view.hasUnloadedSource())
    Swag.assert(not view.jumpToEnd)
    Swag.assert(view.scroll.scrollPosition().y > before.y)
    host.keyPress(Input.Key.Home)
    discard host.render(view)
    Swag.assert(view.residentStart == 0)
    Swag.assert(view.scroll.scrollPosition().y == 0)
}
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_markdown_reverse_stream_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 16_000 do
        source += Format.toString("## Section %\n\nThe resident window keeps useful context on both sides.\n\n", index)
    const RevealContextSize = 64 * 1024'u64
    Swag.assert(source.length > RevealContextSize * 8)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 360)
    view.applyLayout()

    // The ordinary first resident blocks establish the document's byte-to-height estimate before
    // the reader asks for the end, exactly as the visible application does.
    host.fireTimer(view.loadTimer)
    Swag.assert(view.virtualHeight > view.scroll.paddedClientRect().height)

    let requested = source.length - 1
    let revealed  = view.revealFileOffset(requested, "")
    Swag.assert(revealed)
    var steps = 0'u32
    while view.hasPendingTarget and steps < 512
    {
        host.fireTimers()
        steps += 1
    }

    Swag.assert(not view.hasPendingTarget and not view.blocks.isEmpty())
    Swag.assert(view.scroll.scrollPosition().y - view.virtualOrigin >= view.scroll.paddedClientRect().height * 6)
    let firstResidentStart = view.residentStart
    let viewport = view.scroll.paddedClientRect()
    let nearResidentStart  = view.virtualOrigin + viewport.height * 0.5
    view.scroll.setScrollPos(0, nearResidentStart)

    // The old resident content still covers the viewport when the reverse seek is requested.
    Swag.assert(view.pendingSeek)
    Swag.assert(view.scroll.scrollPosition().y + viewport.height > view.virtualOrigin)
    host.fireTimers()

    steps = 0
    while view.hasPendingTarget and steps < 512
    {
        host.fireTimers()
        steps += 1
    }

    Swag.assert(not view.hasPendingTarget and view.residentStart < firstResidentStart)
    let position = view.scroll.scrollPosition().y
    var visibleBlock: bool
    for &block in view.blocks
    {
        if block.wnd.position.bottom() > position and block.wnd.position.y < position + viewport.height do
            visibleBlock = true
    }

    Swag.assert(visibleBlock)
}
#[Swag.TestTag("stress")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_markdown_seek_reversal_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 16_000 do
        source += Format.toString("## Direction %\n\nA distinct paragraph makes every resident window observable.\n\n", index)
    Swag.assert(source.length > 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 360)
    view.applyLayout()
    host.fireTimer(view.loadTimer)

    // A seek abandoned before its timer fires cannot displace the resident first window later.
    view.scroll.setScrollPos(0, view.virtualHeight * 0.8)
    Swag.assert(view.pendingSeek)
    view.scroll.setScrollPos(0, 0)
    Swag.assert(not view.pendingSeek)

    let high = view.virtualHeight * 0.8

    // A tall viewport requires several bounded preparation turns even with viewport priority.
    view.resize(720, 4_800)
    view.applyLayout()
    view.scroll.setScrollPos(0, high)
    Swag.assert(view.pendingSeek and view.loadTimer != null)
    let staleOffset = view.pendingSeekOffset
    host.fireTimer(view.loadTimer)
    Swag.assert(view.hasPendingTarget)

    // Reverse before the high target has finished producing blocks. This is a real scrollbar
    // gesture, not a direct reveal call, and must replace the outstanding target immediately.
    let low = view.scroll.scrollableClientRect().height * 0.2
    view.scroll.setScrollPos(0, low)
    Swag.assert(view.pendingSeek)
    Swag.assert(view.pendingSeekOffset < staleOffset / 2)
    host.fireTimer(view.loadTimer)
    Swag.assert(view.hasPendingTarget)
    Swag.assert(view.residentStart < staleOffset / 2)
    Swag.assert(Math.abs(view.pendingTarget - low) <= 1, Format.toString("pending=%, requested=%, position=%", view.pendingTarget, low, view.scroll.scrollPosition().y).toString())

    var steps = 0'u32
    while view.hasPendingTarget and steps < 1_024
    {
        host.fireTimers()
        steps += 1
    }

    Swag.assert(not view.hasPendingTarget)
    Swag.assert(view.residentStart < staleOffset / 2)
    Swag.assert(Math.abs(view.scroll.scrollPosition().y - low) <= 1, Format.toString("position=%, target=%", view.scroll.scrollPosition().y, low).toString())
}
