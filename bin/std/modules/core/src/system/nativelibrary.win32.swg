#global if WINDOWS

using Win32

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    private func LoadLibraryW(fileName: const [*] u16?)->*void?
    private func FreeLibrary(module: *void)->s32
}

internal func loadNativeLibrary(path: string)->*void fail
{
    let nativePath = Utf16.toZeroTerminated(path)
    let handle     = LoadLibraryW(nativePath.buffer)
    if !handle do
        failWinError(GetLastError())
    return handle!
}

internal func nativeLibrarySymbol(handle: *void, name: string)->const *void?
{
    return GetProcAddress(cast(HMODULE) handle, name.buffer)
}

internal func closeNativeLibrary(handle: *void)
{
    discard FreeLibrary(handle)
}
