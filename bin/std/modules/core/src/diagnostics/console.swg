#global public
#global namespace Console

// Names a console text or background color.
enum Color
{
    Black
    White
    Gray
    Red
    Blue
    Green
    Cyan
    Yellow
    Magenta
    DarkRed
    DarkBlue
    DarkGreen
    DarkCyan
    DarkYellow
    DarkMagenta
}

internal var g_SilentMode: s32
private var g_Lock:        Sync.Mutex

// Acquires the console lock, which serializes console output across threads.
//
// Console functions do not take this lock themselves: a caller that writes from several
// threads locks around each write, and releases the lock with [[Core.Console.unlock]].
func lock() => g_Lock.lock()

// Releases the console lock taken by [[Core.Console.lock]].
func unlock() => g_Lock.unlock()

// Silences console output when `value` is true, and undoes one earlier silencing when it is false.
//
// Silencing is counted, so nested calls balance, and output resumes once every silencing is
// undone. Like the other console functions, this does not take the console lock.
func silent(value: bool)
{
    Swag.assert(value or g_SilentMode > 0)
    g_SilentMode += value ? 1 : -1
}

// Writes a formatted message unless console output is silent.
func printf(message: string?, params: ...)
{
    if g_SilentMode or message == null do
        return

    let safeMessage = message orelse ""
    if params.count do
        writeNative(Format.toString(safeMessage, params))
    else do
        writeNative(safeMessage)
}

// Writes the text form of every parameter, without separators, unless console output is silent.
func print(params: ...)
{
    var buf:     ConcatBuffer
    let convFmt: StrConv.ConvertFormat

    for v in params do
        StrConv.convertAny(&buf, v, convFmt, null)
    printf(buf.toString())
}

// Writes the parameters like [[Core.Console.print]], followed by a new line.
func println(params: ...)
{
    print(params)
    print("\n")
}
