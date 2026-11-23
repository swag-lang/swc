#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Gui, Pixel, Win32

func captureChoice(app: *Application, choice: *Wnd)->Image
{
    // Let the hover animation finish and read the frame Windows actually composited.
    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 200 do
        app.runFrame()
    discard DwmFlush()

    let rect    = choice.surfaceRect()
    let surface = unwrap choice.surface
    var origin  = rect.topLeft()
    surface.surfaceToScreen(&origin)
    return expect getScreenRectImage(false, cast(s32, origin.x), cast(s32, origin.y),
                                     cast(s32, rect.width * surface.dpiScale), cast(s32, rect.height * surface.dpiScale))
}

func visiblyDiffers(rest, current: Image)->bool
{
    var changed = 0'u32
    for y in rest.height
    {
        for x in rest.width
        {
            let a = rest.pixelColor(cast(s32, x), cast(s32, y))
            let b = current.pixelColor(cast(s32, x), cast(s32, y))
            let red   = Math.abs(cast(s32, a.r) - b.r)
            let green = Math.abs(cast(s32, a.g) - b.g)
            let blue  = Math.abs(cast(s32, a.b) - b.b)
            if Math.max(red, Math.max(green, blue)) >= 8 do
                changed += 1
        }
    }

    return changed >= 20
}

// Move across the capture window's choices, then select a delay with the mouse.
#[Swag.TestTag("integration.capture.hub.hover")]
#test
{
    Swag.require(Env.hasArgument("swag.capture.native-screen=true"), "this integration requires actual desktop pixels")
    var journey: CaptureJourney
    journey.setup()
    journey.app.setAppearance(.Dark)
    journey.main.captureOptions.pictureDestination = .InPlace
    journey.main.captureOptions.delay = 0
    // Keep the window on the fixture's monitor regardless of where the desktop pointer starts.
    journey.main.hubBounds = journey.surface.position
    journey.main.showHub()
    let panel     = unwrap journey.main.residentPanel
    let menu      = panel.menu
    let choices   = unwrap panel.pictureChoices
    let clipboard = assume cast(*IconButton, choices.children[0])
    let annotate  = assume cast(*IconButton, choices.children[1])
    let delays    = assume cast(*StackLayoutCtrl, menu.children[1])
    let delay     = assume cast(*IconButton, delays.children[2])
    let surface   = unwrap panel.surface
    // Screen samples must come from this test window even when another app repaints behind it.
    surface.updateFlags(add: .TopMost)
    var input = Gui.Testing.DesktopInput.create(journey.app, surface)

    let row   = unwrap menu.items[1]
    let entry = menu.localToSurface(Math.Point{menu.position.width * 0.5, row.pos + row.size * 0.5})
    journey.waitFor("capture window accepts desktop input", func|surface, entry|()->bool
    {
        var screen = entry
        surface.surfaceToScreen(&screen)
        let hit = WindowFromPoint({cast(s32, screen.x), cast(s32, screen.y)})
        return hit and GetAncestor(hit, GA_ROOT) == surface.win32Handle()
    })
    input.moveTo(menu, entry)
    let clipboardRest = captureChoice(journey.app, clipboard)
    let annotateRest  = captureChoice(journey.app, annotate)
    let delayRest     = captureChoice(journey.app, delay)

    input.moveTo(clipboard, clipboard.surfaceRect().center())
    Swag.require(visiblyDiffers(clipboardRest, captureChoice(journey.app, clipboard)),
                 "the Clipboard button must visibly respond when the pointer enters from a menu row")

    input.moveTo(annotate, annotate.surfaceRect().center())
    Swag.require(visiblyDiffers(annotateRest, captureChoice(journey.app, annotate)),
                 "a selected button must visibly respond to the pointer")
    Swag.require(not visiblyDiffers(clipboardRest, captureChoice(journey.app, clipboard)))
    input.moveTo(delay, delay.surfaceRect().center())
    Swag.require(visiblyDiffers(delayRest, captureChoice(journey.app, delay)))
    Swag.require(not visiblyDiffers(annotateRest, captureChoice(journey.app, annotate)))
    input.moveTo(menu, entry)
    Swag.require(not visiblyDiffers(delayRest, captureChoice(journey.app, delay)))
    input.moveTo(delay, delay.surfaceRect().center())
    let delayHot = captureChoice(journey.app, delay)
    Swag.require(visiblyDiffers(delayRest, delayHot),
                 "the delay must respond again after leaving and reentering it")
    Swag.require(annotate.isChecked and not clipboard.isChecked and not delay.isChecked)

    input.click(delay)
    Swag.require(delay.isChecked and journey.main.captureOptions.delay == 3)
    let delaySelected = captureChoice(journey.app, delay)
    // Sample the fill between the glyph and the label, inside the selection outline.
    let x = delayHot.width / 2
    let y = delayHot.height / 2
    Swag.require(delayHot.pixelColor(x, y) == delaySelected.pixelColor(x, y),
                 "the hover and selected backgrounds must use the same tint")
}
