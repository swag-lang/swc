#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var guid: GUID64
    @assert(guid.isNull())

    guid.guid = 0x0123456789ABCDEF'u64
    @assert(!guid.isNull())
    @assert(guid.getString() == "0123456789ABCDEF")
    @assert(GUID64.parse("0123456789ABCDEF") == guid)
    @assert(GUID64.parse("0x0123456789ABCDEF") == guid)
    @assert(GUID64.parse("A1zz").guid == 0xA1'u64)
    @assert(Hash.hash32(guid) == Hash.Crc32.compute(@mkslice(cast(const [*] u8) &guid.guid, #sizeof(u64))))

    guid.clear()
    @assert(guid.isNull())
}

#test
{
    var guid: GUID128
    guid.val8 = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x10, 0x32, 0x54, 0x76, 0x98, 0xBA, 0xDC, 0xFE]

    @assert(guid.getString() == "01234567-89ab-cdef-1032-547698badcfe")
    @assert(Hash.hash32(guid) == Hash.Crc32.compute(@mkslice(&guid.val8[0], 16)))

    var copy = guid
    @assert(copy == guid)

    copy.clear()
    @assert(copy != guid)
    @assert(copy.val64[0] == 0)
    @assert(copy.val64[1] == 0)
}

#test
{
    let guid = GUID128.getRandom()
    @assert((guid.val8[6] & 0xF0) == 0x40)
    @assert((guid.val8[8] & 0xC0) == 0x80)
}
