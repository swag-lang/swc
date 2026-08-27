#global if #command == Swag.CompilerCommand.Test
#global private

func mappedBytesEqual(actual: const [..] u8, expected: const [..] u8)->bool
{
    if @countof(actual) != @countof(expected) do
        return false
    for actual
    {
        if actual[@index] != expected[@index] do
            return false
    }

    return true
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_shared.tmp")
    defer discard catch File.delete(fileName)

    var source: [96 * 1024] u8
    for &value in source do
        value[] = cast(u8) (@index % 251)
    discard expect File.writeAllBytes(fileName, source)

    var mapped = expect File.MappedFile.open(fileName, .ReadWrite)
    @assert(expect mapped.size() == @countof(source))

    // The offset deliberately crosses the host allocation-granularity boundary so the public
    // slice starts after the internally aligned native view.
    var region   = expect mapped.map(64 * 1024 - 7, 32)
    let writable = region.writableBytes()
    writable[0]  = 0xA1
    writable[31] = 0xB2

    // A region owns the handles required by flush and remains usable after its source closes.
    mapped.close()
    @assert(region.bytes()[0] == 0xA1)
    expect region.flush()
    region.close()

    let persisted = expect File.readAllBytes(fileName)
    @assert(persisted[64 * 1024 - 7] == 0xA1)
    @assert(persisted[64 * 1024 - 7 + 31] == 0xB2)
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
    @assert(region.bytes()[3] == 99)
    region.close()
    mapped.close()

    let persisted = expect File.readAllBytes(fileName)
    @assert(mappedBytesEqual(persisted.toSlice(), original))
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_empty_and_resize.tmp")
    defer discard catch File.delete(fileName)
    var stream = expect File.openWrite(fileName)
    stream.close()

    var mapped = expect File.MappedFile.open(fileName, .ReadWrite)
    var empty  = expect mapped.map(0, 0)
    @assert(empty.isOpen())
    @assert(@countof(empty.bytes()) == 0)
    empty.close()
    @assert(!empty.isOpen())

    expect mapped.resize(8192)
    @assert(expect mapped.size() == 8192)
    discard catch mapped.map(8190, 4) as rangeError
    @assert(rangeError != null)

    var region = expect mapped.map(4096, 4096)
    region.writableBytes()[0] = 42
    region.close()
    expect mapped.resize(16 * 1024)
    @assert(expect mapped.size() == 16 * 1024)
}

// Releasing the pages behind a walk is an accounting hint: the bytes read back unchanged, and
// an empty or unaligned range is accepted.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_mapped_file_release.tmp")
    defer discard catch File.delete(fileName)

    var source: [96 * 1024] u8
    for &value in source do
        value[] = cast(u8) (@index % 239)
    discard expect File.writeAllBytes(fileName, source)

    var mapped = expect File.MappedFile.open(fileName)
    var region = expect mapped.mapAll()
    let bytes  = region.bytes()
    @assert(mappedBytesEqual(bytes, source))

    File.MappedRegion.releasePages(bytes[0 until 0])
    File.MappedRegion.releasePages(bytes[1000 until 5000])
    File.MappedRegion.releasePages(bytes)
    @assert(mappedBytesEqual(bytes, source))

    region.close()
    mapped.close()
}
