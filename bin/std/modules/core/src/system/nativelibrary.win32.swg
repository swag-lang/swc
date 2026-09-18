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
    if not handle do
        try failWinError(GetLastError())
    return handle!
}

internal func nativeLibrarySymbol(handle: *void, name: string)->const *void?
{
    // The symbol name is read up to its terminator, which a 'string' view does not guarantee.
    let symbolName = String.from(name)
    return GetProcAddress(cast(HMODULE) handle, symbolName.buffer)
}

internal func closeNativeLibrary(handle: *void)
{
    discard FreeLibrary(handle)
}
