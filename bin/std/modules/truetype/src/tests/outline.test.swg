#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    var points: [3] FT_Vector = [{x: 0, y: 0}, {x: 64, y: 64}, {x: 128, y: 0}]
    var tags: [3] u8 = [1, 0, 1]
    var contours: [1] s16 = [2]

    var outline = FT_Outline{
        n_contours: 1,
        n_points:   3,
        points:     &points[0],
        tags:       &tags[0],
        contours:   &contours[0],
    }

    let commands = FreeTypePriv.buildOutlineCommands(&outline)
    @assert(commands.count == 3)
    @assert(commands[0].kind == 0)
    @assert(commands[1].kind == 2)
    @assert(commands[2].kind == 1)
}

#test
{
    discard catch FT_Outline_Decompose(null, null, null)
    @assert(@err != null)

    discard catch FT_Outline_Embolden(null, 64)
    @assert(@err != null)
}

#test
{
    withFace(func(_, _, face)
    {
        discard catch FT_Set_Pixel_Sizes(face, 0, 18)
        @assert(@err == null)

        discard catch FT_Load_Char(face, 'A''u32, FT_LOAD_NO_BITMAP)
        @assert(@err == null)
        @assert(face.glyph.outline.n_contours > 0)
        @assert(face.glyph.outline.n_points > 0)
        @assert(face.glyph.advance.x > 0)

        var funcs: FT_Outline_Funcs
        funcs.move_to  = cast(*void) &moveToCounter
        funcs.line_to  = cast(*void) &lineToCounter
        funcs.conic_to = cast(*void) &conicToCounter

        var counter: OutlineCounter
        discard catch FT_Outline_Decompose(&face.glyph.outline, &funcs, &counter)
        @assert(@err == null)
        @assert(counter.moves > 0)
        @assert(counter.lines + counter.conics > 0)

        let bounds0 = getOutlineBounds(&face.glyph.outline)
        FT_Outline_Translate(&face.glyph.outline, 64, 0)
        let bounds1 = getOutlineBounds(&face.glyph.outline)
        @assert(bounds1.xMin == bounds0.xMin + 64)
        @assert(bounds1.xMax == bounds0.xMax + 64)

        discard catch FT_Load_Char(face, 'A''u32, FT_LOAD_NO_BITMAP)
        @assert(@err == null)
        let transformIdx = findPointWithNonZeroY(&face.glyph.outline)
        let beforeTransformX = face.glyph.outline.points[transformIdx].x
        let beforeTransformY = face.glyph.outline.points[transformIdx].y
        let scaleY = FT_Matrix{xx: 65536, yy: 131072}
        FT_Outline_Transform(&face.glyph.outline, &scaleY)
        @assert(face.glyph.outline.points[transformIdx].x == beforeTransformX)
        @assert(face.glyph.outline.points[transformIdx].y == beforeTransformY * 2)

        discard catch FT_Load_Char(face, 'A''u32, FT_LOAD_NO_BITMAP)
        @assert(@err == null)
        let bounds2 = getOutlineBounds(&face.glyph.outline)
        discard catch FT_Outline_Embolden(&face.glyph.outline, 64)
        @assert(@err == null)
        let bounds3 = getOutlineBounds(&face.glyph.outline)
        @assert(bounds3.xMax - bounds3.xMin >= bounds2.xMax - bounds2.xMin)

        discard catch FT_Load_Char(face, 'A''u32, FT_LOAD_NO_BITMAP)
        @assert(@err == null)
        let sampleIdx = findPointWithNonZeroY(&face.glyph.outline)
        let sampleBeforeX = face.glyph.outline.points[sampleIdx].x
        let sampleBeforeY = face.glyph.outline.points[sampleIdx].y
        FT_GlyphSlot_Oblique(face.glyph)
        @assert(face.glyph.outline.points[sampleIdx].x == sampleBeforeX + cast(s32) Math.round(sampleBeforeY * 0.21256))
    })
}
