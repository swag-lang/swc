#global public

using Core.Errors

private const SwagRuntimeHookSymbol = "__swc_rt_stage"
private const SwagRuntimeHookSync   = 0'u64

// Owns one dynamically loaded native library.
//
// Loading may run code owned by the library. Resolve symbols only while this value remains open;
// every address returned by [[Core.NativeLibrary.symbol]] becomes invalid after [[Core.NativeLibrary.close]].
// Dropping the value closes it automatically.
#[Swag.NoCopy]
struct NativeLibrary
{
    internal handle: #null *void     // Platform module handle, or null while closed.
}

impl NativeLibrary
{
    mtd opDrop()
    {
        .close()
    }

    // Reports whether a native library is currently loaded.
    mtd const isOpen()->bool => .handle != null

    // Resolves an exported symbol, or returns null when the library has no export by that name.
    //
    // The returned address is borrowed from this library and remains valid only until [[Core.NativeLibrary.close]].
    mtd const symbol(name: string)->#null const *void
    {
        if !.handle do
            return null
        return nativeLibrarySymbol(.handle!, name)
    }

    // Releases the loaded library. Repeated calls have no effect.
    //
    // Every address returned by [[Core.NativeLibrary.symbol]] becomes invalid.
    mtd close()
    {
        if !.handle do
            return
        closeNativeLibrary(.handle!)
        .handle = null
    }

    // Loads a native library from `path`.
    //
    // The returned owner closes the library automatically. Loading fails when the platform loader
    // cannot resolve the file or one of its dependencies.
    func load(path: string)->NativeLibrary fail
    {
        var result: retval
        result.handle = try loadNativeLibrary(path)

        let runtimeHook = nativeLibrarySymbol(result.handle!, SwagRuntimeHookSymbol)
        if runtimeHook
        {
            let sync = cast(func(u64, u64, u64, const *#null string)) runtimeHook!
            sync(SwagRuntimeHookSync, @getcontext().runtimeTlsIdPlusOne, cast(u64) @getcontext().runtimeFlags, &@pinfos.args)
        }

        return result
    }
}
