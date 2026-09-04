#global public

using Core.Errors

private const SwagRuntimeHookSymbol        = "__swc_rt_stage"
private const SwagRuntimeHookSync          = 0'u64
private const SwagRuntimeHookDynamicLoad   = 4'u64
private const SwagRuntimeHookDynamicUnload = 5'u64

private func callSwagRuntimeHook(handle: *void, stage: u64)
{
    let runtimeHook = nativeLibrarySymbol(handle, SwagRuntimeHookSymbol)
    if !runtimeHook do
        return

    let hook = cast(func(u64, u64, u64, const *(string?))) runtimeHook!
    hook(stage, Swag.getContext().runtimeTlsIdPlusOne, cast(u64) Swag.getContext().runtimeFlags, &Swag.processInfos().args)
}

// Owns one dynamically loaded native library.
//
// Loading may run code owned by the library. Resolve symbols only while this value remains open;
// every address returned by [[Core.NativeLibrary.symbol]] becomes invalid after [[Core.NativeLibrary.close]].
// Dropping the value closes it automatically.
#[Swag.NoCopy]
struct NativeLibrary
{
    internal handle: *void?     // Platform module handle, or null while closed.
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
    mtd const symbol(name: string)->const *void?
    {
        if !.handle do
            return null
        return nativeLibrarySymbol(.handle!, name)
    }

    // Releases the loaded library. Repeated calls have no effect.
    //
    // For a Swag library, this releases one dynamic lifecycle reference and runs its `#drop`
    // blocks before unloading when no static or dynamic owner remains. Every address returned by
    // [[Core.NativeLibrary.symbol]] becomes invalid.
    mtd close()
    {
        if !.handle do
            return
        callSwagRuntimeHook(.handle!, SwagRuntimeHookDynamicUnload)
        closeNativeLibrary(.handle!)
        .handle = null
    }

    // Loads a native library from `path`.
    //
    // The returned owner closes the library automatically. For a Swag library, loading adopts the
    // caller's runtime context and runs `#init` and `#premain` once before this function returns.
    // Repeated loads hold independent lifecycle references. Loading fails when the platform loader
    // cannot resolve the file or one of its dependencies.
    func load(path: string)->NativeLibrary fail
    {
        var result: retval
        result.handle = try loadNativeLibrary(path)

        callSwagRuntimeHook(result.handle!, SwagRuntimeHookSync)
        callSwagRuntimeHook(result.handle!, SwagRuntimeHookDynamicLoad)

        return result
    }
}
