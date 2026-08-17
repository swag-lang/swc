#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var guid: Guid64
    @assert(guid.isNull())

    @assert(Guid64.tryParse("0123456789ABCDEF", &guid))
    @assert(!guid.isNull())
    @assert(guid.value == 0x0123456789ABCDEF'u64)
    @assert(guid.toString() == "0123456789ABCDEF")
    @assert((expect Guid64.parse("0123456789ABCDEF")) == guid)
    @assert((expect Guid64.parse("0x0123456789ABCDEF")) == guid)
    @assert(!Guid64.tryParse("A1zz", &guid))
    @assert(!Guid64.tryParse("0123456789ABCDE", &guid))
    @assert(!Guid64.tryParse("0123456789ABCDEG", &guid))
    @assert(Hash.hash32(guid) == Hash.Crc32.compute(@mkslice(cast(const [*] u8) &guid.value, #sizeof(u64))))

    guid.clear()
    @assert(guid.isNull())
}

#test
{
    var guid: Guid128
    @assert(Guid128.tryParse("01234567-89ab-cdef-1032-547698badcfe", &guid))

    @assert(guid.toString() == "01234567-89ab-cdef-1032-547698badcfe")
    @assert((expect Guid128.parse("01234567-89AB-CDEF-1032-547698BADCFE")) == guid)
    @assert(!Guid128.tryParse("0123456789ab-cdef-1032-547698badcfe", &guid))
    @assert(!Guid128.tryParse("01234567-89ab-cdef-1032-547698badcfz", &guid))
    @assert(Hash.hash32(guid) == Hash.Crc32.compute(@mkslice(&guid.bytes[0], 16)))

    var copy = guid
    @assert(copy == guid)

    copy.clear()
    @assert(copy != guid)
    @assert(copy.isNull())
}

#test
{
    let guid = Guid128.random()
    @assert((guid.bytes[6] & 0xF0) == 0x40)
    @assert((guid.bytes[8] & 0xC0) == 0x80)
}
