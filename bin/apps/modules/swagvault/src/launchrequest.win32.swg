#global if WINDOWS

using Core, Win32

private func launchRequestName(token: u64)->Array'u16
{
    return Utf16.toZeroTerminated(Format.toString("Local\\Swag.Vault.Launch.%", token))
}

func forwardVaultLaunch(surfaceId, path: string)->bool fail
{
    let token         = Guid64.random().value
    let name          = launchRequestName(token)
    let handle        = try CreateFileMappingW(INVALID_HANDLE_VALUE, null, PAGE_READWRITE, 0, #sizeof(LaunchRequest), name.buffer)
    let alreadyExists = GetLastError() == ERROR_ALREADY_EXISTS
    defer CloseHandle(handle)
    if alreadyExists do
        return false

    let view = try MapViewOfFile(handle, FILE_MAP_WRITE, 0, 0, #sizeof(LaunchRequest))
    defer discard catch UnmapViewOfFile(view)
    return (assume cast(*LaunchRequest, view)).send(surfaceId, token, path)
}

func receiveVaultLaunch(token: u64)->String
{
    let name   = launchRequestName(token)
    let handle = catch OpenFileMappingW(FILE_MAP_WRITE, FALSE, name.buffer) { return {} }
    defer CloseHandle(handle)
    let view = catch MapViewOfFile(handle, FILE_MAP_WRITE, 0, 0, #sizeof(LaunchRequest)) { return {} }
    defer discard catch UnmapViewOfFile(view)
    return (assume cast(*LaunchRequest, view)).receive()
}
