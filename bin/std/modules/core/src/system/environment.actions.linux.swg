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
