#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var guid: Guid64
    Swag.assert(guid.isNull())

    Swag.assert(Guid64.tryParse("0123456789ABCDEF", &guid))
    Swag.assert(!guid.isNull())
    Swag.assert(guid.value == 0x0123456789ABCDEF'u64)
    Swag.assert(guid.toString() == "0123456789ABCDEF")
    Swag.assert((expect Guid64.parse("0123456789ABCDEF")) == guid)
    Swag.assert((expect Guid64.parse("0x0123456789ABCDEF")) == guid)
    Swag.assert(!Guid64.tryParse("A1zz", &guid))
    Swag.assert(!Guid64.tryParse("0123456789ABCDE", &guid))
    Swag.assert(!Guid64.tryParse("0123456789ABCDEG", &guid))
    Swag.assert(Hash.hash32(guid) == Hash.Crc32.compute(Swag.makeSlice(cast(const [*] u8) &guid.value, #sizeof(u64))))

    guid.clear()
    Swag.assert(guid.isNull())
}

#test
{
    var guid: Guid128
    Swag.assert(Guid128.tryParse("01234567-89ab-cdef-1032-547698badcfe", &guid))

    Swag.assert(guid.toString() == "01234567-89ab-cdef-1032-547698badcfe")
    Swag.assert((expect Guid128.parse("01234567-89AB-CDEF-1032-547698BADCFE")) == guid)
    Swag.assert(!Guid128.tryParse("0123456789ab-cdef-1032-547698badcfe", &guid))
    Swag.assert(!Guid128.tryParse("01234567-89ab-cdef-1032-547698badcfz", &guid))
    Swag.assert(Hash.hash32(guid) == Hash.Crc32.compute(Swag.makeSlice(&guid.bytes[0], 16)))

    var copy = guid
    Swag.assert(copy == guid)

    copy.clear()
    Swag.assert(copy != guid)
    Swag.assert(copy.isNull())
}

#test
{
    let guid = Guid128.random()
    Swag.assert((guid.bytes[6] & 0xF0) == 0x40)
    Swag.assert((guid.bytes[8] & 0xC0) == 0x80)
}
