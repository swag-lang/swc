#global if WINDOWS

using Win32

#[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
{
    private func LoadLibraryW(fileName: #null const [*] u16)->#null *void
    private func FreeLibrary(module: *void)->s32
}

internal func loadNativeLibrary(path: string)->*void fail
{
    let nativePath = Utf16.toZeroTerminated(path)
    let handle     = LoadLibraryW(@dataof(nativePath))
    if !handle do
        failWinError(GetLastError())
    return handle!
}

internal func nativeLibrarySymbol(handle: *void, name: string)->#null const *void
{
    return GetProcAddress(cast(HMODULE) handle, @dataof(name))
}

internal func closeNativeLibrary(handle: *void)
{
    discard FreeLibrary(handle)
}
