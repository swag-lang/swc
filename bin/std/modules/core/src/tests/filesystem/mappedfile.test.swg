#global if #command == Swag.CompilerCommand.Test
#global private

func mappedBytesEqual(actual: const [..] u8, expected: const [..] u8)->bool
{
    if actual.count != expected.count do
        return false
    for index in actual.count
    {
        if actual[index] != expected[index] do
            return false
    }

    return true
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_shared.tmp")
    defer discard catch File.delete(fileName)

    var source: [96 * 1024] u8
    for &value, index in source do
        value[] = cast(u8) (index % 251)
    discard expect File.writeAllBytes(fileName, source)

    var mapped = expect File.MappedFile.open(fileName, .ReadWrite)
    Swag.assert(expect mapped.size() == source.count)

    // The offset deliberately crosses the host allocation-granularity boundary so the public
    // slice starts after the internally aligned native view.
    var region   = expect mapped.map(64 * 1024 - 7, 32)
    let writable = region.writableBytes()
    writable[0]  = 0xA1
    writable[31] = 0xB2

    // A region owns the handles required by flush and remains usable after its source closes.
    mapped.close()
    Swag.assert(region.bytes()[0] == 0xA1)
    expect region.flush()
    region.close()

    let persisted = expect File.readAllBytes(fileName)
    Swag.assert(persisted[64 * 1024 - 7] == 0xA1)
    Swag.assert(persisted[64 * 1024 - 7 + 31] == 0xB2)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_private.tmp")
    defer discard catch File.delete(fileName)

    let original: [8] u8 = [1, 2, 3, 4, 5, 6, 7, 8]
    discard expect File.writeAllBytes(fileName, original)

    var mapped = expect File.MappedFile.open(fileName, .CopyOnWrite)
    var region = expect mapped.mapAll()
    region.writableBytes()[3] = 99
    expect region.flush()
    Swag.assert(region.bytes()[3] == 99)
    region.close()
    mapped.close()

    let persisted = expect File.readAllBytes(fileName)
    Swag.assert(mappedBytesEqual(persisted.toSlice(), original))
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_empty_and_resize.tmp")
    defer discard catch File.delete(fileName)
    var stream = expect File.openWrite(fileName)
    stream.close()

    var mapped = expect File.MappedFile.open(fileName, .ReadWrite)
    var empty  = expect mapped.map(0, 0)
    Swag.assert(empty.isOpen())
    Swag.assert((empty.bytes()).count == 0)
    empty.close()
    Swag.assert(!empty.isOpen())

    expect mapped.resize(8192)
    Swag.assert(expect mapped.size() == 8192)
    discard catch mapped.map(8190, 4) as rangeError
    Swag.assert(rangeError != null)

    var region = expect mapped.map(4096, 4096)
    region.writableBytes()[0] = 42
    region.close()
    expect mapped.resize(16 * 1024)
    Swag.assert(expect mapped.size() == 16 * 1024)
}

// Releasing the pages behind a walk is an accounting hint: the bytes read back unchanged, and
// an empty or unaligned range is accepted.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_release.tmp")
    defer discard catch File.delete(fileName)

    var source: [96 * 1024] u8
    for &value, index in source do
        value[] = cast(u8) (index % 239)
    discard expect File.writeAllBytes(fileName, source)

    var mapped = expect File.MappedFile.open(fileName)
    var region = expect mapped.mapAll()
    let bytes  = region.bytes()
    Swag.assert(mappedBytesEqual(bytes, source))

    File.MappedRegion.releasePages(bytes[0 until 0])
    File.MappedRegion.releasePages(bytes[1000 until 5000])
    File.MappedRegion.releasePages(bytes)
    Swag.assert(mappedBytesEqual(bytes, source))

    region.close()
    mapped.close()
}
