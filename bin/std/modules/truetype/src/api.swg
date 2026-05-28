using Swag, Core

public func FT_Init_FreeType(alibrary: *FT_Library) throw
{
    if !alibrary do
        FreeTypePriv.fail(0x21)

    let lib = Memory.new'FT_LibraryRec()
    lib.version_major = 2
    lib.version_minor = 0
    lib.version_patch = 0
    dref alibrary = lib
}

public func FT_Done_FreeType(alibrary: FT_Library) throw
{
    if !alibrary do
        FreeTypePriv.fail(0x21)
    Memory.delete(alibrary)
}

public func FT_New_Memory_Face(library: FT_Library, file_base: const *FT_Byte, file_size: FT_Long, face_index: FT_Long, aface: *FT_Face) throw
{
    if !library do
        FreeTypePriv.fail(0x21)
    if !aface or !file_base or file_size <= 0 do
        FreeTypePriv.fail(0x06)
    if face_index != 0 do
        FreeTypePriv.fail(0x07)

    let faceData = Memory.new'FreeTypePriv.FaceImpl()
    faceData.fontData.resize(file_size)
    Memory.copy(faceData.fontData.buffer, file_base, cast(u64) file_size)
    FreeTypePriv.parseFace(faceData, library)
    dref aface = &faceData.faceRec
}

public func FT_Done_Face(face: FT_Face)
{
    if !face do
        return
    let faceData = cast(*FreeTypePriv.FaceImpl) face.finternal
    if faceData do
        Memory.delete(faceData)
}

public func FT_Set_Pixel_Sizes(face: FT_Face, pixel_width, pixel_height: FT_UInt) throw
{
    let faceData = FreeTypePriv.getFaceImpl(face)
    if !pixel_width and !pixel_height do
        FreeTypePriv.fail(0x17)

    var width  = pixel_width
    var height = pixel_height
    if !width do
        width = height
    if !height do
        height = width

    face.size.metrics.x_ppem       = cast(u16) width
    face.size.metrics.y_ppem       = cast(u16) height
    face.size.metrics.x_scale      = FreeTypePriv.scaleFixed(width, faceData.unitsPerEm)
    face.size.metrics.y_scale      = FreeTypePriv.scaleFixed(height, faceData.unitsPerEm)
    face.size.metrics.ascender     = FreeTypePriv.scale26_6(face.ascender, height, faceData.unitsPerEm)
    face.size.metrics.descender    = FreeTypePriv.scale26_6(face.descender, height, faceData.unitsPerEm)
    face.size.metrics.height       = FreeTypePriv.scale26_6(face.height, height, faceData.unitsPerEm)
    face.size.metrics.max_advance  = FreeTypePriv.scale26_6(face.max_advance_width, width, faceData.unitsPerEm)
}

public func FT_Get_Char_Index(face: FT_Face, charcode: FT_ULong)->FT_UInt
{
    let faceData = cast(*FreeTypePriv.FaceImpl) (face ? face.finternal : null)
    if !faceData do
        return 0
    let idx = catch FreeTypePriv.lookupGlyphIndex(faceData, charcode)
    return @err != null ? 0 : cast(FT_UInt) idx
}

public func FT_Load_Glyph(face: FT_Face, glyph_index: FT_UInt, load_flags: FT_Int32) throw
{
    FreeTypePriv.loadGlyphInternal(face, glyph_index)
    if load_flags & FT_LOAD_RENDER do
        FT_Render_Glyph(face.glyph, .FT_RENDER_MODE_NORMAL)
}

public func FT_Load_Char(face: FT_Face, char_code: FT_ULong, load_flags: FT_Int32) throw
{
    let faceData = FreeTypePriv.getFaceImpl(face)
    let glyphIndex = FreeTypePriv.lookupGlyphIndex(faceData, char_code)
    FT_Load_Glyph(face, glyphIndex, load_flags)
}

public func FT_Render_Glyph(slot: FT_GlyphSlot, render_mode: FT_Render_Mode) throw
{
    if render_mode != .FT_RENDER_MODE_NORMAL do
        FreeTypePriv.fail(0x07)
    FreeTypePriv.renderCurrentOutline(slot)
}

public func FT_Outline_Translate(outline: const *FT_Outline, xOffset, yOffset: FT_Pos)
{
    if !outline or outline.n_points <= 0 do
        return

    let points = cast([*] FT_Vector) outline.points
    for cast(u32) outline.n_points
    {
        points[@index].x += xOffset
        points[@index].y += yOffset
    }
}

public func FT_Outline_Transform(outline: const *FT_Outline, matrix: const *FT_Matrix)
{
    if !outline or !matrix or outline.n_points <= 0 do
        return

    let points = cast([*] FT_Vector) outline.points
    for cast(u32) outline.n_points
    {
        let pt = points[@index]
        points[@index].x = FreeTypePriv.roundDiv(cast(s64) pt.x * matrix.xx + cast(s64) pt.y * matrix.xy, 65536)
        points[@index].y = FreeTypePriv.roundDiv(cast(s64) pt.x * matrix.yx + cast(s64) pt.y * matrix.yy, 65536)
    }
}

public func FT_GlyphSlot_Oblique(slot: FT_GlyphSlot)
{
    if !slot or slot.outline.n_points <= 0 do
        return

    for cast(u32) slot.outline.n_points do
        slot.outline.points[@index].x += cast(s32) Math.round(slot.outline.points[@index].y * 0.21256)

    FreeTypePriv.updateSlotMetrics(slot)
}

public func FT_Outline_Embolden(outline: *FT_Outline, strength: FT_Pos) throw
{
    if !outline do
        FreeTypePriv.fail(0x14)
    if outline.n_points <= 0 or outline.n_contours <= 0 or !strength do
        return

    var start = 0'u32
    for cast(u32) outline.n_contours
    {
        let endIdx = cast(u32) outline.contours[@index]
        let slice  = @mkslice(outline.points + start, endIdx - start + 1)
        FreeTypePriv.applyEmboldenToContour(slice, strength)
        start = endIdx + 1
    }
}

public func FT_Outline_Decompose(outline: *FT_Outline, func_interface: const *FT_Outline_Funcs, user: *void) throw
{
    if !outline or !func_interface do
        FreeTypePriv.fail(0x14)

    let moveTo  = func_interface.move_to ? cast(FT_Outline_MoveToFunc) func_interface.move_to : null
    let lineTo  = func_interface.line_to ? cast(FT_Outline_LineToFunc) func_interface.line_to : null
    let conicTo = func_interface.conic_to ? cast(FT_Outline_ConicToFunc) func_interface.conic_to : null
    let unusedCubicTo = func_interface.cubic_to ? cast(FT_Outline_CubicToFunc) func_interface.cubic_to : null

    let commands = FreeTypePriv.buildOutlineCommands(outline)
    foreach cmd in commands
    {
        var res = 0
        switch cmd.kind
        {
        case 0:
            res = moveTo ? moveTo(&cmd.p0, user) : 0

        case 1:
            res = lineTo ? lineTo(&cmd.p0, user) : 0

        case 2:
            res = conicTo ? conicTo(&cmd.p0, &cmd.p1, user) : 0
        }

        if res != 0 do
            FreeTypePriv.fail(0x14)
    }
}

public func FT_Library_SetLcdFilter(library: FT_Library, filter: FT_LcdFilter) throw
{
    if !library do
        FreeTypePriv.fail(0x21)
    if filter < .FT_LCD_FILTER_NONE or filter >= .FT_LCD_FILTER_MAX do
        FreeTypePriv.fail(0x06)
}

public func FT_Library_SetLcdFilterWeights(library: FT_Library, weights: const *u8) throw
{
    if !library do
        FreeTypePriv.fail(0x21)
    if !weights do
        FreeTypePriv.fail(0x06)
}