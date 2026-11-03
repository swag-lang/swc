#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A heading click owns its position, including during a wheel glide or reverse prefetch.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("outline-heading-scroll-", ".md")
    defer discard catch File.delete(fileName)
    var source:  String
    var offsets: Array'u64
    for index in 4_000
    {
        offsets.add(source.length)
        source += Format.toString("## Section %\n\nA paragraph to retain while the document scrolls.\n\n", index)
    }

    for 20 do
        source += "A closing paragraph after the last heading.\n\n"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))
    var host: Testing.HeadlessHost
    host.setup(720, 480)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()

    for index in [2_000'u64, 2_002, 500, 502, 3_999, 0]
    {
        host.setReducedMotion(false)
        host.mouseWheel({360, 240}, -1)
        let revealed = view.revealHeading(offsets[index])
        Swag.require(revealed)
        discard host.render(view)
        Swag.require(not view.hasPendingTarget and
                     not view.pendingSeek and
                     not view.waitingScroll and
                     view.retainedBlocks.isEmpty())
        var found: bool
        for block in view.blocks where block.sourceOffset == offsets[index]
        {
            found = true
            Swag.require(block.wnd.isVisible())
            Swag.require(Math.abs(block.wnd.surfaceRect().y - view.scroll.surfaceRect().y - view.documentStyle.topInset) <= 1)
        }

        Swag.require(found)
        Swag.require(view.readingOffset() == offsets[index])
        let position = view.scroll.scrollPosition()
        for 64 where view.isLoading() do
            host.fireTimers()
        host.finishAnimations()
        discard host.render(view)
        Swag.require(view.scroll.scrollPosition() == position)

        // Crossing the new resident boundary must move by the wheel distance, without a jump
        // when the preceding blocks replace the viewport. Returning keeps the same heading.
        host.setReducedMotion(true)
        let direction = index ? 1 : -1
        for delta in [direction, -direction]
        {
            let before = view.scroll.scrollPosition().y
            host.mouseWheel({360, 240}, delta)
            for 2
            {
                discard host.render(view)
                host.finishAnimations()
            }

            Swag.require(Math.abs(view.scroll.scrollPosition().y - before + delta * view.scroll.verticalScrollStep * 3) <= 1, Format.toString("section=% wheel=% before=% after=%", index, delta, before, view.scroll.scrollPosition().y).toString())
        }

        Swag.require(view.scroll.scrollPosition() == position)
    }

    // The byte-to-height estimate is deliberately different from the true first-page geometry.
    // A reverse overlap must still expose byte zero, with no gap or stalled wheel above it.
    let away = view.revealHeading(offsets[2_000])
    Swag.require(away)
    discard host.render(view)
    let nearStart = view.revealHeading(offsets[2])
    Swag.require(nearStart)
    discard host.render(view)
    Swag.require(view.blocks[0].sourceOffset == offsets[2])
    for 4
    {
        var before: f32
        for block in view.blocks where block.sourceOffset == offsets[2] do
            before = block.wnd.surfaceRect().y
        host.mouseWheel({360, 240}, 1)
        discard host.render(view)
        host.finishAnimations()
        for block in view.blocks where block.sourceOffset == offsets[2]
        {
            let distance = block.wnd.surfaceRect().y - before
            Swag.require(distance >= -1 and distance <= view.scroll.verticalScrollStep * 3 + 1)
        }
    }

    Swag.require(view.residentStart == 0 and
                 view.virtualOrigin == 0 and
                 view.scroll.scrollPosition().y == 0 and
                 not view.waitingScroll)
    Swag.require(view.blocks[0].sourceOffset == 0)
    Swag.require(Math.abs(view.blocks[0].wnd.surfaceRect().y - view.scroll.surfaceRect().y - view.documentStyle.topInset) <= 1)
}
