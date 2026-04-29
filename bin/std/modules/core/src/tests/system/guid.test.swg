#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

func expectBytes(actual: [..] u8, expected: string)
{
    @assert(@countof(actual) == @countof(expected))
    for i in @countof(expected) do
        @assert(actual[i] == expected[i])
}

#test
{
    var guid = GUID64{0x0123456789ABCDEF}
    @assert(!guid.isNull())

    var buffer: [16] u8 = undefined
    guid.toString(buffer)
    expectBytes(buffer, "0123456789ABCDEF")

    @assert(GUID64.parse("0123456789ABCDEF").guid == 0x0123456789ABCDEF)
    @assert(GUID64.parse("0x0123456789abcdef").guid == 0x0123456789ABCDEF)
    @assert(GUID64.parse("0123456789ABCDEF-more").guid == 0x0123456789ABCDEF)
    @assert(GUID64.parse("012Z").guid == 0x012)

    guid.clear()
    @assert(guid.isNull())
}

#test
{
    var guid: GUID128 = undefined
    guid.val8[0]  = 0x12
    guid.val8[1]  = 0x34
    guid.val8[2]  = 0x56
    guid.val8[3]  = 0x78
    guid.val8[4]  = 0x9A
    guid.val8[5]  = 0xBC
    guid.val8[6]  = 0xDE
    guid.val8[7]  = 0xF0
    guid.val8[8]  = 0x01
    guid.val8[9]  = 0x23
    guid.val8[10] = 0x45
    guid.val8[11] = 0x67
    guid.val8[12] = 0x89
    guid.val8[13] = 0xAB
    guid.val8[14] = 0xCD
    guid.val8[15] = 0xEF

    var same = guid
    @assert(guid == same)
    same.val8[15] = 0xEE
    @assert(guid != same)

    var buffer: [36] u8 = undefined
    guid.toString(buffer)
    expectBytes(buffer, "12345678-9abc-def0-0123-456789abcdef")

    guid.clear()
    @assert(guid.val64[0] == 0)
    @assert(guid.val64[1] == 0)
}
