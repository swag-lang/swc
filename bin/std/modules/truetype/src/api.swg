using Swag, Core

public impl Library
{
    func create()->Library
    {
        var result: retval
        result.init()
        return result
    }

    mtd init()
    {
        .versionMajor = 2
        .versionMinor = 0
        .versionPatch = 0
    }

    mtd loadFace(bytes: const [..] u8, faceIndex: u32 = 0)->*Face throw
    {
        if @countof(bytes) == 0 do
            fail(0x06)
        if faceIndex != 0 do
            fail(0x07)

        let faceData = Memory.new'FaceImpl()
        faceData.fontData.resize(@countof(bytes))
        Memory.copy(faceData.fontData.buffer, @dataof(bytes), @countof(bytes))
        parseFace(faceData)
        return &faceData.face
    }

    mtd setLcdFilter(filter: LcdFilter) throw
    {
        if filter < .None or filter >= .Max do
            fail(0x06)
    }

    mtd setLcdFilterWeights(weights: const [..] u8) throw
    {
        if @countof(weights) == 0 do
            fail(0x06)
    }
}

public impl Face
{
    mtd destroy()
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        if faceData do
            Memory.delete(faceData)
    }

    mtd const isBold()->bool => .style.has(.Bold)

    mtd const isItalic()->bool => .style.has(.Italic)

    mtd setPixelSize(pixelWidth, pixelHeight: u32) throw
    {
        let faceData = getFaceImpl(me)
        if !pixelWidth and !pixelHeight do
            fail(0x17)

        var width  = pixelWidth
        var height = pixelHeight
        if !width do
            width = height
        if !height do
            height = width

        .size.metrics.xPpem      = cast(u16) width
        .size.metrics.yPpem      = cast(u16) height
        .size.metrics.xScale     = scaleFixed(width, faceData.unitsPerEm)
        .size.metrics.yScale     = scaleFixed(height, faceData.unitsPerEm)
        .size.metrics.ascender   = scale26_6(.ascender, height, faceData.unitsPerEm)
        .size.metrics.descender  = scale26_6(.descender, height, faceData.unitsPerEm)
        .size.metrics.height     = scale26_6(.height, height, faceData.unitsPerEm)
        .size.metrics.maxAdvance = scale26_6(.maxAdvanceWidth, width, faceData.unitsPerEm)
    }

    mtd glyphIndex(charCode: rune)->u32
    {
        let faceData = cast(*FaceImpl) cast(*void) me
        if !faceData do
            return 0
        let idx = catch lookupGlyphIndex(faceData, cast(u32) charCode)
        return @err != null ? 0 : idx
    }

    mtd loadGlyph(glyphIndex: u32, loadFlags = LoadFlag.Default) throw
    {
        loadGlyphInternal(me, glyphIndex)
        if loadFlags & .Render do
            .renderGlyph()
    }

    mtd loadChar(charCode: rune, loadFlags = LoadFlag.Default) throw
    {
        let faceData = getFaceImpl(me)
        let idx = lookupGlyphIndex(faceData, cast(u32) charCode)
        .loadGlyph(idx, loadFlags)
    }

    mtd renderGlyph(renderMode = RenderMode.Normal) throw
    {
        if renderMode != .Normal do
            fail(0x07)
        renderCurrentOutline(&.glyph)
    }
}

public impl Outline
{
    mtd translate(xOffset, yOffset: s32)
    {
        if .pointCount <= 0 do
            return

        for cast(u32) .pointCount
        {
            .points[@index].x += xOffset
            .points[@index].y += yOffset
        }
    }

    mtd transform(matrix: Matrix)
    {
        if .pointCount <= 0 do
            return

        for cast(u32) .pointCount
        {
            let pt = .points[@index]
            .points[@index].x = roundDiv(cast(s64) pt.x * matrix.xx + cast(s64) pt.y * matrix.xy, 65536)
            .points[@index].y = roundDiv(cast(s64) pt.x * matrix.yx + cast(s64) pt.y * matrix.yy, 65536)
        }
    }

    mtd embolden(strength: s32) throw
    {
        if .pointCount <= 0 or .contourCount <= 0 or !strength do
            return

        var start = 0'u32
        for cast(u32) .contourCount
        {
            let endIdx = cast(u32) .contours[@index]
            let slice  = @mkslice(.points + start, endIdx - start + 1)
            applyEmboldenToContour(slice, strength)
            start = endIdx + 1
        }
    }

    mtd const decompose()->Array'OutlineCommand => buildOutlineCommands(me)
}

public impl GlyphSlot
{
    mtd oblique()
    {
        if .outline.pointCount <= 0 do
            return

        for cast(u32) .outline.pointCount do
            .outline.points[@index].x += cast(s32) Math.round(.outline.points[@index].y * 0.21256)

        updateSlotMetrics(me)
    }
}
