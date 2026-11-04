#global if WINDOWS
#global namespace Env

using Win32

// Returns whether the process command line carries the run argument `name`, with the value after its '=' when there is one.
//
// Read straight from the operating system rather than through 'Swag.args()'. The sandbox is armed
// from a module init hook so it precedes every '#init', '#premain' and '#main' in the program,
// and the runtime has not populated its argument vector that early.
internal func findRunArgument(name: string)->{ found: bool, value: String }
{
    var result: #returntype

    // Runtime arguments are already present in a JIT run. Windows native startup still
    // needs the command-line fallback below before its argument vector is populated.
    result = findRunArgumentIn(Swag.args(), name)
    if result.found do
        return result

    var scan = GetCommandLineA()
    if not scan do
        return result

    var cursor = scan
    while cursor[]
    {
        while cursor[] == ' ' do
            cursor += 1
        if cursor[] == 0 do
            break

        // Tokens are separated by spaces, and a quoted token may contain them.
        var quoted = false
        if cursor[] == '"'
        {
            quoted = true
            cursor += 1
        }

        let start = cursor
        while cursor[] and (quoted ? cursor[] != '"' : cursor[] != ' ') do
            cursor += 1

        let token = cast(string, Swag.makeSlice(start, cast(u64, (cursor - start))))
        if cursor[] do
            cursor += 1

        if token.count < name.count do
            continue
        if token[until name.count] != name do
            continue

        // An exact match, or the name followed by '=' and its value. A longer token that
        // merely starts with the name is a different argument.
        if token.count == name.count
        {
            result.found = true
            return result
        }

        if token[name.count] == '='
        {
            result.found = true
            result.value = String.from(token[name.count + 1 to])
            return result
        }
    }

    return result
}

// Resolves `path` against the current directory and collapses '.' and '..'.
//
// The containment check is only sound on a canonical path: comparing raw text would accept
// 'root/../elsewhere' as being inside 'root'. The system canonicalizer is used rather than a
// hand-written one so the answer matches what the file system will actually open.
internal func absolutePath(path: string)->String
{
    var result: #returntype
    if not Path.isValidPathName(path) do
        return ""

    const MaxLength = 32768'u32

    let winPath = Utf16.toZeroTerminated(path)

    var arr16: Array'u16
    arr16.reserve(cast(u64, MaxLength) + 1)

    // Only the returned length decides: the call does not clear the thread's last error, so a
    // stale one would send an otherwise successful resolution down the fallback path.
    let written = catch GetFullPathNameW(winPath.buffer, MaxLength, arr16.buffer, null)

    // A failed canonicalization must never become a literal prefix accepted by containment.
    if written == 0 or written >= MaxLength do
        return ""

    arr16.count = written
    result      = Utf8.fromUtf16(arr16.toSlice())
    Path.normalize(&result)
    return result
}
