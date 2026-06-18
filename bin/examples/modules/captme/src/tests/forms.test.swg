#global #if #command == Swag.CompilerCommand.Test
#global fileprivate

using Swag, Core

// Rectangle-like forms normalize negative sizes and keep their base geometry coherent.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 10, 20, 30, 40)
    shape.IForm.setBaseForm(80, 90, -20, -30)
    captmeTestAssertRect(shape.IForm.boundRect(), 60, 60, 20, 30)

    shape.IForm.moveBaseForm(5, -7, 3, 4)
    captmeTestAssertRect(shape.IForm.boundRect(), 65, 53, 23, 34)

    shape.IForm.moveForm(-2, 3)
    captmeTestAssertRect(shape.IForm.boundRect(), 63, 56, 23, 34)

    shape.IForm.scaleBaseForm(2)
    captmeTestAssertRect(shape.IForm.boundRect(), 126, 112, 46, 68)

    shape.kind = .Ellipse
    @assert(shape.IForm.isInside({149, 146}))
    @assert(!shape.IForm.isInside({126, 112}))

    shape.kind = .Rectangle
    @assert(shape.IForm.isInside({-1000, -1000}))

    f.shutdown()
}

// Text, image and step forms expose the expected non-painting interaction contracts.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let text = captmeTestAddText(f.capture, 20, 30, 120, 50)
    @assert(text.IForm.mustClipToBound())
    @assert(text.IForm.canRotate())
    @assert(text.IForm.hitTest({30, 40}, 1))
    @assert(!text.IForm.hitTest({10, 10}, 1))
    text.subKind = .Highlight
    @assert(!text.IForm.canRotate())

    let image = captmeTestAddImage(f.capture, 40, 50, 80, 90)
    @assert(image.IForm.canRotate())
    @assert(image.IForm.hitTest({50, 60}, 1))
    @assert(!image.IForm.hitTest({5, 5}, 1))
    image.kind       = .Image
    image.place      = .Free
    image.editInside = true
    image.freePos    = {3, 4, 10, 20}
    @assert(image.kind == .Image and image.place == .Free and image.editInside)
    @assert(!image.IForm.canRotate())
    image.IForm.moveBaseForm(7, 8, 9, 10)
    captmeTestAssertRect(image.freePos, 10, 12, 19, 30)

    let step = captmeTestAddStep(f.capture, 0, 0, 10, 10)
    step.ws = 30
    step.hs = 40
    f.capture.nextStepIndex = 7
    var evt = captmeTestMouse(.MouseMove)
    @assert(!step.IForm.edit(&evt, {100, 90}, {120, 110}, 1))
    captmeTestAssertRect(step.IForm.boundRect(), 85, 70, 30, 40)
    @assert(step.index == 7)
    @assert(f.capture.nextStepIndex == 8)
    @assert(step.isDirty)

    f.shutdown()
}

// Line-like forms keep endpoint, control-point and bound-rect state consistent.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let line = captmeTestAddLine(f.capture, 10, 60, 40, 20)
    captmeTestAssertRect(line.IForm.boundRect(), 10, 20, 30, 40)

    line.IForm.movePoint(0, 5, -10)
    @assert(line.xa == 15)
    @assert(line.ya == 50)
    line.IForm.movePoint(1, -15, 25)
    @assert(line.xb == 25)
    @assert(line.yb == 45)

    line.bezier = true
    line.IForm.movePoint(2, 30, -5)
    @assert(line.xc == 40)
    @assert(line.yc == 5)
    let br0 = line.IForm.boundRect()
    let br1 = line.IForm.boundRect()
    @assert(br0 == br1)

    let arrow = captmeTestAddArrow(f.capture, 100, 120, 140, 150)
    arrow.IForm.moveBaseForm(-10, 5, 0, 0)
    @assert(arrow.xa == 90)
    @assert(arrow.ya == 125)
    @assert(arrow.xb == 130)
    @assert(arrow.yb == 155)

    f.shutdown()
}

// Polygon and draw forms share point-list movement, scaling and inside tests.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    var polyPoints: Array'Math.Vector2
    polyPoints.add({10, 10})
    polyPoints.add({60, 10})
    polyPoints.add({40, 50})
    let polygon = captmeTestAddPolygon(f.capture, polyPoints.toSlice())
    captmeTestAssertRect(polygon.IForm.boundRect(), 10, 10, 50, 40)
    @assert(polygon.IForm.isInside({35, 20}))
    @assert(!polygon.IForm.isInside({5, 5}))

    polygon.IForm.movePoint(1, 10, 15)
    captmeTestAssertPoint(polygon.points[1], 70, 25)
    polygon.IForm.moveBaseForm(-5, 3, 0, 0)
    captmeTestAssertRect(polygon.IForm.boundRect(), 5, 13, 60, 40)
    polygon.IForm.scaleBaseForm(2)
    captmeTestAssertRect(polygon.IForm.boundRect(), 10, 26, 120, 80)

    var drawPoints: Array'Math.Vector2
    drawPoints.add({100, 100})
    drawPoints.add({120, 110})
    drawPoints.add({130, 140})
    let draw = captmeTestAddDraw(f.capture, drawPoints.toSlice())
    draw.borderSize = 10
    captmeTestAssertRect(draw.IForm.boundRect(), 95, 95, 40, 50)
    @assert(draw.IForm.isInside({118, 112}))
    @assert(!draw.IForm.isInside({80, 80}))
    draw.IForm.movePoint(2, -10, 20)
    captmeTestAssertPoint(draw.points[2], 120, 160)
    draw.IForm.moveForm(3, -4)
    captmeTestAssertPoint(draw.points[0], 103, 96)

    f.shutdown()
}

// Form edit methods produce deterministic geometry and completion flags.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 0, 0, 1, 1)
    var moveEvt = captmeTestMouse(.MouseMove)
    @assert(shape.IForm.edit(&moveEvt, {80, 70}, {50, 20}, 1))
    captmeTestAssertRect(shape.IForm.boundRect(), 50, 20, 30, 50)
    var releaseEvt = captmeTestMouse(.MouseReleased)
    @assert(!shape.IForm.edit(&releaseEvt, {80, 70}, {50, 20}, 1))

    let line = captmeTestAddLine(f.capture, 0, 0, 1, 1)
    @assert(line.IForm.edit(&moveEvt, {10, 20}, {70, 90}, 2))
    @assert(line.xa == 5)
    @assert(line.ya == 10)
    @assert(line.xb == 35)
    @assert(line.yb == 45)
    @assert(!line.IForm.edit(&releaseEvt, {10, 20}, {70, 90}, 2))

    let image = captmeTestAddImage(f.capture, 0, 0, 1, 1)
    @assert(image.IForm.edit(&moveEvt, {20, 30}, {60, 100}, 1))
    @assert(!image.isReadyToCapture)
    @assert(!image.IForm.edit(&releaseEvt, {20, 30}, {60, 100}, 1))
    @assert(image.isReadyToCapture)

    f.shutdown()
}

// Point-list edit methods add, update and finish without relying on painting.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    var moveEvt = captmeTestMouse(.MouseMove)
    var releaseEvt = captmeTestMouse(.MouseReleased)
    var doubleEvt = captmeTestMouse(.MouseDoubleClick)

    var emptyPoints: Array'Math.Vector2
    let polygon = captmeTestAddPolygon(f.capture, emptyPoints.toSlice())
    @assert(polygon.IForm.edit(&moveEvt, {10, 10}, {20, 20}, 1))
    @assert(polygon.points.count == 2)
    captmeTestAssertPoint(polygon.points[0], 10, 10)
    captmeTestAssertPoint(polygon.points[1], 20, 20)
    @assert(polygon.IForm.edit(&releaseEvt, {10, 10}, {40, 50}, 1))
    @assert(polygon.points.count == 3)
    captmeTestAssertPoint(polygon.points[2], 40, 50)
    @assert(!polygon.IForm.edit(&doubleEvt, {10, 10}, {40, 50}, 1))
    @assert(polygon.points.count == 3)

    let draw = captmeTestAddDraw(f.capture, emptyPoints.toSlice())
    @assert(draw.IForm.edit(&moveEvt, {5, 5}, {8, 8}, 1))
    @assert(draw.points.count == 2)
    @assert(draw.IForm.edit(&moveEvt, {5, 5}, {14, 8}, 1))
    @assert(draw.points.count == 3)
    @assert(draw.IForm.edit(&moveEvt, {5, 5}, {15, 9}, 1))
    @assert(draw.points.count == 3)
    @assert(!draw.IForm.edit(&releaseEvt, {5, 5}, {15, 9}, 1))

    f.shutdown()
}

// Copy/isSame covers every concrete form family and the regression-sensitive subKind fields.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 1, 2, 30, 40, .Highlight)
    shape.kind = .RoundRectangle
    shape.roundSize = 25
    var shapeCopy: FormShape
    shape.IForm.copy(&shapeCopy, shape)
    @assert(shapeCopy.subKind == .Highlight)
    @assert(shape.IForm.isSame(&shapeCopy))
    shapeCopy.roundSize += 1
    @assert(!shape.IForm.isSame(&shapeCopy))

    let text = captmeTestAddText(f.capture, 0, 0, 50, 60)
    text.fontSize = 34
    text.boldSize = 2
    text.joinStyle = .Bevel
    var textCopy: FormText
    text.IForm.copy(&textCopy, text)
    @assert(text.IForm.isSame(&textCopy))
    textCopy.fontSize += 1
    @assert(!text.IForm.isSame(&textCopy))

    let step = captmeTestAddStep(f.capture, 0, 0, 20, 30)
    step.kind = .RoundRectangle
    step.typeIndex = .LetterDown
    step.ws = 36
    step.hs = 44
    var stepCopy: FormStep
    step.IForm.copy(&stepCopy, step)
    @assert(stepCopy.ws == 36)
    @assert(stepCopy.hs == 44)
    @assert(step.IForm.isSame(&stepCopy))
    stepCopy.typeIndex = .LetterUp
    @assert(!step.IForm.isSame(&stepCopy))

    let line = captmeTestAddLine(f.capture, 0, 0, 10, 10, .PixSel)
    line.dashCap = .Round
    line.bezier = true
    line.paintShadow = false
    var lineCopy: FormLine
    line.IForm.copy(&lineCopy, line)
    @assert(lineCopy.subKind == .PixSel)
    @assert(lineCopy.paintShadow == false)
    @assert(line.IForm.isSame(&lineCopy))
    lineCopy.subKind = .Highlight
    @assert(!line.IForm.isSame(&lineCopy))

    var points: Array'Math.Vector2
    points.add({1, 1})
    points.add({20, 1})
    points.add({10, 20})

    let polygon = captmeTestAddPolygon(f.capture, points.toSlice(), .Highlight)
    polygon.paintShadow = false
    polygon.bezier = true
    var polygonCopy: FormPolygon
    polygon.IForm.copy(&polygonCopy, polygon)
    @assert(polygonCopy.subKind == .Highlight)
    @assert(polygonCopy.paintShadow == false)
    @assert(polygon.IForm.isSame(&polygonCopy))
    polygonCopy.subKind = .PixSel
    @assert(!polygon.IForm.isSame(&polygonCopy))

    let draw = captmeTestAddDraw(f.capture, points.toSlice(), .PixSel)
    draw.paintShadow = false
    var drawCopy: FormDraw
    draw.IForm.copy(&drawCopy, draw)
    @assert(drawCopy.subKind == .PixSel)
    @assert(drawCopy.paintShadow == false)
    @assert(draw.IForm.isSame(&drawCopy))
    drawCopy.paintShadow = true
    @assert(!draw.IForm.isSame(&drawCopy))

    let image = captmeTestAddImage(f.capture, 0, 0, 40, 50)
    image.kind = .Image
    image.strength = 77
    image.backColor = ColorRed
    var imageCopy: FormImage
    image.IForm.copy(&imageCopy, image)
    @assert(image.IForm.isSame(&imageCopy))
    imageCopy.backColor = ColorBlue
    @assert(!image.IForm.isSame(&imageCopy))
    image.kind = .Blur
    imageCopy.kind = .Blur
    @assert(image.IForm.isSame(&imageCopy))

    f.shutdown()
}
