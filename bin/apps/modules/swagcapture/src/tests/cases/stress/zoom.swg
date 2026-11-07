#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Exercises zoom over large shadowed annotations at a desktop-sized viewport.
// An optional SCC path lets the same sequence profile a reported slow capture.
#[Swag.TestTag("stress")]
#test
{
    var f: HeadlessFixture
    f.setup(3200, 2600)
    defer f.shutdown()

    let source = Env.variable("SWAG_CAPTURE_STRESS_FILE")
    if not source.isEmpty()
    {
        let capture = expect Capture.load(source)
        f.editView.setCapture(capture)
        f.capture = capture
    }
    else
    {
        f.capture.width, f.capture.widthOrg   = 2146
        f.capture.height, f.capture.heightOrg = 2019
        f.capture.backImg = Image.create(2332, 1875, .BGRA8)
        f.capture.backImg.fill(Argb.White)

        var points: Array'Math.Vector2
        points.add({410, -221})
        points.add({2487, -221})
        points.add({2487, 2057})
        points.add({410, 2057})
        let first = testAddPolygon(f.capture, points.toSlice())
        first.borderSize = 23
        first.paintShadow = true

        points.clear()
        points.add({-176, -117})
        points.add({1881, -117})
        points.add({1881, 2084})
        points.add({-176, 2084})
        let second = testAddPolygon(f.capture, points.toSlice())
        second.borderSize = 23
        second.paintShadow = true
    }

    discard f.gui.render(f.main)
    f.editView.setZoom(0.56)
    f.gui.fireTimer(f.editView.zoomTimer)
    var watch: Time.Stopwatch
    watch.start()
    discard f.gui.render(f.main)
    Console.print("zoom initial: ", watch.elapsedMilliseconds(), " ms\n")
    Swag.require(f.capture.formCaches.count >= 2)
    for i in 0 until 2
    {
        let shadow = &f.capture.formCaches[i]!.shadow
        Swag.require(shadow.contentTarget != null and shadow.shadowTarget == null)
        Swag.require(shadow.contentTarget.colorBuffer.width <= MaxFormShadowDim and
                     shadow.contentTarget.colorBuffer.height <= MaxFormShadowDim)
    }
    let firstShadow = f.capture.formCaches[0]!.shadow.contentTarget!.colorBuffer.handle
    let secondShadow = f.capture.formCaches[1]!.shadow.contentTarget!.colorBuffer.handle
    f.gui.moveMouse({1600, 1300})

    for zoom in [0.66'f32, 0.86, 1.0, 1.5, 2.0, 3.0, 4.0]
    {
        let first = unwrap f.capture.formCaches[0]
        let second = unwrap f.capture.formCaches[1]
        let firstZoom = first.zoom
        let secondZoom = second.zoom
        f.editView.setZoom(zoom, mouseCenter: true)
        watch.restart()
        discard f.gui.render(f.main)
        let preview = watch.elapsedMilliseconds()
        Swag.require(first.zoom == firstZoom and second.zoom == secondZoom)
        f.gui.fireTimer(f.editView.zoomTimer)
        watch.restart()
        discard f.gui.render(f.main)
        let settled = watch.elapsedMilliseconds()
        Swag.require(first.shadow.contentTarget!.colorBuffer.handle == firstShadow and
                     second.shadow.contentTarget!.colorBuffer.handle == secondShadow)
        Console.print("zoom ", zoom, ": preview ", preview, " ms; settled ", settled, " ms\n")
    }
}
