#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The retained form renderings (see FormCache) are an invisible optimization: whatever
// mix of cached, scaled, and freshly rendered forms a repaint composites, the pixels
// must be exactly the ones a from-scratch render of every form produces. The software
// renderer is bit-exact, so every comparison here is byte equality.

func testSameImage(a, b: *Pixel.Image)->bool
{
    if a.width != b.width or a.height != b.height or a.pixels.count != b.pixels.count do
        return false
    let sa = a.pixels.toSlice()
    let sb = b.pixels.toSlice()
    return @memcmp(@dataof(sa), @dataof(sb), @countof(sa)) == 0
}

func testPopulate(f: *HeadlessFixture)
{
    discard testAddShape(f.capture, 20, 20, 100, 70)
    let rotated = testAddShape(f.capture, 150, 20, 90, 60)
    rotated.rotate = 35
    discard testAddArrow(f.capture, 30, 130, 130, 180)
    discard testAddLine(f.capture, 160, 130, 240, 190)
    let text = testAddText(f.capture, 250, 40, 120, 60)
    text.text = "Cache"
    discard testAddStep(f.capture, 300, 150, 40, 40)

    var polyPoints: Array'Math.Vector2
    polyPoints.add({30, 220})
    polyPoints.add({90, 205})
    polyPoints.add({110, 260})
    polyPoints.add({50, 275})
    discard testAddPolygon(f.capture, polyPoints.toSlice())

    var drawPoints: Array'Math.Vector2
    drawPoints.add({150, 220})
    drawPoints.add({190, 240})
    drawPoints.add({230, 225})
    drawPoints.add({260, 255})
    discard testAddDraw(f.capture, drawPoints.toSlice())

    discard testAddShape(f.capture, 280, 210, 90, 60, .Highlight)
}

// A repaint that changed nothing draws every form from its retained rendering and must
// reproduce the first, cache-filling render exactly.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPopulate(&f)

    var cold = f.gui.render(f.main)
    @assert(cold.isValid())
    var warm = f.gui.render(f.main)
    @assert(testSameImage(&cold, &warm))
}

// A translation keeps the retained rendering and only moves its quad; the composite
// must still equal a forced from-scratch render of every form.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPopulate(&f)
    discard f.gui.render(f.main)

    f.capture.selection.add(0)
    let u = f.capture.newUndo(.OffsetSelection)
    u.newPosX = 60
    u.newPosY = 25
    f.capture.pushUndo(u)

    var moved = f.gui.render(f.main)
    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    @assert(testSameImage(&moved, &fresh))
}

// A zoom first draws the retained renderings scaled, then sharpens a few forms per
// repaint; once nothing is left stale the result must equal a from-scratch render.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPopulate(&f)
    discard f.gui.render(f.main)

    f.editView.setZoom(2)
    for 12 do
        discard f.gui.render(f.main)

    @assert(!f.capture.cacheNeedsRefine)

    // TEMP DIAGNOSTIC — which side diverges?
    var settled  = f.gui.render(f.main)
    var settled2 = f.gui.render(f.main)
    Console.print("[cache] settled==settled2: ", testSameImage(&settled, &settled2), "\n")

    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    f.capture.invalidateAllFormCaches()
    var fresh2 = f.gui.render(f.main)
    Console.print("[cache] fresh==fresh2: ", testSameImage(&fresh, &fresh2), "\n")
    Console.print("[cache] settled==fresh: ", testSameImage(&settled, &fresh), "\n")
    @assert(testSameImage(&settled, &fresh))
}

// A content change through the undo timeline re-renders the touched form: the repaint
// right after the edit must already match a forced from-scratch render.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPopulate(&f)
    discard f.gui.render(f.main)

    f.capture.selection.add(4)
    let u = f.capture.newUndo(.SetText)
    u.text = "Edited"
    f.capture.pushUndo(u)

    var edited = f.gui.render(f.main)
    f.capture.invalidateAllFormCaches()
    var fresh = f.gui.render(f.main)
    @assert(testSameImage(&edited, &fresh))
}
