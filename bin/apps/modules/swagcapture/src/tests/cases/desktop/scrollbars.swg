#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// The two capture collections scroll through native pointer input in their reserved gutters.
// This checks real window hit testing, including the edge beside the resize border.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    for index in 15
    {
        discard index
        discard journey.newCapture()
    }

    let main = journey.main
    main.showRecentBar(true)
    var input = Testing.DesktopInput.create(journey.app, journey.surface)
    let recent = main.recentWnd
    journey.waitFor("recent strip overflow", func|recent|()->bool => recent.scrollSize.x > recent.view.position.width)
    Swag.require(recent.view.position.bottom() < recent.position.height)
    let recentMetrics = recent.themeMetrics()
    let recentY = recent.position.height - recentMetrics.scrollBar_EdgeInset - recentMetrics.scrollBar_HitSize * 0.5
    let recentFrom = recent.localToSurface(Math.Point{recent.view.position.width * 0.45, recentY})
    let recentTo = recent.localToSurface(Math.Point{recent.view.position.width * 0.8, recentY})
    input.drag(recent, recentFrom, recentTo)
    Swag.require(recent.scrollPosition().x > 0, "the native recent-strip scrollbar did not scroll")

    journey.openLibrary(15)
    main.libWnd.setPreviewSize(.Big)
    journey.waitFor("library overflow", func|main|()->bool => main.libWnd.captureHost.scrollSize.y > main.libWnd.captureHost.view.position.height)
    let scroll = main.libWnd.captureHost
    Swag.require(scroll.view.position.right() < scroll.position.width)
    let metrics = scroll.themeMetrics()
    let x = scroll.position.width - metrics.scrollBar_EdgeInset - metrics.scrollBar_HitSize * 0.5
    let first = scroll.localToSurface(Math.Point{x, scroll.view.position.height * 0.4})
    let last = scroll.localToSurface(Math.Point{x, scroll.view.position.height * 0.75})
    input.drag(scroll, first, last)
    Swag.require(scroll.scrollPosition().y > 0, "the native library scrollbar did not scroll")
}

// The shape inspector must accept a drag in its gutter on a compact native window.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    discard journey.newCapture(400, 300)
    journey.surface.setPosition({40, 40, 1100, 580})
    var input = Testing.DesktopInput.create(journey.app, journey.surface)
    input.shortcut(.R, .None)
    let main = journey.main
    journey.waitFor("shape inspector", func|main|()->bool => main.editMode == .Shape)

    let scroll = main.propWnd.grid.scrollWnd
    Swag.require(scroll.scrollSize.y > scroll.view.position.height, "the compact shape inspector did not overflow")
    Swag.require(scroll.surfaceRect().right() <= main.propWnd.surfaceRect().right())
    let metrics = scroll.themeMetrics()
    let x = scroll.position.width - metrics.scrollBar_EdgeInset - metrics.scrollBar_HitSize * 0.5
    let first = scroll.localToSurface(Math.Point{x, scroll.view.position.height * 0.45})
    let last = scroll.localToSurface(Math.Point{x, scroll.view.position.height * 0.75})
    input.drag(scroll, first, last)
    Swag.require(scroll.scrollPosition().y > 0, "the native shape inspector scrollbar did not scroll")
}
