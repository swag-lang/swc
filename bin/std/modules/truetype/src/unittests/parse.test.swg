#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let valueU16 = catch readU16(ReaderBytes, 0) as err
    @assert(err == null)
    @assert(valueU16 == 0x1234)

    let valueS16 = catch readS16(ReaderBytes, 2) as err2
    @assert(err2 == null)
    @assert(valueS16 == -128)

    let valueU32 = catch readU32(ReaderBytes, 0) as err3
    @assert(err3 == null)
    @assert(valueU32 == 0x1234FF80)

    let valueS32 = catch readS32(ReaderS32Bytes, 0) as err4
    @assert(err4 == null)
    @assert(valueS32 == -128)

    let valueF2Dot14 = catch readF2Dot14(FixedPointBytes, 0) as err5
    @assert(err5 == null)
    @assert(Math.abs(valueF2Dot14 - 0.5) < 0.0001)

    discard catch assertRange(ReaderBytes, 0, 16) as err6
    @assert(err6 != null)
}

#test
{
    let badFace0: #null *Face = catch Face.load(BrokenFontBytes) as err7
    @assert(err7 != null)

    var empty:    Array'u8
    let badFace1: #null *Face = catch Face.load(empty.toSlice()) as err8
    @assert(err8 != null)

    let bytes                 = loadFontBytes()
    let badFace2: #null *Face = catch Face.load(bytes.toSlice(), 1) as err9
    @assert(err9 != null)
}
