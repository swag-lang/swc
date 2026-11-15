#global if WINDOWS
#global namespace Env

using Win32

internal impl SessionInstance
{
    mtd acquireNative(id: string)->bool fail
    {
        let user = getSpecialDirectory(.UserAppData)
        if not Path.isRooted(user) do
            fail Errors.BadParameterError{}
        let name   = Utf16.toZeroTerminated(Format.toString("Local\\Swag.%.%", id, Hash.hash64(user)))
        let handle = try CreateMutexW(null, FALSE, name.buffer)
        if GetLastError() == ERROR_ALREADY_EXISTS
        {
            CloseHandle(handle)
            return false
        }

        .handle = handle
        return true
    }

    mtd closeNative()
    {
        CloseHandle(.handle)
        .handle = null
    }
}
