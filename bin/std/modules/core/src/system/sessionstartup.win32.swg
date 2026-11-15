#global if WINDOWS
#global namespace Env

using Win32

internal func setSessionStartupNative(id, _: string, enabled: bool, arguments: const [..] string)->bool fail
{
    let key  = Utf16.toZeroTerminated("Software\\Microsoft\\Windows\\CurrentVersion\\Run")
    let name = Utf16.toZeroTerminated(id)
    var handle: HKEY
    if RegCreateKeyExW(HKEY_CURRENT_USER, key.buffer, 0, null, 0, KEY_SET_VALUE, null, &handle, null) != ERROR_SUCCESS do
        return false
    defer RegCloseKey(handle)
    if not enabled
    {
        let status = RegDeleteValueW(handle, name.buffer)
        return status == ERROR_SUCCESS or status == ERROR_FILE_NOT_FOUND
    }

    var command = quoteArgument(try Process.currentExecutablePath())
    for argument in arguments
    {
        command += ' 'u8
        command += quoteArgument(argument)
    }

    let native = Utf16.toZeroTerminated(command)
    return RegSetValueExW(handle, name.buffer, 0, REG_SZ, cast(const *u8?, native.buffer), cast(u32, native.count * #sizeof(u16))) == ERROR_SUCCESS
}
