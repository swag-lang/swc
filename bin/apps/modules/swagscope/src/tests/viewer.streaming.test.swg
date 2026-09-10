#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The text viewer starts replacing a resident window while several screens remain on
// both sides. Even withheld timers cannot expose a blank viewport during a continuous gesture.
#test
{
    let fileName = Testing.tempFilePath("scope-text-continuous-", ".txt")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("// Line % keeps the viewport covered during a resident transition.\n", index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var session  = openTestViewer(textViewerPlugin(), &host.root, fileName, commandParent: commands)
    let view     = cast(*TextView) session.view!
    view.resize(640, 360)
    view.applyLayout()
    discard host.render(view)
    view.updateEstimatedHeight()
    Swag.assert(view.revealOffset(source.length / 2, ""))
    discard host.render(view)
    view.updateEstimatedHeight()
    let viewport = view.editor.paddedClientRect()

    for forward in [true, false]
    {
        let start = view.residentOffsetY
        let end   = start + view.editor.loadedDocumentHeight()
        view.editor.setScrollPosition({0, forward ? end - viewport.height * 8 : start + viewport.height * 8})
        view.pendingSeek = false
        let previousStart = view.residentStart
        for 20 where not view.pendingSeek do
            view.editor.setScrollPosition({0, view.editor.scrollPosition().y + viewport.height * (forward ? 0.25 : -0.25)})
        Swag.assert(view.pendingSeek)
        Swag.assert(view.editor.scrollPosition().y >= start + viewport.height * 3)
        Swag.assert(view.editor.scrollPosition().y + viewport.height <= end - viewport.height * 3)

        // Continue without servicing the prefetch timer, through the previous resident edge.
        for 28
        {
            let residentBefore = view.residentStart
            view.editor.setScrollPosition({0, view.editor.scrollPosition().y + viewport.height * (forward ? 0.25 : -0.25)})
            if view.residentStart != residentBefore
            {
                discard host.render(view)
                view.updateEstimatedHeight()
            }

            Swag.assert(view.editor.scrollPosition().y >= view.residentOffsetY - 1, Format.toString("forward=%, position=%, origin=%, height=%", forward, view.editor.scrollPosition().y, view.residentOffsetY, view.editor.loadedDocumentHeight()).toString())
            Swag.assert(view.editor.scrollPosition().y + viewport.height <= view.residentOffsetY + view.editor.loadedDocumentHeight() + 1)
        }

        Swag.assert(view.residentStart != previousStart)
        Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)
    }

    // Thumb scrubbing coalesces before paint, but cannot wait for the streaming timer.
    for ratio in [0.85'f32, 0.15'f32, 0.65'f32]
    {
        view.editor.setScrollPosition({0, view.virtualHeight * (1 - ratio)})
        view.editor.setScrollPosition({0, view.virtualHeight * ratio})
        discard host.render(view)
        Swag.assert(not view.pendingSeek)
        Swag.assert(view.editor.scrollPosition().y >= view.residentOffsetY - 1)
        Swag.assert(view.editor.scrollPosition().y + viewport.height <= view.residentOffsetY + view.editor.loadedDocumentHeight() + 1)
        Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024)
    }
}

// The code viewer starts replacing a resident window while several screens remain on
// both sides. Even withheld timers cannot expose a blank viewport during a continuous gesture.
#test
{
    let fileName = Testing.tempFilePath("scope-code-continuous-", ".swg")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("// Line % keeps the viewport covered during a resident transition.\n", index)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = CodeViewer.create(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    discard host.render(view)
    view.updateEstimatedHeight()
    Swag.assert(view.revealOffset(source.length / 2, ""))
    discard host.render(view)
    view.updateEstimatedHeight()
    let viewport = view.editor.paddedClientRect()

    for forward in [true, false]
    {
        let start = view.residentOffsetY
        let end   = start + view.editor.loadedDocumentHeight()
        view.editor.setScrollPosition({0, forward ? end - viewport.height * 8 : start + viewport.height * 8})
        view.pendingSeek = false
        let previousStart = view.residentStart
        for 20 where not view.pendingSeek do
            view.editor.setScrollPosition({0, view.editor.scrollPosition().y + viewport.height * (forward ? 0.25 : -0.25)})
        Swag.assert(view.pendingSeek)
        Swag.assert(view.editor.scrollPosition().y >= start + viewport.height * 3)
        Swag.assert(view.editor.scrollPosition().y + viewport.height <= end - viewport.height * 3)

        // Continue without servicing the prefetch timer, through the previous resident edge.
        for 28
        {
            let residentBefore = view.residentStart
            view.editor.setScrollPosition({0, view.editor.scrollPosition().y + viewport.height * (forward ? 0.25 : -0.25)})
            if view.residentStart != residentBefore
            {
                discard host.render(view)
                view.updateEstimatedHeight()
            }

            Swag.assert(view.editor.scrollPosition().y >= view.residentOffsetY - 1, Format.toString("forward=%, position=%, origin=%, height=%", forward, view.editor.scrollPosition().y, view.residentOffsetY, view.editor.loadedDocumentHeight()).toString())
            Swag.assert(view.editor.scrollPosition().y + viewport.height <= view.residentOffsetY + view.editor.loadedDocumentHeight() + 1)
        }

        Swag.assert(view.residentStart != previousStart)
        Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)
    }

    for ratio in [0.85'f32, 0.15'f32, 0.65'f32]
    {
        view.editor.setScrollPosition({0, view.virtualHeight * (1 - ratio)})
        view.editor.setScrollPosition({0, view.virtualHeight * ratio})
        discard host.render(view)
        Swag.assert(not view.pendingSeek)
        Swag.assert(view.editor.scrollPosition().y >= view.residentOffsetY - 1)
        Swag.assert(view.editor.scrollPosition().y + viewport.height <= view.residentOffsetY + view.editor.loadedDocumentHeight() + 1)
        Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024)
    }
}
