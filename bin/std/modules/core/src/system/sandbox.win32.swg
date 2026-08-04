#global if WINDOWS
#global namespace Env

using Win32

// Returns the operating-system identifier of the running process.
internal func currentProcessId()->u32
{
    return GetCurrentProcessId()
}

// Returns whether the process command line carries the run argument `name`, along with the
// value that follows an '=' when there is one.
//
// Read straight from the operating system rather than through '@args'. The sandbox is armed
// from a module init hook so it precedes every '#init', '#premain' and '#main' in the program,
// and the runtime has not populated its argument vector that early.
internal func findRunArgument(name: string)->{ found: bool, value: String }
{
    var result: retval

    // A compile-time run has no operating-system command line of its own: it executes inside
    // the compiler, which hands the program its arguments directly. Consult those first so a
    // test running under the interpreter is isolated exactly like the native one.
    for arg in @args
    {
        if @countof(arg) < @countof(name) do
            continue
        if arg[0 until @countof(name)] != name do
            continue
        if @countof(arg) == @countof(name)
        {
            result.found = true
            return result
        }

        if arg[@countof(name)] == '='
        {
            result.found = true
            result.value = String.from(arg[@countof(name) + 1 until @countof(arg)])
            return result
        }
    }

    var scan = GetCommandLineA()
    if !scan do
        return result

    var cursor = scan!
    while dref cursor
    {
        while dref cursor == ' ' do
            cursor += 1
        if dref cursor == 0 do
            break

        // Tokens are separated by spaces, and a quoted token may contain them.
        var quoted = false
        if dref cursor == '"'
        {
            quoted = true
            cursor += 1
        }

        let start = cursor
        while dref cursor and (quoted ? dref cursor != '"' : dref cursor != ' ') do
            cursor += 1

        let token = cast(string) @mkslice(start, cast(u64) (cursor - start))
        if dref cursor do
            cursor += 1

        if @countof(token) < @countof(name) do
            continue
        if token[0 until @countof(name)] != name do
            continue

        // An exact match, or the name followed by '=' and its value. A longer token that
        // merely starts with the name is a different argument.
        if @countof(token) == @countof(name)
        {
            result.found = true
            return result
        }

        if token[@countof(name)] == '='
        {
            result.found = true
            result.value = String.from(token[@countof(name) + 1 until @countof(token)])
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
    var result: retval

    const MaxLength = 32768'u32

    let winPath = Utf16.toZeroTerminated(path)

    var arr16: Array'u16
    arr16.reserve(cast(u64) MaxLength + 1)

    // Only the returned length decides: the call does not clear the thread's last error, so a
    // stale one would send an otherwise successful resolution down the fallback path.
    let written = catch GetFullPathNameW(@dataof(winPath), MaxLength, arr16.buffer, null)
    if written == 0 or written > MaxLength
    {
        // Fall back to the literal path. It can only make the check stricter: a path that
        // cannot be resolved will not match the root, so the write is refused.
        result = String.from(path)
        Path.normalize(&result)
        return result
    }

    arr16.count = written
    result      = Utf8.fromUtf16(arr16.toSlice())
    Path.normalize(&result)
    return result
}
