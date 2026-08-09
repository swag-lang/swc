#global public
#global namespace File

using Core.Errors

// Origin from which to calculate seek offset in a file stream
enum SeekOrigin
{
    Begin       // Seek from the beginning of the file
    Current     // Seek from the current position
    End         // Seek from the end of the file
}

#[Swag.EnumFlags]
// File access permissions
enum FileAccess
{
    Read                         // Read access
    Write                        // Write access
    ReadWrite = Read | Write     // Read and write access
}

// File creation and opening behaviors
enum FileMode
{
    Append           // Opens the file if it exists and moves the seek to the end, or creates a new file
    Create           // Creates a new file, overwriting if it already exists
    CreateNew        // Creates a new file, fails if the file already exists
    Open             // Opens an existing file
    OpenOrCreate     // Opens the file if it exists, otherwise creates a new one
    Truncate         // Opens an existing file and truncates its content to zero length
}

#[Swag.EnumFlags]
// File sharing options
enum FileShare
{
    Zero = 0                     // No sharing
    Delete                       // Allows the file to be deleted by others
    Inheritable                  // File handle is inheritable
    Read                         // Allows shared read access
    Write                        // Allows shared write access
    ReadWrite = Read | Write     // Allows shared read and write access
}

// Deletes `fullName` permanently after enforcing the process sandbox.
func delete(fullName: string) fail
{
    try Env.guardWrite(fullName)
    deleteNative(fullName)
}

// Moves `oldName` to `newName`, replacing the destination when it exists.
func move(newName, oldName: string) fail
{
    try Env.guardWrite(oldName)
    try Env.guardWrite(newName)
    moveNative(newName, oldName)
}

// Updates a file's write time after enforcing the process sandbox.
func touch(fullName: string) fail
{
    try Env.guardWrite(fullName)
    touchNative(fullName)
}

// Opens a file with the requested creation, access, and sharing policy.
func open(fullName: string, mode: FileMode, access: FileAccess, share: FileShare)->FileStream fail
{
    if access & .Write do
        try Env.guardWrite(fullName)

    let canRead  = access.has(.Read)
    let canWrite = access.has(.Write)
    let handle   = openNative(fullName, mode, access, share)

    var result: retval
    result.open(fullName, handle, canRead, canWrite, true)
    if mode == .Append do
        result.seek(.End, 0)
    return result
}

// Opens an existing file for shared reading.
func openRead(fullName: string)->FileStream fail
{
    return open(fullName, .Open, .Read, .Read)
}

// Creates or replaces a file for exclusive writing.
func openWrite(fullName: string)->FileStream fail
{
    return open(fullName, .Create, .Write, .Zero)
}

// Reads the entire content of a file into a UTF-8 string
func readAllText(fullname: string, encoding = TextEncoding.Utf8, normalizeEol = false)->String fail
{
    var textReader: TextReader
    textReader.open(fullname, encoding)

    // Normalized end of lines.
    if normalizeEol
    {
        var result: retval
        var res:    String
        while textReader.readLine(&res)
        {
            result += res
            result += '\n'u8
        }

        return result
    }

    return textReader.readToEnd()
}

// Reads all lines from a file into an array of strings
func readAllLines(fullname: string, encoding = TextEncoding.Utf8)->Array'String fail
{
    var textReader: TextReader
    textReader.open(fullname, encoding)

    var result: retval
    var res:    String
    while textReader.readLine(&res) do
        result.add(#move res)
    return result
}

// Executes user code for each line read from a file
// Block parameter: 'line' is a reference to the current line.
#[Swag.Macro]
func readEachLines(fullname: string, encoding = TextEncoding.Utf8, stmt: #code(var line: &String)) fail
{
    var textReader: TextReader
    textReader.open(fullname, encoding)

    var res: String
    while textReader.readLine(&res)
    {
        #inject(stmt, line = &res)
    }
}

// Reads the entire content of a file into an array of bytes
func readAllBytes(fullname: string)->Array'u8 fail
{
    var stream = openRead(fullname)

    var result: retval
    let len = stream.size()
    result.reserve(len)
    result.count = stream.read(result.buffer, len)
    return result
}

// Writes the content of a byte slice to a file
#[Swag.Discardable]
func writeAllBytes(fullname: string, buffer: const [..] u8)->u64 fail
{
    var stream = openWrite(fullname)
    return stream.write(@dataof(buffer), @countof(buffer))
}

// Writes the content of a ConcatBuffer to a file
#[Swag.Discardable]
func writeAllBytes(fullname: string, buffer: ConcatBuffer)->u64 fail
{
    var stream = openWrite(fullname)

    var total = 0'u64
    for p in buffer do
        total += stream.write(p.data, p.count)

    return total
}

// Writes an array of strings to a file, one string per line
#[Swag.Discardable]
func writeAllLines(fullname: string, lines: Array'(string))->u64 fail
{
    var stream = openWrite(fullname)

    var total = 0'u64
    for v in lines
    {
        total += stream.write(@dataof(v), @countof(v))
        total += stream.write(@dataof("\n"), 1)
    }

    return total
}

// Creates a duplicate of an existing file
func duplicate(newName, oldName: string) fail
{
    var res = readAllBytes(oldName)
    writeAllBytes(newName, res.toSlice())
}
