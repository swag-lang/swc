#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

func assertOnlyFileAttribute(value: u32, expected: File.FileAttributes)
{
    let attributes = File.FileAttributes.fromDWORD(value)
    Swag.assert(attributes == expected)
    Swag.assert(attributes.has(expected))
}

#test
{
    using File.FileAttributes

    Swag.assert(File.FileAttributes.fromDWORD(0) == None)
    Swag.assert(File.FileAttributes.fromDWORD(0xFFFF_FFFF'u32) == None)

    assertOnlyFileAttribute(0x0000_0001, ReadOnly)
    assertOnlyFileAttribute(0x0000_0002, Hidden)
    assertOnlyFileAttribute(0x0000_0004, System)
    assertOnlyFileAttribute(0x0000_0010, Directory)
    assertOnlyFileAttribute(0x0000_0020, Archive)
    assertOnlyFileAttribute(0x0000_0040, Device)
    assertOnlyFileAttribute(0x0000_0080, Normal)
    assertOnlyFileAttribute(0x0000_0100, Temporary)
    assertOnlyFileAttribute(0x0000_0200, SparseFile)
    assertOnlyFileAttribute(0x0000_0400, ReparsePoint)
    assertOnlyFileAttribute(0x0000_0800, Compressed)
    assertOnlyFileAttribute(0x0000_1000, Offline)
    assertOnlyFileAttribute(0x0000_2000, NotContentIndexed)
    assertOnlyFileAttribute(0x0000_4000, Encrypted)

    let attributes = File.FileAttributes.fromDWORD(0x0000_0010 | 0x0000_0020 | 0x0000_0400 | 0x0000_4000)
    Swag.assert(attributes.has(Directory))
    Swag.assert(attributes.has(Archive))
    Swag.assert(attributes.has(ReparsePoint))
    Swag.assert(attributes.has(Encrypted))
    Swag.assert(!attributes.has(ReadOnly))
    Swag.assert(!attributes.has(Hidden))
    Swag.assert(!attributes.has(System))
    Swag.assert(!attributes.has(Device))
    Swag.assert(!attributes.has(Normal))
    Swag.assert(!attributes.has(Temporary))
    Swag.assert(!attributes.has(SparseFile))
    Swag.assert(!attributes.has(Compressed))
    Swag.assert(!attributes.has(Offline))
    Swag.assert(!attributes.has(NotContentIndexed))
}
