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

func testPopulate(capture: *Capture)
{
    discard testAddShape(capture, 20, 20, 100, 70)
    let rotated = testAddShape(capture, 150, 20, 90, 60)
    rotated.rotate = 35
    discard testAddArrow(capture, 30, 130, 130, 180)
    discard testAddLine(capture, 160, 130, 240, 190)
    let text = testAddText(capture, 250, 40, 120, 60)
    text.text = "Cache"
    discard testAddStep(capture, 300, 150, 40, 40)

    var polyPoints: Array'Math.Vector2
    polyPoints.add({30, 220})
    polyPoints.add({90, 205})
    polyPoints.add({110, 260})
    polyPoints.add({50, 275})
    discard testAddPolygon(capture, polyPoints.toSlice())

    var drawPoints: Array'Math.Vector2
    drawPoints.add({150, 220})
    drawPoints.add({190, 240})
    drawPoints.add({230, 225})
    drawPoints.add({260, 255})
    discard testAddDraw(capture, drawPoints.toSlice())

    discard testAddShape(capture, 280, 210, 90, 60, .Highlight)
}

// A repaint that changed nothing draws every form from its retained rendering and must
// reproduce the first, cache-filling render exactly.
#test
{
    var f: HeadlessFixture
    f.setup()
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
    f.setup()
    defer f.shutdown()
    testPopulate(f.capture)
    discard f.gui.render(f.main)

    f.capture.selection.add(0)
    let u = f.capture.newUndo(.OffsetSelection)
    u.newPosX = 60
    u.newPosY = 25
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
    f.setup()
    defer f.shutdown()
    testPopulate(f.capture)
    discard f.gui.render(f.main)

    f.editView.setZoom(2)
    for 12 do
        discard f.gui.render(f.main)
    Swag.assert(!f.capture.cacheNeedsRefine)

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
    f.setup()
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
