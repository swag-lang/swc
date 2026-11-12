#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let valueU16 = expect readU16(ReaderBytes, 0)
    Swag.require(valueU16 == 0x1234)

    let valueS16 = expect readS16(ReaderBytes, 2)
    Swag.require(valueS16 == -128)

    let valueU32 = expect readU32(ReaderBytes, 0)
    Swag.require(valueU32 == 0x1234FF80)

    let valueS32 = expect readS32(ReaderS32Bytes, 0)
    Swag.require(valueS32 == -128)

    let valueF2Dot14 = expect readF2Dot14(FixedPointBytes, 0)
    Swag.require(Math.abs(valueF2Dot14 - 0.5) < 0.0001)

    var err6Outcome: Swag.Error
    discard catch assertRange(ReaderBytes, 0, 16) as err6Outcome
    let err6 = err6Outcome.value()
    Swag.require(err6 != null)

    var errOverflowOutcome: Swag.Error
    discard catch assertRange(ReaderBytes, Swag.U64.Max, 1) as errOverflowOutcome
    let errOverflow = errOverflowOutcome.value()
    Swag.require(errOverflow != null)
}

#test
{
    Swag.require(peekU16(ReaderBytes, Swag.U64.Max) == 0)
    Swag.require(peekU16(ReaderBytes, Swag.U64.Max - 1) == 0)
    Swag.require(peekU24(ReaderBytes, Swag.U64.Max) == 0)
    Swag.require(peekU24(ReaderBytes, Swag.U64.Max - 1) == 0)
    Swag.require(peekU32(ReaderBytes, Swag.U64.Max) == 0)
    Swag.require(peekU32(ReaderBytes, Swag.U64.Max - 3) == 0)
}

// A CFF real without its terminating nibble fails instead of reading zero bytes forever.
#test
{
    const UnterminatedReal: [2] u8 = [30, 0x12]
    var rejected: Swag.Error
    discard catch parseCffDict(UnterminatedReal) as rejected
    let error = rejected.value()
    Swag.require(error != null)
}

#test
{
    var err7Outcome: Swag.Error
    catch checkFaceLoad(BrokenFontBytes) as err7Outcome
    let err7 = err7Outcome.value()
    Swag.require(err7 != null)

    var empty:       Array'u8
    var err8Outcome: Swag.Error
    catch checkFaceLoad(empty.toSlice()) as err8Outcome
    let err8 = err8Outcome.value()
    Swag.require(err8 != null)
}
