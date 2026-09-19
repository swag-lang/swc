#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An estimated long range is not permission to scroll beyond an unfinished first viewport.
#test
{
    let fileName = Testing.tempFilePath("markdown-first-viewport-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for 512 do
        source += "A short paragraph is followed by more source.\n\n"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 1000)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 1000)
    view.applyLayout()
    host.fireTimer(view.loadTimer)
    Swag.assert(not view.blocks.isEmpty() and view.loadedDocumentHeight() < 1000)
    host.mouseWheel({360, 240}, -1)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y == 0 and view.waitingScroll)
    for 64 where view.waitingScroll do
        host.fireTimer(view.loadTimer)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y > 0 and not view.waitingScroll)
}

// Wheel input before the first streaming tick must survive the initially empty scroll extent.
#test
{
    let fileName = Testing.tempFilePath("markdown-initial-wheel-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for 512 do
        source += "A paragraph remains available while the rest of this large document is loading.\n\n"
    discard expect File.writeAllText(fileName, source)

    for reduced in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(720, 1000)
        defer host.shutdown()
        host.setReducedMotion(reduced)
        let view = Markdown.View.createFile(&host.root, fileName)
        view.resize(720, 1000)
        view.applyLayout()
        Swag.assert(view.blocks.isEmpty() and view.isLoading())

        let step = view.scroll.verticalScrollStep * 3
        for 3 do
            host.mouseWheel({360, 240}, -1)
        Swag.assert(view.scroll.scrollPosition().y == 0)

        // Do not wait for the prefetch reserve to finish before expecting the first movement.
        for 64 where view.scroll.scrollTarget().y == 0 and view.isLoading() do
            host.fireTimer(view.loadTimer)
        host.finishAnimations()
        Swag.assert(Math.abs(view.scroll.scrollPosition().y - step * 3) <= 1)
        Swag.assert(view.hasUnloadedSource())
    }
}

// Reversing before the first chunk arrives cancels the queued downward gesture.
#test
{
    let fileName = Testing.tempFilePath("markdown-initial-reverse-", ".md")
    defer discard catch File.delete(fileName)
    var source: String
    for 256 do
        source += "A paragraph keeps a pending wheel gesture separate from the loading extent.\n\n"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    host.mouseWheel({360, 240}, -2)
    host.mouseWheel({360, 240}, 1)
    for 64 where view.isLoading() do
        host.fireTimer(view.loadTimer)
    host.finishAnimations()
    Swag.assert(view.scroll.scrollPosition().y == 0 and not view.waitingScroll)
    host.mouseWheel({360, 240}, -1)
    host.finishAnimations()
    Swag.assert(Math.abs(view.scroll.scrollPosition().y - view.scroll.verticalScrollStep * 3) <= 1)
}
