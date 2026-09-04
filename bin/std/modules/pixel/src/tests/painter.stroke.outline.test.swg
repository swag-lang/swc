#global if #command == Swag.CompilerCommand.Test

using Swag, Core

const OutlineTestWidth  = 160
const OutlineTestHeight = 120

// Renders one stroke over a colour neither the stroke nor its contour uses.
//
// The background carries the reading, not the alpha channel: a stroke goes through the
// no-overlap pass, which clears the alpha of the whole target.
func outlineTestRender(pen: Pen)->Image
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Blue))
    painter.setAntialiased()
    painter.drawLine(20, 60, 120, 60, pen)
    painter.end()

    var renderer: RenderCpu
    renderer.begin(OutlineTestWidth, OutlineTestHeight)
    let render: IRenderer = &renderer
    render.draw(&painter)
    render.end()
    return renderer.surfaceImage()
}

// Rows of one column covered by the stroke itself, and by anything the stroke painted.
//
// The two are read from the same column so a contour shows up as the difference between them,
// which is what its width is.
func outlineTestSpan(img: Image, x: s32, whiteOnly: bool)->{ top, bottom: s32 }
{
    var result: retval = {-1, -1}
    for y in OutlineTestHeight
    {
        let c = img.pixelColor(x, cast(s32) y)
        if c.r <= 60 and c.b >= 150 do
            continue
        if whiteOnly and c.r < 200 do
            continue

        if result.top < 0 do
            result.top = cast(s32) y
        result.bottom = cast(s32) y
    }

    return result
}

// The x of every place the stroke starts or stops covering the row it runs along.
func outlineTestRuns(img: Image, y: s32)->Array's32
{
    var result: retval
    var inside = false
    for x in OutlineTestWidth
    {
        let c  = img.pixelColor(cast(s32) x, y)
        let on = c.r >= 200
        if on != inside
        {
            result.add(cast(s32) x)
            inside = on
        }
    }

    return result
}

// The pen a contour test strokes with; `outline` zero asks for no contour.
func outlineTestPen(outline: f32, cap: LineCapStyle, dash: DashStyle)->Pen
{
    var result = Pen.createDash(dash, Color.fromArgb(Argb.White), 8)
    result.begCapStyle  = .None
    result.endCapStyle  = cap
    result.outlineSize  = outline
    result.outlineColor = Color.fromArgb(Argb.Black)
    return result
}

// A contour keeps the width it was asked for along the shaft, on both sides of it.
#test
{
    let img  = outlineTestRender(outlineTestPen(4, .None, .None))
    let all  = outlineTestSpan(img, 60, whiteOnly: false)
    let core = outlineTestSpan(img, 60, whiteOnly: true)

    Swag.assert(core.bottom - core.top == 7)
    Swag.assert(core.top - all.top == 4)
    Swag.assert(all.bottom - core.bottom == 4)
}

// A contour is the stroke pushed outward, so it leaves the stroke it surrounds exactly as it was.
//
// Stroking a second, wider pen underneath instead scaled every cap with that pen: the arrow head
// drawn over it came out proportionally larger, and covered the one below it completely, so the
// head ended up with no contour at all along either of its sloped sides.
#test
{
    let plain    = outlineTestRender(outlineTestPen(0, .ArrowAnchor, .None))
    let bordered = outlineTestRender(outlineTestPen(4, .ArrowAnchor, .None))

    // The head is at the end of the line and is widest where it meets the shaft.
    const HeadX = 112

    let plainCore    = outlineTestSpan(plain, HeadX, whiteOnly: true)
    let borderedCore = outlineTestSpan(bordered, HeadX, whiteOnly: true)
    Swag.assert(plainCore.top == borderedCore.top)
    Swag.assert(plainCore.bottom == borderedCore.bottom)

    // And the head carries the contour the shaft carries.
    let borderedAll = outlineTestSpan(bordered, HeadX, whiteOnly: false)
    Swag.assert(borderedCore.top - borderedAll.top == 4)
    Swag.assert(borderedAll.bottom - borderedCore.bottom == 4)
}

// A contoured dashed stroke keeps the dash pattern of the stroke itself.
//
// The pattern is measured in stroke widths, so widening a second pen to draw the contour lengthed
// every dash with it and the two rows of dashes stopped lining up.
#test
{
    let plain    = outlineTestRender(outlineTestPen(0, .None, .Dash))
    let bordered = outlineTestRender(outlineTestPen(2, .None, .Dash))

    let plainRuns    = outlineTestRuns(plain, 60)
    let borderedRuns = outlineTestRuns(bordered, 60)
    Swag.assert(plainRuns.count > 4)
    Swag.assert(plainRuns.count == borderedRuns.count)
    for r, i in plainRuns do
        Swag.assert(r == borderedRuns[i])
}

// An arc fan covers its own centre.
//
// Every triangle of the fan used to meet the next one exactly on that point, and the pixel
// sitting on it fell outside all of them: a round line end painted over a contrasting ground
// showed a single hole in its middle, which a contour under the stroke makes plain.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Black))
    painter.setAntialiased()

    var pen = Pen.createSolid(Color.fromArgb(Argb.White), 14)
    pen.begCapStyle  = .RoundAnchor
    pen.endCapStyle  = .None
    pen.capBegScaleX = 3
    pen.capBegScaleY = 3
    painter.drawLine(40, 60, 120, 60, pen)
    painter.end()

    var renderer: RenderCpu
    renderer.begin(OutlineTestWidth, OutlineTestHeight)
    let render: IRenderer = &renderer
    render.draw(&painter)
    render.end()

    let img = renderer.surfaceImage()
    for y in 58 to 62
    {
        for x in 38 to 42 do
            Swag.assert(img.pixelColor(cast(s32) x, cast(s32) y).r == 255)
    }
}
