#global public

using Core.Errors

// Owns one dynamically loaded native library.
//
// Loading may run code owned by the library. Resolve symbols only while this value remains open;
// every address returned by [[Core.NativeLibrary.symbol]] becomes invalid after [[Core.NativeLibrary.close]].
// Dropping the value closes it automatically.
#[Swag.NoCopy]
struct NativeLibrary
{
    internal handle: const *void?     // Platform module handle, or null while closed.
}

impl NativeLibrary
{
    // Closes the library and invalidates every symbol address borrowed from it.
    mtd opDrop()
    {
        .close()
    }

    // Reports whether a native library is currently loaded.
    mtd const isOpen()->bool => .handle != null

    // Resolves an exported symbol, or returns null when the name contains a zero byte or has no export.
    //
    // The returned address is borrowed from this library and remains valid only until [[Core.NativeLibrary.close]].
    mtd const symbol(name: string)->const *void?
    {
        if not .handle
        {
            return null
        }

        for byte in name where byte == 0
        {
            return null
        }

        return nativeLibrarySymbol(.handle, name)
    }

    // Releases the loaded library. Repeated calls have no effect.
    //
    // Every address returned by [[Core.NativeLibrary.symbol]] becomes invalid.
    mtd close()
    {
        if not .handle
        {
            return
        }

        closeNativeLibrary(.handle)
        .handle = null
    }

    // Loads a native library from `path`.
    //
    // The returned owner closes the library automatically. Repeated loads hold independent
    // references. Loading fails for a path containing a zero byte or when the platform loader
    // cannot resolve the file or one of its dependencies.
    func load(path: string)->NativeLibrary fail
    {
        for byte in path where byte == 0
        {
            fail BadParameterError{"native library paths must not contain zero bytes"}
        }

        var result: #returntype
        result.handle = try loadNativeLibrary(path)


        return result
    }
}
