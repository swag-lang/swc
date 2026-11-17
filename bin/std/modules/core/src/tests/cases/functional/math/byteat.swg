#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    #static if #safety(Swag.SafetyWhat.BoundCheck)
    {
        var byteIndex = Time.monotonicMilliseconds() + 1
        var wordIndex = Time.monotonicMilliseconds() + 8
        let byteFailure = Swag.catchPanic(func|&byteIndex|() { discard Math.byteAt(0xA5'u8, byteIndex) })
        let wordFailure = Swag.catchPanic(func|&wordIndex|() { discard Math.byteAt(0x0123456789ABCDEF'u64, wordIndex) })

        Swag.require(byteFailure.raised and byteFailure.message() == "byte index is out of range")
        Swag.require(wordFailure.raised and wordFailure.message() == "byte index is out of range")
    }
}
