#global public
#global namespace Console

// Selects color.
enum Color
{
    Black           // Selects black.
    White           // Selects white.
    Gray            // Selects gray.
    Red             // Selects red.
    Blue            // Selects blue.
    Green           // Selects green.
    Cyan            // Selects cyan.
    Yellow          // Selects yellow.
    Magenta         // Selects magenta.
    DarkRed         // Selects dark red.
    DarkBlue        // Selects dark blue.
    DarkGreen       // Selects dark green.
    DarkCyan        // Selects dark cyan.
    DarkYellow      // Selects dark yellow.
    DarkMagenta     // Selects dark magenta.
}

internal var g_SilentMode: s32
private var g_lock:        Sync.Mutex

// Use to access console with multiple threads.
// No console function is thread safe, so it is the user responsability
// to lock the console when necessary
func lock() => g_lock.lock()

// Releases the lock.
func unlock() => g_lock.unlock()

// Disable console output. This is a counter, so can be called
// multiple times with the same 'value'
// Like any other console functions, this is not thread-safe
// => call 'lock' before if necessary, and 'unlock' after
func silent(value: bool)
{
    Debug.assert(value or g_SilentMode > 0)
    g_SilentMode += value ? 1 : -1
}

// Writes a formatted message unless console output is silent.
func printf(message: #null string, params: ...)
{
    if g_SilentMode or message == null do
        return

    let safeMessage = message orelse ""
    if params.count
    {
        let rendered = Format.toString(safeMessage, params)
        writeNative(rendered)
    }
    else do
        writeNative(safeMessage)
}

// Write a bunch of parameters to the console
func print(params: ...)
{
    var buf:     ConcatBuffer
    let convFmt: StrConv.ConvertFormat

    for v in params do
        StrConv.convertAny(&buf, v, convFmt, null)
    printf(buf.toString())
}

// Write a line to the console
func println(params: ...)
{
    print(params)
    print("\n")
}
