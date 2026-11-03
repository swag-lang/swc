#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

func assertOnlyFileAttribute(value: u32, expected: File.FileAttributes)
{
    let attributes = File.FileAttributes.fromDWORD(value)
    Swag.require(attributes == expected)
    Swag.require(attributes.has(expected))
}

#test
{
    using File.FileAttributes

    Swag.require(File.FileAttributes.fromDWORD(0) == None)
    Swag.require(File.FileAttributes.fromDWORD(0xFFFF_FFFF'u32) == None)

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
    assertOnlyFileAttribute(0x0000_8000, IntegrityStream)
    assertOnlyFileAttribute(0x0002_0000, NoScrubData)
    assertOnlyFileAttribute(0x0004_0000, RecallOnOpen)
    assertOnlyFileAttribute(0x0008_0000, Pinned)
    assertOnlyFileAttribute(0x0010_0000, Unpinned)
    assertOnlyFileAttribute(0x0040_0000, RecallOnDataAccess)

    let attributes = File.FileAttributes.fromDWORD(0x0000_0010 | 0x0000_0020 | 0x0000_0400 | 0x0000_4000 |
                                                   0x0000_8000 | 0x0002_0000 | 0x0004_0000 | 0x0008_0000 |
                                                   0x0010_0000 | 0x0040_0000)
    Swag.require(attributes.has(Directory))
    Swag.require(attributes.has(Archive))
    Swag.require(attributes.has(ReparsePoint))
    Swag.require(attributes.has(Encrypted))
    Swag.require(attributes.has(IntegrityStream))
    Swag.require(attributes.has(NoScrubData))
    Swag.require(attributes.has(RecallOnOpen))
    Swag.require(attributes.has(Pinned))
    Swag.require(attributes.has(Unpinned))
    Swag.require(attributes.has(RecallOnDataAccess))
    Swag.require(not attributes.has(ReadOnly))
    Swag.require(not attributes.has(Hidden))
    Swag.require(not attributes.has(System))
    Swag.require(not attributes.has(Device))
    Swag.require(not attributes.has(Normal))
    Swag.require(not attributes.has(Temporary))
    Swag.require(not attributes.has(SparseFile))
    Swag.require(not attributes.has(Compressed))
    Swag.require(not attributes.has(Offline))
    Swag.require(not attributes.has(NotContentIndexed))
}

// Metadata queries translate a missing path into the same Core error.
#test
{
    let path = CoreTests.makeFilesystemTestPath("core_file_info_missing")

    var infoErrorOutcome: Swag.Error
    discard catch File.info(path.toString()) as infoErrorOutcome
    Swag.require(infoErrorOutcome.value() is Errors.FileNotFoundError)

    var attributesErrorOutcome: Swag.Error
    discard catch File.attributes(path.toString()) as attributesErrorOutcome
    Swag.require(attributesErrorOutcome.value() is Errors.FileNotFoundError)
}
