#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core.Errors

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_encoded_text.tmp")
    defer discard catch File.delete(fileName)

    let utf16Bytes   = expect File.writeAllText(fileName, "A€", encoding: .Utf16Be, includeBom: true)
    let utf16Expected: [6] u8 = [0xFE, 0xFF, 0, 'A', 0x20, 0xAC]
    let writtenUtf16 = expect File.readAllBytes(fileName)
    Swag.require(utf16Bytes == utf16Expected.count)
    Swag.require(Slice.equals(writtenUtf16.toSlice(), utf16Expected))

    let windowsBytes   = expect File.writeAllText(fileName, "café €", encoding: .Windows1252, includeBom: true)
    let windowsExpected: [6] u8 = ['c', 'a', 'f', 0xE9, ' ', 0x80]
    let writtenWindows = expect File.readAllBytes(fileName)
    Swag.require(windowsBytes == windowsExpected.count)
    Swag.require(Slice.equals(writtenWindows.toSlice(), windowsExpected))
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_encoding_failure.tmp")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "keep this content")

    var encodingFailure: Swag.Error
    discard catch File.writeAllText(fileName, "😀", encoding: .Windows1252) as encodingFailure
    Swag.require(encodingFailure.value() is InvalidFormatError)
    Swag.require((expect File.readAllText(fileName)) == "keep this content")
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_read_encoded_text.tmp")
    defer discard catch File.delete(fileName)

    discard expect File.writeAllText(fileName, "A€", encoding: .Utf16Be, includeBom: true)
    Swag.require((expect File.readAllText(fileName, encoding: .Utf16Be)) == "A€")

    discard expect File.writeAllText(fileName, "café €", encoding: .Windows1252)
    Swag.require((expect File.readAllText(fileName, encoding: .Windows1252)) == "café €")
}

#test
{
    let missing = CoreTests.makeFilesystemTestPath("core_file_read_encoded_missing.tmp")
    var errorOutcome: Swag.Error
    discard catch File.readAllText(missing, encoding: .Utf16Be) as errorOutcome
    Swag.require(errorOutcome.value() is Errors.FileNotFoundError)
}

// Both backends reject empty and unknown access or sharing flags.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_invalid_access.tmp")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "data")

    var rejected: Swag.Error
    discard catch File.open(fileName, .Open, cast(File.FileAccess, 0), .Read) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch File.open(fileName, .Open, File.FileAccess.Read | cast(File.FileAccess, 4), .Read) as rejected
    Swag.require(rejected.value() is BadParameterError)
    discard catch File.open(fileName, .Open, .Read, .Read | cast(File.FileShare, 128)) as rejected
    Swag.require(rejected.value() is BadParameterError)
}

// Create and Truncate reject read-only access before touching the path on both platforms.
#test
{
    let missing  = CoreTests.makeFilesystemTestPath("core_file_read_only_create.tmp")
    let existing = CoreTests.makeFilesystemTestPath("core_file_read_only_truncate.tmp")
    defer discard catch File.delete(missing)
    defer discard catch File.delete(existing)
    discard expect File.writeAllText(existing, "keep this content")

    for mode in [File.FileMode.Create, .Truncate]
    {
        var rejected: Swag.Error
        discard catch File.open(missing, mode, .Read, .Zero) as rejected
        Swag.require(rejected.value() is BadParameterError)
        Swag.require(not File.exists(missing))

        discard catch File.open(existing, mode, .Read, .Zero) as rejected
        Swag.require(rejected.value() is BadParameterError)
        Swag.require((expect File.readAllText(existing)) == "keep this content")
    }
}

// CreateNew and OpenOrCreate can create a file through a read-only handle.
#test
{
    let createNewPath    = CoreTests.makeFilesystemTestPath("core_file_read_only_create_new.tmp")
    let openOrCreatePath = CoreTests.makeFilesystemTestPath("core_file_read_only_open_or_create.tmp")
    defer discard catch File.delete(createNewPath)
    defer discard catch File.delete(openOrCreatePath)

    var createNew = expect File.open(createNewPath, .CreateNew, .Read, .Zero)
    createNew.close()
    Swag.require(File.exists(createNewPath))

    var openOrCreate = expect File.open(openOrCreatePath, .OpenOrCreate, .Read, .Zero)
    openOrCreate.close()
    Swag.require(File.exists(openOrCreatePath))
}

// Live readers leave no idle handle and follow replacements without losing their cursor.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_live.tmp")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "first line\nsecond line\n")
    var stream = expect File.openReadLive(fileName)
    let first  = expect stream.readUtf8Chunk(6)
    Swag.require(first == "first " and expect stream.position() == 6)

    discard expect File.writeAllText(fileName, "other replacement\n")
    let next = expect stream.readUtf8Chunk(11)
    Swag.require(next == "replacement")
    expect stream.seek(.End, cast #bit (u64, -1's64))
    let ending = expect stream.readUtf8Chunk(4)
    Swag.require(ending == "\n")

    let replacement = CoreTests.makeFilesystemTestPath("core_file_live_replacement.tmp")
    discard expect File.writeAllText(replacement, "new")
    defer discard catch File.delete(replacement)
    expect File.move(fileName, replacement)
    Swag.require(expect stream.size() == 3)
    expect stream.seek(.Begin, 0)
    let replaced = expect stream.readUtf8Chunk(4)
    Swag.require(replaced == "new")
    expect File.delete(fileName)
    var missingOutcome: Swag.Error
    discard catch stream.size() as missingOutcome
    let missing = missingOutcome.value()
    Swag.require(missing != null and stream.isOpen())
    stream.close()
    stream.close()
    Swag.require(not stream.isOpen())
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_existing.tmp")

    discard expect File.writeAllBytes(fileName, ['a'u8, 'b'u8])
    scope
    {
        var stream = expect File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
        discard expect stream.write(("cd").buffer, 2)
        stream.close()
    }

    scope
    {
        let content = expect File.readAllBytes(fileName)
        Swag.require(Slice.equals(content.toSlice(), ['a'u8, 'b'u8, 'c'u8, 'd'u8]))
    }

    discard expect File.delete(fileName)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_random_access.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, File.FileMode.CreateNew, File.FileAccess.ReadWrite, File.FileShare.Read)
    expect stream.resize(32)
    Swag.require(expect stream.size() == 32)
    Swag.require(expect stream.position() == 0)

    let payload: [5] u8 = [1, 3, 5, 7, 9]
    expect stream.writeAllAt(11, payload)
    expect stream.flush()
    Swag.require(expect stream.position() == 16)

    var recovered: [5] u8
    Swag.require(expect stream.readExactAt(11, recovered))
    Swag.require(Slice.equals(recovered, payload))
    Swag.require(expect stream.position() == 16)

    var beyond: [17] u8
    Swag.require(not (expect stream.readExactAt(16, beyond)))

    expect stream.seek(.Begin, 8)
    expect stream.resize(12)
    Swag.require(expect stream.position() == 8)
    expect stream.resize(4)
    Swag.require(expect stream.position() == 4)
    Swag.require(expect stream.size() == 4)
    stream.close()
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_utf8_chunks.tmp")
    defer discard catch File.delete(fileName)

    let content = "abcé◆xyz"
    discard expect File.writeAllText(fileName, content)

    var stream = expect File.openRead(fileName)

    var recovered: String
    while true
    {
        let chunk = expect stream.readUtf8Chunk(4)
        if chunk.isEmpty() do
            break
        Swag.require(chunk.count <= 4)
        Swag.require(Utf8.isValid(chunk.toSlice()))
        recovered += chunk
    }

    Swag.require(recovered == content)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_invalid_utf8_chunk.tmp")
    defer discard catch File.delete(fileName)

    discard expect File.writeAllBytes(fileName, ['a'u8, 0xFF'u8, 'b'u8])
    var stream = expect File.openRead(fileName)

    Swag.require((expect stream.readUtf8Chunk(16)) == "a")
    var errOutcome: Swag.Error
    discard catch stream.readUtf8Chunk(16) as errOutcome
    let err = errOutcome.value()
    Swag.require(err is Errors.InvalidFormatError)
    Swag.require(expect stream.position() == 1)
}

// Text chunks reject a buffer too small for one complete UTF-8 rune before moving the cursor.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_small_text_chunk.tmp")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "text")

    var stream = expect File.openRead(fileName)
    var utf8Error: Swag.Error
    discard catch stream.readUtf8Chunk(3) as utf8Error
    Swag.require(utf8Error.value() is BadParameterError)
    Swag.require(expect stream.position() == 0)

    var utf16Error: Swag.Error
    discard catch stream.readTextChunk(3, .Utf16Le) as utf16Error
    Swag.require(utf16Error.value() is BadParameterError)
    Swag.require(expect stream.position() == 0)
}

// Offsets are 64-bit all the way down to the platform call. Everything from 2 GB upward has bit 31
// set, which a 32-bit signed distance cannot carry, so these are the offsets a container-sized file
// actually lives at. Seeking never allocates a byte, so the file stays empty throughout.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_large_offset.tmp")
    defer discard catch File.delete(fileName)

    var stream = expect File.open(fileName, File.FileMode.CreateNew, File.FileAccess.ReadWrite, File.FileShare.Read)

    let offsets: [4] u64 = [0x7FFF_FFFF, 0x8000_0000, 0x1_0000_0000, 0x3_1234_5678]
    for offset in offsets
    {
        expect stream.seek(.Begin, offset)
        Swag.require(expect stream.position() == offset)
    }

    expect stream.seek(.Begin, 0x8000_0000)
    expect stream.skip(0x8000_0000)
    Swag.require(expect stream.position() == 0x1_0000_0000)
    Swag.require(expect stream.size() == 0)

    let previousPosition = expect stream.position()
    var overflowOutcome: Swag.Error
    discard catch stream.skip(Swag.U64.Max) as overflowOutcome
    Swag.require(overflowOutcome.value() is BadParameterError)
    Swag.require(expect stream.position() == previousPosition)
}

#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_append_create.tmp")

    var stream = expect File.open(fileName, File.FileMode.Append, File.FileAccess.Write, File.FileShare.Zero)
    discard expect stream.write(("xy").buffer, 2)
    stream.close()

    let content = expect File.readAllBytes(fileName)
    Swag.require(Slice.equals(content.toSlice(), ['x'u8, 'y'u8]))

    discard expect File.delete(fileName)
}

// Touching a missing path reports that it is absent and does not create it.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_touch_missing.tmp")
    Swag.require(not File.exists(fileName))

    var error: Swag.Error
    discard catch File.touch(fileName) as error
    Swag.require(error.value() is Errors.FileNotFoundError)
    Swag.require(not File.exists(fileName))
}

// OpenOrCreate preserves an existing file, while Truncate empties it.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_open_or_create.tmp")
    defer discard catch File.delete(fileName)

    let content: [4] u8 = ['k', 'e', 'e', 'p']
    scope
    {
        var stream = expect File.open(fileName, .OpenOrCreate, .ReadWrite, .Read)
        expect stream.writeAll(content)
    }

    scope
    {
        var stream = expect File.open(fileName, .OpenOrCreate, .ReadWrite, .Read)
        Swag.require(expect stream.size() == 4)
    }

    scope
    {
        var stream = expect File.open(fileName, .Truncate, .ReadWrite, .Read)
        Swag.require(expect stream.size() == 0)
    }
}

#test
{
    let source = CoreTests.makeFilesystemTestPath("core_file_move_source.tmp")
    let target = CoreTests.makeFilesystemTestPath("core_file_move_target.tmp")

    defer
    {
        if File.exists(source.toString()) do
            discard catch File.delete(source.toString())
        if File.exists(target.toString()) do
            discard catch File.delete(target.toString())
    }

    discard expect File.writeAllText(source.toString(), "moved")
    expect File.move(target.toString(), source.toString())

    Swag.require(not File.exists(source.toString()))
    Swag.require(File.exists(target.toString()))
    Swag.require((expect File.readAllText(target.toString())) == "moved")

    // Moving over an existing file replaces it rather than refusing.
    discard expect File.writeAllText(source.toString(), "again")
    expect File.move(target.toString(), source.toString())
    Swag.require((expect File.readAllText(target.toString())) == "again")
}

// Empty files and empty buffers need no absent pointer at the I/O boundary.
#test
{
    let fileName = CoreTests.makeFilesystemTestPath("core_file_empty.tmp")
    defer discard catch File.delete(fileName)
    var empty: Array'u8
    let written = expect File.writeAllBytes(fileName, empty.toSlice())
    Swag.require(written == 0)
    let bytes = expect File.readAllBytes(fileName)
    Swag.require(bytes.isEmpty())

    var stream   = expect File.open(fileName, .Open, .ReadWrite, .Read)
    var byte: u8 = 0xA5
    let read     = expect stream.read(&byte, 0)
    let write    = expect stream.write(&byte, 0)
    Swag.require(read == 0 and write == 0 and byte == 0xA5)
    Swag.require(expect stream.position() == 0)
}

// Creation modes enforce the write sandbox even when the requested handle is read-only.
#test
{
    if not Env.isSandboxed() do
        return

    let directory = Path.combine(Env.realSpecialDirectory(.Temp).toString(), Format.toString("swag-open-mode-%", Guid64.random()))
    let fileName  = Path.combine(directory.toString(), "read-only-create.tmp")
    var errOutcome: Swag.Error
    discard catch File.open(fileName.toString(), .Create, .Read, .Read) as errOutcome

    let err = errOutcome.value()
    Swag.require(err is Errors.SandboxError)
    Swag.require(not File.exists(fileName.toString()))
}

// Duplicate replaces an existing destination with the source bytes.
#test
{
    let source = CoreTests.makeFilesystemTestPath("core_file_duplicate_source.tmp")
    let target = CoreTests.makeFilesystemTestPath("core_file_duplicate_target.tmp")
    defer discard catch File.delete(source)
    defer discard catch File.delete(target)

    discard expect File.writeAllBytes(source, ['s'u8, 0, 'r'u8, 'c'u8])
    discard expect File.writeAllText(target, "old destination")

    expect File.duplicate(target, source)

    let content = expect File.readAllBytes(target)
    Swag.require(Slice.equals(content.toSlice(), ['s'u8, 0, 'r'u8, 'c'u8]))
}
