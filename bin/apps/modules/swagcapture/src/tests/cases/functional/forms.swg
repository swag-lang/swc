#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

struct TextPaintTransform
{
    tr:    Math.Transform2
    found: bool
}

func testTextPaintTransform(text: *FormText, tx, ty, z, renderScale: f32)->TextPaintTransform
{
    var result: #returntype

    var painter: Painter
    painter.begin(layoutOnly: true)
    painter.setAntialiased()
    painter.translateTransform(tx * renderScale, ty * renderScale)

    var cxt: FormPaintContext
    cxt.z = z
    cxt.renderScale = renderScale
    text.IForm.paint(&painter, cxt)

    for cmd in painter.commandBuffer where cmd.op is .Transform
    {
        let tr      = cmd.transform.tr
        let weight  = Math.abs(tr.m11) + Math.abs(tr.m22) + Math.abs(tr.tx) + Math.abs(tr.ty)
        let current = Math.abs(result.tr.m11) + Math.abs(result.tr.m22) + Math.abs(result.tr.tx) + Math.abs(result.tr.ty)
        if not result.found or weight > current
        {
            result.tr    = tr
            result.found = true
        }
    }

    painter.end()
    return result
}

func testAssertScaledTransform(base, scaled: TextPaintTransform, scale: f32)
{
    Swag.require(base.found and scaled.found)
    Swag.require(Math.abs(base.tr.m11 - scaled.tr.m11 / scale) < 0.001)
    Swag.require(Math.abs(base.tr.m22 - scaled.tr.m22 / scale) < 0.001)
    Swag.require(Math.abs(base.tr.tx - scaled.tr.tx / scale) < 0.01)
    Swag.require(Math.abs(base.tr.ty - scaled.tr.ty / scale) < 0.01)
}

// Off-screen form layers reserve only the geometry that can escape the tight bound.
#test
{
    var shape: FormShape
    shape.borderSize = 5
    let shapeItf: IForm = &shape
    Swag.require(BaseForm.paintOverdraw(shapeItf, false) == 10)
    Swag.require(BaseForm.paintOverdraw(shapeItf, true) == BaseForm.QuickPaintOverdraw)

    // The line ends are shaped from the stroke and the contour is pushed out around them, so
    // the anchor reserves 5/2 * 20 and the contour adds its own 3 once: 50 + 3, plus the
    // antialiasing margin. A round anchor is a disc, so its radius is that same 50 whatever
    // direction the line runs in.
    var line: FormLine
    line.borderSize  = 5
    line.outlineSize = 3
    line.startSize   = 4
    line.endSize     = 20
    line.endCap      = .RoundAnchor
    let lineItf: IForm = &line
    Swag.require(BaseForm.paintOverdraw(lineItf, false) == 55)

    // FormArrow embeds FormLine but has its own runtime type. Its arrowhead must reserve the
    // same layer margin instead of falling back to the ordinary-stroke extent.
    var arrow: FormArrow
    arrow.borderSize  = 5
    arrow.outlineSize = 3
    arrow.endSize     = 8
    arrow.endCap      = .ArrowAnchor
    let arrowItf: IForm = &arrow

    // An arrow head stands 5/2 * 8 across the line and reaches twice that back along it, so the
    // corner between the two is at their diagonal, 44.7, wherever the line points.
    Swag.require(BaseForm.paintOverdraw(arrowItf, false) == 50)
}

// Stroke contours participate in both painting and hit testing; a point outside the core must
// become selectable once its outer contour reaches it.
#test
{
    var line: FormLine
    line.xa         = 10
    line.ya         = 10
    line.xb         = 100
    line.yb         = 10
    line.borderSize = 4
    let lineCore = line.IForm.hitTest({50, 14}, 1)
    Swag.require(not lineCore)
    line.outlineSize = 4
    let lineOutline = line.IForm.hitTest({50, 14}, 1)
    Swag.require(lineOutline)

    var draw: FormDraw
    draw.points.add({10, 10})
    draw.points.add({100, 10})
    draw.borderSize = 4
    let drawCore = draw.IForm.hitTest({50, 14}, 1)
    Swag.require(not drawCore)
    draw.outlineSize = 4
    let drawOutline = draw.IForm.hitTest({50, 14}, 1)
    Swag.require(drawOutline)
    Gui.Testing.assertRect(draw.IForm.boundRect(), 4, 4, 102, 12)
}

// Rectangle-like forms normalize negative sizes and keep their base geometry coherent.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 20, 30, 40)
    shape.IForm.setBaseForm(80, 90, -20, -30)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 60, 60, 20, 30)

    shape.IForm.moveBaseForm(5, -7, 3, 4)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 65, 53, 23, 34)

    shape.IForm.moveForm(-2, 3)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 63, 56, 23, 34)

    shape.IForm.scaleBaseForm(2)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 126, 112, 46, 68)

    shape.kind = .Ellipse
    Swag.require(shape.IForm.isInside({149, 146}))
    Swag.require(not shape.IForm.isInside({126, 112}))

    shape.kind = .Rectangle
    Swag.require(shape.IForm.isInside({-1000, -1000}))
}

// Text supersampling must only increase raster resolution, never logical layout.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let text = testAddText(f.capture, 20, 30, 180, 90)
    text.text        = "780"
    text.fontSize    = 48
    text.borderSize  = 7
    text.boldSize    = 2
    text.backColor   = Argb.Black
    text.borderColor = Argb.White

    let base   = testTextPaintTransform(text, 17, -9, 1, 1)
    let scaled = testTextPaintTransform(text, 17, -9, 1, 3)
    testAssertScaledTransform(base, scaled, 3)
}

// Text, image and step forms expose the expected non-painting interaction contracts.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let text = testAddText(f.capture, 20, 30, 120, 50)
    Swag.require(text.IForm.mustClipToBound())
    Swag.require(text.IForm.canRotate())
    Swag.require(text.IForm.hitTest({30, 40}, 1))
    Swag.require(not text.IForm.hitTest({10, 10}, 1))
    text.subKind = .Highlight
    Swag.require(not text.IForm.canRotate())

    let image = testAddImage(f.capture, 40, 50, 80, 90)
    Swag.require(image.IForm.canRotate())
    Swag.require(image.IForm.hitTest({50, 60}, 1))
    Swag.require(not image.IForm.hitTest({5, 5}, 1))
    image.kind       = .Image
    image.place      = .Free
    image.editInside = true
    image.freePos    = {3, 4, 10, 20}
    Swag.require(image.kind == .Image and image.place == .Free and image.editInside)
    Swag.require(not image.IForm.canRotate())
    image.IForm.moveBaseForm(7, 8, 9, 10)
    Gui.Testing.assertRect(image.freePos, 10, 12, 19, 30)

    with let step = testAddStep(f.capture, 0, 0, 10, 10)
    {
        .ws = 30
        .hs = 40
    }

    f.capture.nextStepIndex = 7
    var evt     = testMouse(.Move)
    let editing = step.IForm.edit(&evt, {100, 90}, {120, 110}, 1)
    Swag.require(not editing)
    Gui.Testing.assertRect(step.IForm.boundRect(), 85, 70, 30, 40)
    Swag.require(step.index == 7)
    Swag.require(f.capture.nextStepIndex == 8)
    Swag.require(step.isDirty)
}

// The margin a form's layer reserves holds everything that form paints, at every angle.
//
// The line ends stand across the line as well as along it, so the corner of a square one, or of
// an arrow head, lands at the diagonal of the two: reserving the larger of the two axes alone cut
// that corner off as soon as the line stopped being axis aligned, and a cap grown by its size row
// lost more of itself the larger it got.
func testAssertFormFitsItsMargin(itf: IForm)
{
    var painter: Painter
    painter.begin(layoutOnly: true)
    painter.setAntialiased()

    var cxt: FormPaintContext
    cxt.z = 1
    itf.paint(&painter, cxt)
    painter.end()

    var minimum = Math.Vector2{Swag.F32.Max, Swag.F32.Max}
    var maximum = Math.Vector2{-Swag.F32.Max, -Swag.F32.Max}
    for cmd in painter.commandBuffer where cmd.op is .DrawTriangles
    {
        for i in cmd.drawTriangles.count
        {
            let pos = painter.vertexBuffer[cmd.drawTriangles.start + i].pos
            minimum = Math.Vector2.min(minimum, pos)
            maximum = Math.Vector2.max(maximum, pos)
        }
    }

    if minimum.x > maximum.x do
        return

    var room = itf.boundRect()
    room.inflate(BaseForm.paintOverdraw(itf, false))
    Swag.require(minimum.x >= room.x and minimum.y >= room.y)
    Swag.require(maximum.x <= room.right() and maximum.y <= room.bottom())
}

#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    const Angles = [0.0, 23.0, 45.0, 67.0, 90.0, 143.0, 200.0, 300.0]
    for cap in LineCapStyle
    {
        for a in Angles.count
        {
            let angle = Math.toRadians(Angles[a])

            with let line = testAddLine(f.capture, 200, 200, 200 + Math.cos(angle) * 120, 200 + Math.sin(angle) * 120)
            {
                .borderSize  = 18
                .outlineSize = 4
                .beginCap    = cap
                .endCap      = cap
                .startSize   = MaxCapSize
                .endSize     = MaxCapSize
            }

            testAssertFormFitsItsMargin(line)

            line.dashStyle = .Dash
            line.dashCap   = .Square
            testAssertFormFitsItsMargin(line)
        }
    }
}

// Line-like forms keep endpoint, control-point and bound-rect state consistent.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let line = testAddLine(f.capture, 10, 60, 40, 20)
    Gui.Testing.assertRect(line.IForm.boundRect(), 10, 20, 30, 40)

    line.IForm.movePoint(0, 5, -10)
    Swag.require(line.xa == 15)
    Swag.require(line.ya == 50)
    line.IForm.movePoint(1, -15, 25)
    Swag.require(line.xb == 25)
    Swag.require(line.yb == 45)

    line.bezier = true
    line.IForm.movePoint(2, 30, -5)
    Swag.require(line.xc == 40)
    Swag.require(line.yc == 5)
    let br0 = line.IForm.boundRect()
    let br1 = line.IForm.boundRect()
    Swag.require(br0 == br1)

    let arrow = testAddArrow(f.capture, 100, 120, 140, 150)
    arrow.IForm.moveBaseForm(-10, 5, 0, 0)
    Swag.require(arrow.xa == 90)
    Swag.require(arrow.ya == 125)
    Swag.require(arrow.xb == 130)
    Swag.require(arrow.yb == 155)
}

// Polygon and draw forms share point-list movement, scaling and inside tests.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    var polyPoints: Array'Math.Vector2
    polyPoints.add({10, 10})
    polyPoints.add({60, 10})
    polyPoints.add({40, 50})
    let polygon = testAddPolygon(f.capture, polyPoints.toSlice())
    Gui.Testing.assertRect(polygon.IForm.boundRect(), 10, 10, 50, 40)
    Swag.require(polygon.IForm.isInside({35, 20}))
    Swag.require(not polygon.IForm.isInside({5, 5}))

    polygon.IForm.movePoint(1, 10, 15)
    Gui.Testing.assertPoint(polygon.points[1], 70, 25)
    polygon.IForm.moveBaseForm(-5, 3, 0, 0)
    Gui.Testing.assertRect(polygon.IForm.boundRect(), 5, 13, 60, 40)
    polygon.IForm.scaleBaseForm(2)
    Gui.Testing.assertRect(polygon.IForm.boundRect(), 10, 26, 120, 80)

    var drawPoints: Array'Math.Vector2
    drawPoints.add({100, 100})
    drawPoints.add({120, 110})
    drawPoints.add({130, 140})
    let draw = testAddDraw(f.capture, drawPoints.toSlice())
    draw.borderSize = 10
    Gui.Testing.assertRect(draw.IForm.boundRect(), 95, 95, 40, 50)
    Swag.require(draw.IForm.isInside({118, 112}))
    Swag.require(not draw.IForm.isInside({80, 80}))
    draw.IForm.movePoint(2, -10, 20)
    Gui.Testing.assertPoint(draw.points[2], 120, 160)
    draw.IForm.moveForm(3, -4)
    Gui.Testing.assertPoint(draw.points[0], 103, 96)
}

// Form edit methods produce deterministic geometry and completion flags.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let shape   = testAddShape(f.capture, 0, 0, 1, 1)
    var moveEvt = testMouse(.Move)
    var editing = shape.IForm.edit(&moveEvt, {80, 70}, {50, 20}, 1)
    Swag.require(editing)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 50, 20, 30, 50)
    var releaseEvt = testMouse(.Released)
    editing = shape.IForm.edit(&releaseEvt, {80, 70}, {50, 20}, 1)
    Swag.require(not editing)

    let line = testAddLine(f.capture, 0, 0, 1, 1)
    editing = line.IForm.edit(&moveEvt, {10, 20}, {70, 90}, 2)
    Swag.require(editing)
    Swag.require(line.xa == 5)
    Swag.require(line.ya == 10)
    Swag.require(line.xb == 35)
    Swag.require(line.yb == 45)
    editing = line.IForm.edit(&releaseEvt, {10, 20}, {70, 90}, 2)
    Swag.require(not editing)

    let image = testAddImage(f.capture, 0, 0, 1, 1)
    editing = image.IForm.edit(&moveEvt, {20, 30}, {60, 100}, 1)
    Swag.require(editing)
    Swag.require(not image.isReadyToCapture)
    editing = image.IForm.edit(&releaseEvt, {20, 30}, {60, 100}, 1)
    Swag.require(not editing)
    Swag.require(image.isReadyToCapture)
}

// Point-list edit methods add, update and finish without relying on painting.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    var moveEvt    = testMouse(.Move)
    var releaseEvt = testMouse(.Released)
    var doubleEvt  = testMouse(.DoubleClick)

    var emptyPoints: Array'Math.Vector2
    let polygon = testAddPolygon(f.capture, emptyPoints.toSlice())
    var editing = polygon.IForm.edit(&moveEvt, {10, 10}, {20, 20}, 1)
    Swag.require(editing)
    Swag.require(polygon.points.count == 2)
    Gui.Testing.assertPoint(polygon.points[0], 10, 10)
    Gui.Testing.assertPoint(polygon.points[1], 20, 20)
    editing = polygon.IForm.edit(&releaseEvt, {10, 10}, {40, 50}, 1)
    Swag.require(editing)
    Swag.require(polygon.points.count == 3)
    Gui.Testing.assertPoint(polygon.points[2], 40, 50)
    editing = polygon.IForm.edit(&doubleEvt, {10, 10}, {40, 50}, 1)
    Swag.require(not editing)
    Swag.require(polygon.points.count == 3)

    let draw = testAddDraw(f.capture, emptyPoints.toSlice())
    editing = draw.IForm.edit(&moveEvt, {5, 5}, {8, 8}, 1)
    Swag.require(editing)
    Swag.require(draw.points.count == 2)
    editing = draw.IForm.edit(&moveEvt, {5, 5}, {14, 8}, 1)
    Swag.require(editing)
    Swag.require(draw.points.count == 3)
    editing = draw.IForm.edit(&moveEvt, {5, 5}, {15, 9}, 1)
    Swag.require(editing)
    Swag.require(draw.points.count == 3)
    editing = draw.IForm.edit(&releaseEvt, {5, 5}, {15, 9}, 1)
    Swag.require(not editing)
}

// Copy/isSame covers every concrete form family and the regression-sensitive subKind fields.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    with let shape = testAddShape(f.capture, 1, 2, 30, 40, .Highlight)
    {
        .kind      = .RoundRectangle
        .roundSize = 25
    }

    var shapeCopy: FormShape
    shape.IForm.copy(&shapeCopy, shape)
    Swag.require(shapeCopy.subKind == .Highlight)
    Swag.require(shape.IForm.isSame(&shapeCopy))
    shapeCopy.roundSize += 1
    Swag.require(not shape.IForm.isSame(&shapeCopy))

    with let text = testAddText(f.capture, 0, 0, 50, 60)
    {
        .fontSize  = 34
        .boldSize  = 2
        .joinStyle = .Bevel
    }

    var textCopy: FormText
    text.IForm.copy(&textCopy, text)
    Swag.require(text.IForm.isSame(&textCopy))
    textCopy.fontSize += 1
    Swag.require(not text.IForm.isSame(&textCopy))

    with let step = testAddStep(f.capture, 0, 0, 20, 30)
    {
        .kind      = .RoundRectangle
        .typeIndex = .LetterDown
        .ws        = 36
        .hs        = 44
    }

    var stepCopy: FormStep
    step.IForm.copy(&stepCopy, step)
    Swag.require(stepCopy.ws == 36)
    Swag.require(stepCopy.hs == 44)
    Swag.require(step.IForm.isSame(&stepCopy))
    stepCopy.typeIndex = .LetterUp
    Swag.require(not step.IForm.isSame(&stepCopy))

    with let line = testAddLine(f.capture, 0, 0, 10, 10, .PixSel)
    {
        .outlineSize  = 3
        .outlineColor = ColorBlue
        .dashCap      = .Round
        .bezier       = true
        .paintShadow  = false
    }

    var lineCopy: FormLine
    line.IForm.copy(&lineCopy, line)
    Swag.require(lineCopy.subKind == .PixSel)
    Swag.require(not lineCopy.paintShadow)
    Swag.require(lineCopy.outlineSize == 3 and lineCopy.outlineColor == ColorBlue)
    Swag.require(line.IForm.isSame(&lineCopy))
    lineCopy.subKind = .Highlight
    Swag.require(not line.IForm.isSame(&lineCopy))

    var points: Array'Math.Vector2
    points.add({1, 1})
    points.add({20, 1})
    points.add({10, 20})

    with let polygon = testAddPolygon(f.capture, points.toSlice(), .Highlight)
    {
        .paintShadow = false
        .bezier      = true
    }

    var polygonCopy: FormPolygon
    polygon.IForm.copy(&polygonCopy, polygon)
    Swag.require(polygonCopy.subKind == .Highlight)
    Swag.require(not polygonCopy.paintShadow)
    Swag.require(polygon.IForm.isSame(&polygonCopy))
    polygonCopy.subKind = .PixSel
    Swag.require(not polygon.IForm.isSame(&polygonCopy))

    with let draw = testAddDraw(f.capture, points.toSlice(), .PixSel)
    {
        .outlineSize  = 3
        .outlineColor = ColorBlue
        .paintShadow  = false
    }

    var drawCopy: FormDraw
    draw.IForm.copy(&drawCopy, draw)
    Swag.require(drawCopy.subKind == .PixSel)
    Swag.require(not drawCopy.paintShadow)
    Swag.require(drawCopy.outlineSize == 3 and drawCopy.outlineColor == ColorBlue)
    Swag.require(draw.IForm.isSame(&drawCopy))
    drawCopy.paintShadow = true
    Swag.require(not draw.IForm.isSame(&drawCopy))

    with let image = testAddImage(f.capture, 0, 0, 40, 50)
    {
        .kind      = .Image
        .strength  = 77
        .backColor = ColorRed
    }

    var imageCopy: FormImage
    image.IForm.copy(&imageCopy, image)
    Swag.require(image.IForm.isSame(&imageCopy))
    imageCopy.backColor = ColorBlue
    Swag.require(not image.IForm.isSame(&imageCopy))
    image.kind     = .Blur
    imageCopy.kind = .Blur
    Swag.require(image.IForm.isSame(&imageCopy))
}

// An attached form uses its own application's theme and keeps texture ownership when
// another Capture window becomes the module's active global application.
#test
{
    var first: HeadlessFixture
    first.setup()
    defer first.shutdown()
    first.gui.app.theme.setLight()

    var second: HeadlessFixture
    second.setup()
    defer second.shutdown()
    second.gui.app.theme.setDark()

    var image: FormImage
    image.image = Image.create(8, 8, .BGRA8)
    image.capture = first.capture
    Swag.require(image.ownerApp() == &first.gui.app)
    image.backCapture()
    Swag.require(image.texture.isValid() and image.textureApp == &first.gui.app)
    Swag.require(first.gui.app.renderer.readTexturePixels(image.texture, .BGRA8).count ==
                 image.image.byteCount)

    var painter: Painter
    painter.begin(layoutOnly: true)
    let style = image.applyPixSelStyle(&painter, {})
    Swag.require(style.bSize > 0 and image.borderColor ==
                 first.gui.app.theme.colors.btnIcon_Icon)
    Swag.require(image.borderColor != second.gui.app.theme.colors.btnIcon_Icon)
    painter.end()

    var step: FormStep
    step.capture = first.capture
    step.w = 48
    step.h = 48
    var context: FormPaintContext
    context.z = 1
    painter.begin(layoutOnly: true)
    step.IForm.paint(&painter, context)
    painter.end()
    Swag.require(step.cacheFace == first.gui.app.theme.res.defaultTypeFaceR)

    image.capture = second.capture
    image.backCapture()
    Swag.require(image.texture.isValid() and image.textureApp == &second.gui.app)
    Swag.require(second.gui.app.renderer.readTexturePixels(image.texture, .BGRA8).count ==
                 image.image.byteCount)
    image.image = {}
    image.backCapture()
    Swag.require(not image.texture.isValid())
}
