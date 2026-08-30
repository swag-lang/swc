#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let valueU16 = expect readU16(ReaderBytes, 0)
    Swag.assert(valueU16 == 0x1234)

    let valueS16 = expect readS16(ReaderBytes, 2)
    Swag.assert(valueS16 == -128)

    let valueU32 = expect readU32(ReaderBytes, 0)
    Swag.assert(valueU32 == 0x1234FF80)

    let valueS32 = expect readS32(ReaderS32Bytes, 0)
    Swag.assert(valueS32 == -128)

    let valueF2Dot14 = expect readF2Dot14(FixedPointBytes, 0)
    Swag.assert(Math.abs(valueF2Dot14 - 0.5) < 0.0001)

    discard catch assertRange(ReaderBytes, 0, 16) as err6
    Swag.assert(err6 != null)
}

#test
{
    let badFace0: #null *Face = catch Face.load(BrokenFontBytes) as err7
    Swag.assert(err7 != null)

    var empty:    Array'u8
    let badFace1: #null *Face = catch Face.load(empty.toSlice()) as err8
    Swag.assert(err8 != null)
}
