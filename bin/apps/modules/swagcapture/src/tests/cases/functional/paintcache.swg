#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The retained form renderings (see FormCache) are an invisible optimization: whatever
// mix of cached, scaled, and freshly rendered forms a repaint composites, the pixels
// must be the ones a from-scratch render of every form produces. Comparisons across
// two different bake frames tolerate one least-significant antialiasing step: the
// software rasterizer is bit-exact within a frame, but the batching context of another
// frame can move an edge sample by one. A stale or misplaced cache produces large
// deltas and still fails.
const CrossBakeTolerance = Pixel.Testing.ImageGoldenOptions{maxChannelDelta: 2}

// A Gaussian form shadow keeps nonzero alpha in its retained mask.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()
    let arrow = testAddArrow(f.capture, 50, 50, 150, 120)
    discard f.gui.render(f.main)
    let cache    = unwrap f.capture.findFormCache(arrow)
    let target   = unwrap cache.shadow.contentTarget
    var mask     = f.editView.app().renderer.readRenderTarget(target, 0, 0, target.colorBuffer.width, target.colorBuffer.height)
    var maxAlpha = 0'u8
    for y in 0 until mask.height
    {
        for x in 0 until mask.width do
            maxAlpha = Math.max(maxAlpha, mask.pixelColor(x, y).a)
    }

    Swag.require(maxAlpha > 40)

    let shadowTexture = cache.shadow.contentTarget.colorBuffer.handle
    var exported      = f.capture.toImage()
    Swag.require(exported.pixelColor(100, 94).r < 250)

    arrow.paintShadow = false
    f.capture.invalidateFormCache(arrow)
    discard f.gui.render(f.main)
    Swag.require(cache.shadow.contentTarget == null)

    arrow.paintShadow = true
    f.capture.invalidateFormCache(arrow)
    discard f.gui.render(f.main)
    Swag.require(cache.shadow.contentTarget != null and cache.shadow.contentTarget.colorBuffer.handle != shadowTexture)
}

func testPopulate(capture: *Capture)
{
    // Cache invalidation needs varied forms and a complete 2x zoom, not a desktop-sized image.
    capture.width, capture.widthOrg   = 200
    capture.height, capture.heightOrg = 150
    capture.backImg = Image.create(200, 150, .BGRA8)
    discard testAddShape(capture, 10, 10, 50, 35)
    let rotated = testAddShape(capture, 75, 10, 45, 30)
    rotated.rotate = 35
    discard testAddArrow(capture, 15, 65, 65, 90)
    discard testAddLine(capture, 80, 65, 120, 95)
    let text = testAddText(capture, 125, 20, 60, 30)
    text.text     = "Cache"
    text.fontSize = 24
    discard testAddStep(capture, 150, 75, 20, 20)

    var polyPoints: Array'Math.Vector2
    polyPoints.add({15, 110})
    polyPoints.add({45, 102.5})
    polyPoints.add({55, 130})
    polyPoints.add({25, 137.5})
    discard testAddPolygon(capture, polyPoints.toSlice())

    var drawPoints: Array'Math.Vector2
    drawPoints.add({75, 110})
    drawPoints.add({95, 120})
    drawPoints.add({115, 112.5})
    drawPoints.add({130, 127.5})
    discard testAddDraw(capture, drawPoints.toSlice())

    discard testAddShape(capture, 140, 105, 45, 30, .Highlight)
}

// A repaint that changed nothing draws every form from its retained rendering and must
// reproduce the first, cache-filling render exactly.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()
    testPopulate(f.capture)

    var cold = f.gui.render(f.main)
    var warm = f.gui.render(f.main)
    Pixel.Testing.assertImagesNear(&cold, &warm, "paintcache.warm")
}

// A translation keeps the retained rendering and only moves its quad; the composite
// must still equal a forced from-scratch render of every form.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()
    testPopulate(f.capture)
    discard f.gui.render(f.main)

    f.capture.selection.add(0)
    with let u = f.capture.newUndo(.OffsetSelection)
    {
        .newPosX = 30
        .newPosY = 12
    }

    f.capture.pushUndo(u)

    var moved = f.gui.render(f.main)
    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    Pixel.Testing.assertImagesNear(&fresh, &moved, "paintcache.moved", CrossBakeTolerance)
}

// A zoom first draws the retained renderings scaled, then sharpens a few forms per
// repaint; once nothing is left stale the result must equal a from-scratch render.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()
    testPopulate(f.capture)
    discard f.gui.render(f.main)

    f.editView.setZoom(2)
    let captureRect = f.editView.getCaptureRect()
    Swag.require(captureRect.x >= 0 and
                 captureRect.y >= 0 and
                 captureRect.right() <= f.editView.position.width and
                 captureRect.bottom() <= f.editView.position.height)
    Swag.require(f.editView.zoomTimer != null)
    f.gui.fireTimer(f.editView.zoomTimer)
    for 12 do
        discard f.gui.render(f.main)
    Swag.require(not f.capture.cacheNeedsRefine)

    var settled = f.gui.render(f.main)
    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    Pixel.Testing.assertImagesNear(&fresh, &settled, "paintcache.zoom", CrossBakeTolerance)
}

// A content change through the undo timeline re-renders the touched form: the repaint
// right after the edit must already match a forced from-scratch render.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()
    testPopulate(f.capture)
    discard f.gui.render(f.main)

    f.capture.selection.add(4)
    let u = f.capture.newUndo(.SetText)
    u.text = "Edited"
    f.capture.pushUndo(u)

    var edited = f.gui.render(f.main)
    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    Pixel.Testing.assertImagesNear(&fresh, &edited, "paintcache.edited", CrossBakeTolerance)
}

// A form larger than the editor retains the visible part at the current zoom.
// Repainting and a zoom step reuse that layer; settling and scrolling bake a new view.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()

    var points: Array'Math.Vector2
    points.add({-1000, -1000})
    points.add({1300, -1000})
    points.add({-1000, 1300})
    let polygon = testAddPolygon(f.capture, points.toSlice())
    polygon.paintShadow = true
    polygon.borderSize  = 23

    f.editView.setZoom(4)
    discard f.gui.render(f.main)
    let cache = unwrap f.capture.findFormCache(polygon)
    Swag.require(cache.clipped)
    let view = f.editView.clientRect()
    Swag.require(cache.layer.width <= view.width + 200 and cache.layer.height <= view.height + 200)
    let texture = cache.layer.contentTarget!.colorBuffer.handle

    var warm = f.gui.render(f.main)
    Swag.require(cache.layer.contentTarget.colorBuffer.handle == texture)
    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    Pixel.Testing.assertImagesNear(&fresh, &warm, "paintcache.clipped", CrossBakeTolerance)

    let bakedZoom    = cache.zoom
    let bakedTexture = cache.layer.contentTarget.colorBuffer.handle
    f.gui.moveMouse({260, 190})
    f.editView.setZoom(4.1, mouseCenter: true)
    Swag.require(f.editView.zoomTimer != null)
    discard f.gui.render(f.main)
    Swag.require(cache.zoom == bakedZoom and cache.layer.contentTarget.colorBuffer.handle == bakedTexture)
    f.editView.setZoom(4.2, mouseCenter: true)
    discard f.gui.render(f.main)
    Swag.require(cache.zoom == bakedZoom and cache.layer.contentTarget.colorBuffer.handle == bakedTexture)
    f.gui.fireTimer(f.editView.zoomTimer)
    discard f.gui.render(f.main)
    Swag.require(cache.zoom == 4.2)

    f.editView.setZoom(4.1, mouseCenter: true)
    discard f.gui.render(f.main)
    Swag.require(cache.zoom == 4.2)
    f.gui.fireTimer(f.editView.zoomTimer)
    discard f.gui.render(f.main)
    Swag.require(cache.zoom == 4.1)

    let oldOrigin = cache.origin
    f.editView.scrollPos.x += 40
    discard f.gui.render(f.main)
    Swag.require(cache.origin.x != oldOrigin.x)
}

// A text whose fill lets the capture through shows the capture inside its glyphs, not the colour
// of its border: the border is a ring around the glyphs, painted only where they are not.
#test
{
    var f: HeadlessFixture
    f.setup(520, 380)
    defer f.shutdown()

    f.capture.width, f.capture.widthOrg   = 240
    f.capture.height, f.capture.heightOrg = 160
    f.capture.backImg = Image.create(240, 160, .BGRA8)
    f.capture.backImg.fill(Color.fromArgb(0xFF0000FF))
    f.capture.dirtyBackImg = true

    with let text = testAddText(f.capture, 20, 20, 200, 120)
    {
        .text        = "I"
        .fontSize    = 110
        .boldSize    = 4
        .borderSize  = 6
        .borderColor = Color.fromArgb(Argb.White)
        .backColor   = Color.fromArgb(128, Argb.Red)
        .paintShadow = false
    }

    discard f.gui.render(f.main)
    var exported = f.capture.toImage()

    // The middle of the stem: half red over the blue capture, with no white under it.
    let inside = exported.pixelColor(120, 80)
    Swag.require(inside.b > 90 and inside.r > 90 and inside.g < 40)
}
