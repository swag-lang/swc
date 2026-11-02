#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Env

private func launchDesktopAction(argument: string)->bool
{
    // Detach our streams from a launcher that may outlive this call. Process cleanup hands
    // the live child to Core's reaper without waiting for the desktop application to close.
    let arguments = [argument]
    with let info = StartInfo{fileName: "xdg-open", arguments: arguments}
    {
        .standardInput  = .Discard
        .standardOutput = .Discard
        .standardError  = .Discard
    }

    var outcome: Swag.Error
    discard catch startProcess(info) as outcome
    return outcome.value() == null
}

// Opens a file or directory with its system-default application through `xdg-open`.
//
// Relative paths are made absolute without resolving symlinks, so a leading dash or colon
// cannot be interpreted as a launcher option or URL scheme. Empty, invalid UTF-8 and zero-byte
// paths return `false`. The result reports whether the launcher started, not whether a desktop
// handler later succeeded. Missing launchers return `false`; this call does not wait for a UI.
#[Swag.Discardable]
func openFile(path: string)->bool
{
    if not Utf8.isValid(cast(const [..]u8, path)) do
        return false
    let absolute = catch Path.absolute(path) { return false }
    return launchDesktopAction(absolute.toString())
}

// Opens a web address with the system-default handler through `xdg-open`.
//
// Only addresses accepted by [[Core.Env.isWebUrl]] are handed over. The complete address is
// passed as one argument, with no shell parsing. The result reports whether the launcher started,
// not whether a desktop handler later succeeded. Missing launchers return `false`.
#[Swag.Discardable]
func openUrl(url: string)->bool
{
    if not isWebUrl(url) do
        return false
    return launchDesktopAction(url)
}

// Asks the session's file manager to show and select `path`.
//
// Uses the standard FileManager1 D-Bus service through `gdbus`. Paths become absolute without
// resolving symlinks and are encoded as local file URIs. Returns `true` only when the service
// acknowledges the request; invalid paths, missing tools/services, rejection and timeout return
// `false`. The call waits approximately two seconds at most, subject to scheduling, and stops
// its request process on timeout. Acknowledgement does not prove a window became visible.
#[Swag.Discardable]
func showInFileExplorer(path: string)->bool
{
    if not Utf8.isValid(cast(const [..]u8, path)) do
        return false
    let absolute    = catch Path.absolute(path) { return false }
    var uri: String = "file://"
    const Hex = "0123456789ABCDEF"
    for byte in absolute.toString()
    {
        if (byte >= 'a' and byte <= 'z') or
           (byte >= 'A' and byte <= 'Z') or
           (byte >= '0' and byte <= '9') or
           byte == '/' or
           byte == '-' or
           byte == '_' or
           byte == '.' or
           byte == '~'
        {
            uri.append(byte)
        }
        else
        {
            uri.append("%")
            uri.append(Hex[byte >> 4])
            uri.append(Hex[byte & 15])
        }
    }

    // URI encoding also keeps quotes and variant syntax out of this typed string array.
    let items     = Format.toString("['%']", uri.toString())
    let arguments = ["call", "--session", "--dest", "org.freedesktop.FileManager1",
                     "--object-path", "/org/freedesktop/FileManager1",
                     "--method", "org.freedesktop.FileManager1.ShowItems", "--timeout", "2",
                     items.toString(), ""]
    with let info = StartInfo{fileName: "gdbus", arguments: arguments}
    {
        .standardInput  = .Discard
        .standardOutput = .Discard
        .standardError  = .Discard
    }

    var process = catch startProcess(info) { return false }
    defer
    {
        if process.isRunning() do
            discard catch process.kill()
    }

    let finished = catch process.tryWaitForExit(Time.Duration.fromMilliseconds(2000)) { return false }
    return finished and process.exitCode() == 0
}
