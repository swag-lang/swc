#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The code viewer starts replacing a resident window while several screens remain on
// both sides. Even withheld timers cannot expose a blank viewport during a continuous gesture.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("scope-code-continuous-", ".swg")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("// Line % keeps the viewport covered during a resident transition.\n", index)
    discard expect File.writeAllBytes(fileName, source)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    with let view = Code.Panel.create(&host.root, fileName)
    {
        .resize(640, 360)
        .applyLayout()
    }

    discard host.render(view)
    view.updateEstimatedHeight()
    Swag.require(view.revealOffset(source.length / 2, ""))
    discard host.render(view)
    view.updateEstimatedHeight()
    let viewport = view.editor.paddedClientRect()

    for forward in [true, false]
    {
        let start = view.residentOffsetY
        let end   = start + view.editor.loadedDocumentHeight()
        view.editor.setScrollPosition(Math.Point{0, forward ? end - viewport.height * 8 : start + viewport.height * 8})
        view.pendingSeek = false
        let previousStart = view.residentStart
        for 20 where not view.pendingSeek do
            view.editor.setScrollPosition(Math.Point{0, view.editor.scrollPosition().y + viewport.height * (forward ? 0.25 : -0.25)})
        Swag.require(view.pendingSeek)
        Swag.require(view.editor.scrollPosition().y >= start + viewport.height * 3)
        Swag.require(view.editor.scrollPosition().y + viewport.height <= end - viewport.height * 3)

        // Continue without servicing the prefetch timer, through the previous resident edge.
        for 28
        {
            let residentBefore = view.residentStart
            view.editor.setScrollPosition(Math.Point{0, view.editor.scrollPosition().y + viewport.height * (forward ? 0.25 : -0.25)})
            if view.residentStart != residentBefore
            {
                discard host.render(view)
                view.updateEstimatedHeight()
            }

            Swag.require(view.editor.scrollPosition().y >= view.residentOffsetY - 1, Format.toString("forward=%, position=%, origin=%, height=%", forward, view.editor.scrollPosition().y, view.residentOffsetY, view.editor.loadedDocumentHeight()))
            Swag.require(view.editor.scrollPosition().y + viewport.height <= view.residentOffsetY + view.editor.loadedDocumentHeight() + 1)
        }

        Swag.require(view.residentStart != previousStart)
        Swag.require(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)
    }

    for ratio in [0.85'f32, 0.15'f32, 0.65'f32]
    {
        view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.45})
        view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * ratio})
        discard host.render(view)
        Swag.require(not view.pendingSeek)
        Swag.require(view.editor.scrollPosition().y >= view.residentOffsetY - 1)
        Swag.require(view.editor.scrollPosition().y + viewport.height <= view.residentOffsetY + view.editor.loadedDocumentHeight() + 1)
        Swag.require(view.bytesRead - view.residentStart <= 256 * 1024)
    }
}
