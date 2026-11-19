using Core, Gui

const OpenVaultMessage = 2'u32

// Resolves the file in the caller's working directory before handing it to another process.
func vaultLaunchFile(arguments: const [..] string)->String
{
    if arguments.count <= 1 do
        return {}

    for argument in arguments[1 to]
    {
        let runtimeSetting = argument == "swag.sandbox" or argument == "swag.test" or Utf8.startsWith(argument, "swag.") and Utf8.contains(argument, "=")
        if runtimeSetting or Utf8.startsWith(argument, "--") or not Path.isValidPathName(argument) do
            continue
        let path = catch Path.absolute(argument) { continue }
        if File.exists(path) do
            return path
    }

    return {}
}

// Each launch owns a separate memory block until the window has copied the path.
// A byte count covers UTF-8 encodings of the longest supported native paths.
struct LaunchRequest
{
    size:     u32
    accepted: u32
    bytes:    [128 * 1024] u8
}

impl LaunchRequest
{
    mtd send(surfaceId: string, token: u64, path: string)->bool
    {
        if path.count > .bytes.count do
            return false
        Memory.copy(.bytes.buffer, path.buffer, path.count)
        Atomic.exchange(&.size, cast(u32, path.count))

        // The session lock can become visible before the first window has been created.
        var delivered = false
        for 250
        {
            if not delivered do
                delivered = Surface.sendCustomMessage(surfaceId, OpenVaultMessage, token)
            if Atomic.get(&.accepted) != 0 do
                return true
            Threading.Thread.sleep(20'ms)
        }

        return false
    }

    mtd receive()->String
    {
        let size = Atomic.get(&.size)
        if size == 0 or size > .bytes.count or Atomic.get(&.accepted) != 0 do
            return {}

        let path = cast(string, .bytes[until size])
        if not Path.isValidPathName(path) or not Path.isRooted(path) do
            return {}

        let result = String.from(path)
        Atomic.exchange(&.accepted, 1)
        return result
    }
}
