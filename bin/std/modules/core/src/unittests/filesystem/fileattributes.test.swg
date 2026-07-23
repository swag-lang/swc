#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
#global private

using Swag

func assertOnlyFileAttribute(value: u32, expected: File.FileAttributes)
{
    let attributes = File.FileAttributes.fromDWORD(value)
    @assert(attributes == expected)
    @assert(attributes.has(expected))
}

#test
{
    using File.FileAttributes

    @assert(File.FileAttributes.fromDWORD(0) == Zero)
    @assert(File.FileAttributes.fromDWORD(0xFFFF_FFFF'u32) == Zero)

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
    @assert(attributes.has(Directory))
    @assert(attributes.has(Archive))
    @assert(attributes.has(ReparsePoint))
    @assert(attributes.has(Encrypted))
    @assert(!attributes.has(ReadOnly))
    @assert(!attributes.has(Hidden))
    @assert(!attributes.has(System))
    @assert(!attributes.has(Device))
    @assert(!attributes.has(Normal))
    @assert(!attributes.has(Temporary))
    @assert(!attributes.has(SparseFile))
    @assert(!attributes.has(Compressed))
    @assert(!attributes.has(Offline))
    @assert(!attributes.has(NotContentIndexed))
}
