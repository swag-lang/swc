#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Builds a square with a square hole, winding each contour as asked.
//
// A vector document states a fill rule over the winding count and is free to wind its
// contours either way, which is exactly what makes the direction they run in the wrong thing
// to read a hole from.
private func ringPathList(outerClockwise, innerClockwise: bool)->LinePathList
{
    var result: retval

    let outer = result.newPath()
    outer.start(4, 4)
    if outerClockwise
    {
        outer.lineTo(36, 4)
        outer.lineTo(36, 36)
        outer.lineTo(4, 36)
    }
    else
    {
        outer.lineTo(4, 36)
        outer.lineTo(36, 36)
        outer.lineTo(36, 4)
    }

    outer.close()

    let inner = result.newPath()
    inner.start(14, 14)
    if innerClockwise
    {
        inner.lineTo(26, 14)
        inner.lineTo(26, 26)
        inner.lineTo(14, 26)
    }
    else
    {
        inner.lineTo(14, 26)
        inner.lineTo(26, 26)
        inner.lineTo(26, 14)
    }

    inner.close()
    return result
}

private func renderRing(outerClockwise, innerClockwise: bool, rule: PathFillRule)->Image
{
    var paths = ringPathList(outerClockwise, innerClockwise)

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.fillPath(&paths, Color.fromArgb(Argb.Red), rule)
    painter.end()

    return renderCpu(40, 40, &painter)
}

// A simple concave contour is borrowed only while recording. Its cached tessellation survives
// repeated fills, and the recorded vertices remain valid after the source contour is dropped.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    {
        var path: LinePath
        path.start(4, 4)
        path.lineTo(28, 4)
        path.lineTo(28, 12)
        path.lineTo(12, 12)
        path.lineTo(12, 28)
        path.lineTo(4, 28)
        path.close()
        painter.fillPath(&path, Color.fromArgb(Argb.Red))
        Swag.assert(path.polygon.isSimple and not path.polygon.isConvex)
        Swag.assert(path.triangles.vertices.count != 0)
        let cached = path.triangles.vertices.buffer
        let count  = path.triangles.vertices.count
        painter.fillPath(&path, Color.fromArgb(Argb.Red))
        Swag.assert(path.triangles.vertices.buffer == cached)
        Swag.assert(path.triangles.vertices.count == count)
    }

    painter.end()
    let image = renderCpu(40, 40, &painter)
    assertPixel(image, 8, 20, Argb.Red)
    assertPixel(image, 20, 20, Argb.Zero)
}

// The painter and preparer reuse index storage across independent short-lived path lists.
// Each list owns its normalized geometry and cached triangles, not the reusable workspace.
#test
{
    var painter:  Painter
    var preparer: FillPreparer
    for 2
    {
        var paths = ringPathList(true, true)
        preparer.prepare(&paths, 1, .EvenOdd)
        let normalized = paths.normalizedFill(.EvenOdd, byDirection: false)
        var triangles  = 0'u64
        for path in normalized.paths do
            triangles += path.triangles.vertices.count
        Swag.assert(triangles != 0)
        let last   = normalized.paths[normalized.paths.count - 1]
        let cached = last.triangles.vertices.buffer

        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.Zero))
        painter.fillPath(&paths, Color.fromArgb(Argb.Red), .EvenOdd)
        painter.end()
        Swag.assert(last.triangles.vertices.buffer == cached)
    }

    let image = renderCpu(40, 40, &painter)
    assertPixel(image, 8, 20, Argb.Red)
    assertPixel(image, 20, 20, Argb.Zero)
}

// The winding rule counts turns, so opposing contours cancel and agreeing ones accumulate.
//
// Which of the two directions the outline itself runs in carries no meaning: a counter that
// opposes its outline is a hole whether the pair runs clockwise-then-anticlockwise or the
// other way round. A renderer that reads the hole from the absolute direction instead fills
// in the middle of every glyph drawn the unexpected way.
#test
{
    const Opposed: [2] { outer: bool, inner: bool } = [
        {true,  false},
        {false, true}]

    for winding in Opposed
    {
        let image = renderRing(winding.outer, winding.inner, .NonZero)
        assertPixel(image, 8, 20, Argb.Red)
        assertPixel(image, 20, 20, Argb.Zero)
    }

    const Agreeing: [2] { outer: bool, inner: bool } = [
        {true,  true},
        {false, false}]

    for winding in Agreeing
    {
        let image = renderRing(winding.outer, winding.inner, .NonZero)
        assertPixel(image, 8, 20, Argb.Red)
        assertPixel(image, 20, 20, Argb.Red)
    }
}

// Several holed shapes in one fill each keep their own hole.
//
// This is what a line of text converted to outlines is: one fill holding every letter of the
// word, each an outer contour with its counter inside it. A renderer that pairs a hole with
// whichever shape happens to precede it in the list fills in the counters of all but the
// first letter, which is the state a diagram label arrives in.
#test
{
    var paths = ringPathList(true, false)

    let outer = paths.newPath()
    outer.start(44, 4)
    outer.lineTo(76, 4)
    outer.lineTo(76, 36)
    outer.lineTo(44, 36)
    outer.close()

    let inner = paths.newPath()
    inner.start(54, 14)
    inner.lineTo(54, 26)
    inner.lineTo(66, 26)
    inner.lineTo(66, 14)
    inner.close()

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.fillPath(&paths, Color.fromArgb(Argb.Red), .NonZero)
    painter.end()

    let image = renderCpu(80, 40, &painter)
    assertPixel(image, 8, 20, Argb.Red)
    assertPixel(image, 20, 20, Argb.Zero)
    assertPixel(image, 48, 20, Argb.Red)
    assertPixel(image, 60, 20, Argb.Zero)
}

// The alternating rule makes every nested contour a hole, whichever way the two run.
#test
{
    const Windings: [4] { outer: bool, inner: bool } = [
        {true,  false},
        {false, true},
        {true,  true},
        {false, false}]

    for winding in Windings
    {
        let image = renderRing(winding.outer, winding.inner, .EvenOdd)
        assertPixel(image, 8, 20, Argb.Red)
        assertPixel(image, 20, 20, Argb.Zero)
    }
}
