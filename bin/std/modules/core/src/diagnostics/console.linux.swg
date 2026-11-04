#global if #os == Swag.TargetOs.Linux
#global namespace Console

private const TextColors = ["\x1b[30m", "\x1b[97m", "\x1b[37m", "\x1b[91m", "\x1b[94m", "\x1b[92m", "\x1b[96m", "\x1b[93m", "\x1b[95m", "\x1b[31m", "\x1b[34m", "\x1b[32m", "\x1b[36m", "\x1b[33m", "\x1b[35m"]
private const BackColors = ["\x1b[40m", "\x1b[107m", "\x1b[47m", "\x1b[101m", "\x1b[104m", "\x1b[102m", "\x1b[106m", "\x1b[103m", "\x1b[105m", "\x1b[41m", "\x1b[44m", "\x1b[42m", "\x1b[46m", "\x1b[43m", "\x1b[45m"]

private var g_ColorChanged: bool

#drop
{
    if g_ColorChanged do
        resetColor()
}

private func supportsColor()->bool
{
    if Linux.isatty(1) != 1 do
        return false
    let term = Linux.getenv("TERM".buffer)
    if not term do
        return false
    let kind = cast(string, cast(cstring, term))
    return kind.count != 0 and kind != "dumb"
}

internal func writeNative(message: string)
{
    var offset = 0'u64
    while offset < message.count
    {
        let count = Linux.write(1, message.buffer + offset, message.count - offset)
        if count > 0 do
            offset += cast(u64, count)
        elif count == 0 or Linux.errno() != Linux.EINTR do
            return
    }
}

// Sets the foreground color on a terminal; redirected output receives no escape sequences.
public func setTextColor(color: Color)
{
    if supportsColor()
    {
        writeNative(TextColors[cast(u32, color)])
        g_ColorChanged = true
    }
}

// Sets the background color on a terminal; redirected output receives no escape sequences.
public func setBackColor(color: Color)
{
    if supportsColor()
    {
        writeNative(BackColors[cast(u32, color)])
        g_ColorChanged = true
    }
}

// Restores terminal default colors; redirected output is unchanged.
public func resetColor()
{
    if supportsColor() do
        writeNative("\x1b[0m")
    g_ColorChanged = false
}

// Reads one line of bytes from standard input, including its line ending.
//
// End of input or a read failure returns the bytes already read. Bytes after the first newline
// remain on standard input for the next call; no terminal encoding conversion is performed.
public func prompt()->String
{
    var result: #returntype
    var byte:   u8
    for
    {
        let count = Linux.read(0, &byte, 1)
        if count == 1
        {
            result += cast(string, Swag.makeSlice(&byte, 1))
            if byte == '\n' do
                return result
        }
        elif count == 0 or Linux.errno() != Linux.EINTR
        {
            return result
        }
    }
}
