#global #if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    let valueU16 = catch readU16(ReaderBytes, 0)
    @assert(@err == null)
    @assert(valueU16 == 0x1234)

    let valueS16 = catch readS16(ReaderBytes, 2)
    @assert(@err == null)
    @assert(valueS16 == -128)

    let valueU32 = catch readU32(ReaderBytes, 0)
    @assert(@err == null)
    @assert(valueU32 == 0x1234FF80)

    let valueS32 = catch readS32(ReaderS32Bytes, 0)
    @assert(@err == null)
    @assert(valueS32 == -128)

    let valueF2Dot14 = catch readF2Dot14(FixedPointBytes, 0)
    @assert(@err == null)
    @assert(Math.abs(valueF2Dot14 - 0.5) < 0.0001)

    discard catch assertRange(ReaderBytes, 0, 16)
    @assert(@err != null)
}

#test
{
    discard catch Face.load(BrokenFontBytes)
    @assert(@err != null)

    var empty: Array'u8
    discard catch Face.load(empty.toSlice())
    @assert(@err != null)

    let bytes = loadFontBytes()
    discard catch Face.load(bytes.toSlice(), 1)
    @assert(@err != null)
}
