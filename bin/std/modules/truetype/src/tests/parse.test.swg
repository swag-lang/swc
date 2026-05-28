#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    let valueU16 = catch FreeTypePriv.readU16(ReaderBytes, 0)
    @assert(@err == null)
    @assert(valueU16 == 0x1234)

    let valueS16 = catch FreeTypePriv.readS16(ReaderBytes, 2)
    @assert(@err == null)
    @assert(valueS16 == -128)

    let valueU32 = catch FreeTypePriv.readU32(ReaderBytes, 0)
    @assert(@err == null)
    @assert(valueU32 == 0x1234FF80)

    let valueS32 = catch FreeTypePriv.readS32(ReaderS32Bytes, 0)
    @assert(@err == null)
    @assert(valueS32 == -128)

    let valueF2Dot14 = catch FreeTypePriv.readF2Dot14(FixedPointBytes, 0)
    @assert(@err == null)
    @assert(Math.abs(valueF2Dot14 - 0.5) < 0.0001)

    discard catch FreeTypePriv.assertRange(ReaderBytes, 0, 16)
    @assert(@err != null)
}

#test
{
    withLibrary(func(library)
    {
        var face: FT_Face

        discard catch FT_New_Memory_Face(library, &BrokenFontBytes[0], cast(FT_Long) @countof(BrokenFontBytes), 0, &face)
        @assert(@err != null)

        discard catch FT_New_Memory_Face(library, null, 12, 0, &face)
        @assert(@err != null)

        let bytes = loadFontBytes()
        discard catch FT_New_Memory_Face(library, bytes.buffer, cast(FT_Long) bytes.count, 1, &face)
        @assert(@err != null)
    })
}
