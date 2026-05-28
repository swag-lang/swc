using Swag, Core

moduleprivate namespace FreeTypePriv
{
    const TAG_CMAP = FT_IMAGE_TAG('c''u32, 'm''u32, 'a''u32, 'p''u32)
    const TAG_GLYF = FT_IMAGE_TAG('g''u32, 'l''u32, 'y''u32, 'f''u32)
    const TAG_HEAD = FT_IMAGE_TAG('h''u32, 'e''u32, 'a''u32, 'd''u32)
    const TAG_HHEA = FT_IMAGE_TAG('h''u32, 'h''u32, 'e''u32, 'a''u32)
    const TAG_HMTX = FT_IMAGE_TAG('h''u32, 'm''u32, 't''u32, 'x''u32)
    const TAG_LOCA = FT_IMAGE_TAG('l''u32, 'o''u32, 'c''u32, 'a''u32)
    const TAG_MAXP = FT_IMAGE_TAG('m''u32, 'a''u32, 'x''u32, 'p''u32)
    const TAG_NAME = FT_IMAGE_TAG('n''u32, 'a''u32, 'm''u32, 'e''u32)
    const TAG_POST = FT_IMAGE_TAG('p''u32, 'o''u32, 's''u32, 't''u32)

    const CURVE_TAG_ON = 0x01'u8
    const OVERSAMPLE   = 4'u32
    const MAX_RECURSE  = 16'u32

    const CMP_ARG_1_AND_2_ARE_WORDS    = 0x0001'u16
    const CMP_ARGS_ARE_XY_VALUES       = 0x0002'u16
    const CMP_WE_HAVE_A_SCALE          = 0x0008'u16
    const CMP_MORE_COMPONENTS          = 0x0020'u16
    const CMP_WE_HAVE_AN_XY_SCALE      = 0x0040'u16
    const CMP_WE_HAVE_A_2X2            = 0x0080'u16
    const CMP_WE_HAVE_INSTRUCTIONS     = 0x0100'u16

    const NAME_ID_FAMILY = 1'u16
    const NAME_ID_STYLE  = 2'u16

    struct TableRecord
    {
        tag:        u32
        offset:     u32
        length:     u32
    }

    struct GlyphMetric
    {
        advanceWidth:        u16
        leftSideBearing:     s16
    }

    struct DesignPoint
    {
        x:           f64
        y:           f64
        onCurve:     bool
    }

    struct OutlineCommand
    {
        kind:     s32
        p0:       FT_Vector
        p1:       FT_Vector
        p2:       FT_Vector
    }

    struct Edge
    {
        x0:       f64
        y0:       f64
        x1:       f64
        y1:       f64
        minY:     f64
        maxY:     f64
    }

    struct FaceImpl
    {
        faceRec:             FT_FaceRec
        glyphRec:            FT_GlyphSlotRec
        sizeRec:             FT_SizeRec
        charMapRec:          FT_CharMapRec

        fontData:            Array'u8
        tables:              Array'TableRecord
        glyphMetrics:        Array'GlyphMetric
        glyphLocations:      Array'u32
        chosenCMap:          const [..] u8
        cmapFormat:          u16
        unitsPerEm:          u16
        numLongMetrics:      u16
        lineGap:             s16
        macStyle:            u16
        indexToLocFormat:    s16

        familyName:          String
        styleName:           String

        outlinePoints:       Array'FT_Vector
        outlineTags:         Array'u8
        outlineContours:     Array's16
        bitmapPixels:        Array'u8
    }

    impl FaceImpl
    {
        mtd opDrop()
        {
            .fontData.clear()
            .tables.clear()
            .glyphMetrics.clear()
            .glyphLocations.clear()
            .outlinePoints.clear()
            .outlineTags.clear()
            .outlineContours.clear()
            .bitmapPixels.clear()
        }
    }

    func fail(code: u8) throw
    {
        let msg = Errors[code]
        throw SystemError{msg ? msg : "freetype error"}
    }

    func assertRange(buffer: const [..] u8, offset, length: u64) throw
    {
        if offset + length > @countof(buffer) do
            fail(0x03)
    }

    func getSlice(buffer: const [..] u8, offset, length: u64)->const [..] u8 throw
    {
        assertRange(buffer, offset, length)
        return @mkslice(@dataof(buffer) + offset, length)
    }

    func readU8(buffer: const [..] u8, offset: u64)->u8 throw
    {
        assertRange(buffer, offset, 1)
        return buffer[offset]
    }

    func readU16(buffer: const [..] u8, offset: u64)->u16 throw
    {
        assertRange(buffer, offset, 2)
        return cast(u16) buffer[offset] << 8 | buffer[offset + 1]
    }

    func readS16(buffer: const [..] u8, offset: u64)->s16 throw
    {
        let value = readU16(buffer, offset)
        if value <= 0x7FFF do
            return cast(s16) value
        return cast(s16) (cast(s32) value - 0x1_0000)
    }

    func readU32(buffer: const [..] u8, offset: u64)->u32 throw
    {
        assertRange(buffer, offset, 4)
        return cast(u32) buffer[offset] << 24 | cast(u32) buffer[offset + 1] << 16 | cast(u32) buffer[offset + 2] << 8 | buffer[offset + 3]
    }

    func readS32(buffer: const [..] u8, offset: u64)->s32 throw
    {
        let value = readU32(buffer, offset)
        if value <= 0x7FFF_FFFF do
            return cast(s32) value
        return cast(s32) (cast(s64) value - 0x1_0000_0000)
    }

    func readF2Dot14(buffer: const [..] u8, offset: u64)->f64 throw
    {
        return readS16(buffer, offset) / 16384.0
    }

    func roundDiv(value, divisor: s64)->s32
    {
        if !divisor do
            return 0
        if value >= 0 do
            return cast(s32) ((value + divisor / 2) / divisor)
        return cast(s32) -(((-value) + divisor / 2) / divisor)
    }

    func scaleFixed(ppem, unitsPerEm: u32)->s32
    {
        return roundDiv(cast(s64) ppem * 64 * 65536, unitsPerEm)
    }

    func scale26_6(value: s32, ppem, unitsPerEm: u32)->s32
    {
        return roundDiv(cast(s64) value * cast(s64) ppem * 64, unitsPerEm)
    }

    func getFaceImpl(face: FT_Face)->*FaceImpl throw
    {
        if !face do
            fail(0x23)
        let faceData = cast(*FaceImpl) face.finternal
        if !faceData do
            fail(0x23)
        return faceData
    }

    func getSlotImpl(slot: FT_GlyphSlot)->*FaceImpl throw
    {
        if !slot do
            fail(0x25)
        return getFaceImpl(slot.face)
    }

    func findTable(faceData: *FaceImpl, tag: u32)->const *TableRecord
    {
        foreach it in faceData.tables
        {
            if it.tag == tag do
                return &it
        }

        return null
    }

    func getTableSlice(faceData: *FaceImpl, tag: u32, missingCode: u8)->const [..] u8 throw
    {
        let rec = findTable(faceData, tag)
        if !rec do
            fail(missingCode)
        return getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    }


}
