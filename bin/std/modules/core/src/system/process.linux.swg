#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Env

internal func processEnvironmentStoredName(name: string)->String => String.from(name)

// Exits the current process; the parent observes the low eight bits of `exitCode`.
#[Swag.NoReturn]
func exit(exitCode: s32) => Linux.exit(exitCode)

// Returns a copy of the current process environment variable `name`.
//
// Names are case-sensitive. An unset variable, an empty value, or an invalid name returns
// an empty string. The caller must synchronize this with any concurrent environment mutation.
func variable(name: string)->String
{
    if not name.count do
        return ""
    for byte in name where byte == 0 or byte == '=' do
        return ""
    let native = String.from(name)
    let value  = Linux.getenv(native.storage())
    if not value do
        return ""
    return String.from(cast(string, cast(cstring, value)))
}

impl Process
{
    // Returns the current operating-system process identifier.
    func currentProcessId()->u64 => cast(u64, Linux.getpid())

    // Returns the current operating-system thread identifier (Linux TID, not pthread_t).
    func currentThreadId()->u64 => cast(u64, Linux.gettid())
}

// glibc owns the environment table. Keep its address, since setenv/clearenv can replace the table.
// No loader allocation or Core storage is retained by the returned view.
internal func nativeEnvironmentAddress()->const *([*] ([*] u8?)?) fail
{
    let image = Linux.dlopen(null, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not image do
        fail Swag.SystemError{"cannot open the current process image"}
    defer discard Linux.dlclose(unwrap image)
    let address = Linux.dlsym(image, "environ".buffer)
    if not address do
        fail Swag.SystemError{"cannot find the current process environment"}
    return cast(const *([*] ([*] u8?)?), address)
}

// Returns an owned snapshot of the process environment, preserving case-sensitive names.
//
// Changing the snapshot does not change this process. The caller must synchronize with any
// concurrent native environment mutation. An unavailable native table yields an empty snapshot.
func currentEnvironment()->ProcessEnvironment
{
    let address = catch nativeEnvironmentAddress() { return {} }
    let values  = address[]
    var result: #returntype
    if not values do
        return result
    var index = 0'u64
    for
    {
        let entry = values[index]
        if not entry do
            return result
        let text      = cast(string, cast(cstring, entry))
        let separator = Utf8.indexOf(cast(const [..] u8, text), "=")
        if separator != Swag.U64.Max and separator != 0 do
            result.set(text[until separator], text[separator + 1 to])
        index += 1
    }
}

impl Process
{
    // Returns the absolute native image path reported by /proc/self/exe.
    //
    // Fails when procfs is unavailable or the link cannot be read. Linux appends " (deleted)"
    // when the executable was unlinked; that spelling is retained and may not name an openable file.
    func currentExecutablePath()->String fail
    {
        var buffer: Array'u8
        buffer.reserve(256)
        for
        {
            let count = Linux.readlinkat(Linux.AT_FDCWD, "/proc/self/exe".buffer, buffer.storage(), buffer.capacity)
            if count < 0
            {
                let error = Linux.errno()
                if error == Linux.EINTR do
                    continue
                try Errors.failLinuxError(error, "/proc/self/exe")
            }

            if cast(u64, count) < buffer.capacity do
                return String.from(cast(string, Swag.makeSlice(buffer.storage(), cast(u64, count))))

            // readlink has no terminator, and filling the whole buffer can mean truncation.
            if buffer.capacity > Swag.U64.Max / 2 do
                fail Errors.OverflowError{}
            buffer.reserve(buffer.capacity * 2)
        }
    }
}
