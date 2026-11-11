#global if WINDOWS

using Win32

internal func loadNativeLibrary(path: string)->const *void fail
{
    let nativePath = Utf16.toZeroTerminated(path)
    // A full path identifies a deployable directory. Resolve its sibling DLL dependencies
    // there as well as in the application's normal search locations.
    let handle = Path.isRooted(path) ?
                 LoadLibraryExW(nativePath.buffer, null, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS) :
                 LoadLibraryW(nativePath.buffer)
    if not handle do
        try failWinError(GetLastError())
    return cast(const *void, unwrap handle)
}

internal func nativeLibrarySymbol(handle: const *void, name: string)->const *void?
{
    // The symbol name is read up to its terminator, which a 'string' view does not guarantee.
    let symbolName = String.from(name)
    return GetProcAddress(cast(HMODULE, handle), symbolName.buffer)
}

internal func closeNativeLibrary(handle: const *void)
{
    discard FreeLibrary(cast(HMODULE, handle))
}
