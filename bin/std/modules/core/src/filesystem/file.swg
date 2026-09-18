#global public
#global namespace File

using Core.Errors

// Origin of a seek offset in a file stream.
enum SeekOrigin
{
    Begin       // Seek from the beginning of the file
    Current     // Seek from the current position
    End         // Seek from the end of the file
}

// Access requested when opening a file.
#[Swag.EnumFlags]
enum FileAccess
{
    Read                         // Read access
    Write                        // Write access
    ReadWrite = Read | Write     // Read and write access
}

// What opening a file does when the file exists or is missing.
enum FileMode
{
    Append           // Opens the file if it exists and moves the position to its end, or creates a new file
    Create           // Creates a new file, overwriting if it already exists
    CreateNew        // Creates a new file, fails if the file already exists
    Open             // Opens an existing file
    OpenOrCreate     // Opens the file if it exists, otherwise creates a new one
    Truncate         // Opens an existing file and truncates its content to zero length
}

// Access other handles keep to a file while it is open.
#[Swag.EnumFlags]
enum FileShare
{
    Zero = 0                     // No sharing
    Delete                       // Allows the file to be deleted by others
    Inheritable                  // Child processes inherit the handle
    Read                         // Allows shared read access
    Write                        // Allows shared write access
    ReadWrite = Read | Write     // Allows shared read and write access
}

// Deletes `fullName` permanently after enforcing the process sandbox.
func delete(fullName: string) fail
{
    try Env.guardWrite(fullName)
    try deleteNative(fullName)
}

// Moves `oldName` to `newName`, replacing the destination when it exists.
func move(newName, oldName: string) fail
{
    try Env.guardWrite(oldName)
    try Env.guardWrite(newName)
    try moveNative(newName, oldName)
}

// Sets the last write time of `fullName` to now, after enforcing the process sandbox.
func touch(fullName: string) fail
{
    try Env.guardWrite(fullName)
    try touchNative(fullName)
}

// Opens a file with the requested creation, access, and sharing policy.
func open(fullName: string, mode: FileMode, access: FileAccess, share: FileShare)->FileStream fail
{
    if access & .Write do
        try Env.guardWrite(fullName)

    let canRead  = access.has(.Read)
    let canWrite = access.has(.Write)
    let handle   = try openNative(fullName, mode, access, share)

    var result: retval
    result.open(fullName, handle, canRead, canWrite, true)
    if mode == .Append do
        try result.seek(.End, 0)
    return result
}

// Opens an existing file for shared reading.
func openRead(fullName: string)->FileStream fail => try open(fullName, .Open, .Read, .Read)

// Opens a read-only stream that releases the file between operations.
//
// Each read, seek, or size query reopens the path with read, write, and delete sharing. The
// cursor survives between calls, but the file may be replaced, truncated, or removed; subsequent
// operations observe the current path and can fail. No native handle is retained while idle,
// so even an exclusive writer can save the source. This is not a consistent snapshot.
func openReadLive(fullName: string)->FileStream fail
{
    var result = try open(fullName, .Open, .Read, .ReadWrite | .Delete)
    result.close()
    result.liveRead = true
    return result
}

// Creates or replaces a file for exclusive writing.
func openWrite(fullName: string)->FileStream fail => try open(fullName, .Create, .Write, .Zero)

// Reads a whole UTF-8 file and returns its text.
//
// A leading byte-order mark is skipped. When `normalizeEol` is true, every line ends with a
// single `\n`, including the last one.
func readAllText(fullName: string, normalizeEol = false)->String fail
{
    var reader: TextReader
    try reader.open(fullName)
    if not normalizeEol do
        return try reader.readToEnd()

    var result: retval
    var line:   String
    while try reader.readLine(&line)
    {
        result += line
        result += '\n'u8
    }

    return result
}

// Reads a whole UTF-8 file and returns its lines, without their end-of-line characters.
func readAllLines(fullName: string)->Array'String fail
{
    var reader: TextReader
    try reader.open(fullName)

    var result: retval
    var line:   String
    while try reader.readLine(&line) do
        result.add(#move line)
    return result
}

// Runs `stmt` for each line of a UTF-8 file, read one at a time.
//
// The block receives `line`, the address of a buffer reused from one line to the next: copy the
// text to keep it beyond the iteration.
#[Swag.Macro]
func readEachLine(fullName: string, stmt: #code(var line: *String)) fail
{
    var reader: TextReader
    try reader.open(fullName)

    var buffer: String
    while try reader.readLine(&buffer) do
        #inject(stmt, line = &buffer)
}

// Reads a whole file and returns its bytes.
func readAllBytes(fullName: string)->Array'u8 fail
{
    var stream = try openRead(fullName)

    var result: retval
    let length = try stream.size()
    result.reserve(length)
    result.count = try stream.read(result.buffer, length)
    return result
}

// Creates or replaces a file with `buffer` and returns the number of bytes written.
#[Swag.Discardable]
func writeAllBytes(fullName: string, buffer: const [..] u8)->u64 fail
{
    var stream = try openWrite(fullName)
    return try stream.write(buffer)
}

// Creates or replaces a file with every chunk of `buffer`, in order, and returns the number of bytes written.
#[Swag.Discardable]
func writeAllBytes(fullName: string, buffer: ConcatBuffer)->u64 fail
{
    var stream = try openWrite(fullName)

    var total = 0'u64
    for chunk in buffer do
        total += try stream.write(chunk.data, chunk.count)
    return total
}

// Creates or replaces a file with the UTF-8 bytes of `text` and returns the number of bytes written.
#[Swag.Discardable]
func writeAllText(fullName: string, text: string)->u64 fail => try writeAllBytes(fullName, cast(const [..] u8) text)

// Creates or replaces a file with `lines`, each followed by `\n`, and returns the number of bytes written.
#[Swag.Discardable]
func writeAllLines(fullName: string, lines: Array'(string))->u64 fail
{
    var stream = try openWrite(fullName)

    var total = 0'u64
    for line in lines
    {
        total += try stream.write(cast(const [..] u8) line)
        total += try stream.write(cast(const [..] u8) "\n")
    }

    return total
}

// Copies the file `oldName` to `newName`, replacing the destination when it exists.
//
// The whole content is held in memory during the copy.
func duplicate(newName, oldName: string) fail
{
    let content = try readAllBytes(oldName)
    try writeAllBytes(newName, content.toSlice())
}
