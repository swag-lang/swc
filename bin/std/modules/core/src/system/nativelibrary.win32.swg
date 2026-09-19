#global if WINDOWS

using Win32

internal func loadNativeLibrary(path: string)->const *void fail
{
    let nativePath = Utf16.toZeroTerminated(path)
    let handle     = LoadLibraryW(nativePath.buffer)
    if not handle do
        try failWinError(GetLastError())
    return cast(const *void) handle!
}

internal func nativeLibrarySymbol(handle: const *void, name: string)->const *void?
{
    // The symbol name is read up to its terminator, which a 'string' view does not guarantee.
    let symbolName = String.from(name)
    return GetProcAddress(cast(HMODULE) handle, symbolName.buffer)
}

internal func closeNativeLibrary(handle: const *void)
{
    discard FreeLibrary(cast(HMODULE) handle)
}
