using Core

func verifyExpandedContextSlot(library: *NativeLibrary)
{
    let hookSymbol    = library.symbol("__swc_rt_stage")
    let contextSymbol = library.symbol("ctx_dynamic_read_context")
    let failureSymbol = library.symbol("ctx_dynamic_catches_core_failure")
    Swag.assert(hookSymbol != null and contextSymbol != null and failureSymbol != null)
    let hook           = cast(func(u64, u64, u64, const *(string?))) hookSymbol
    let readContext    = cast(func()->*Swag.Context) contextSymbol
    let catchesFailure = cast(func()->bool) failureSymbol
    let previous       = Swag.getContext()
    let previousSlot   = previous.runtimeTlsIdPlusOne
    let flags          = cast(u64) previous.runtimeFlags
    let arguments      = &Swag.processInfos().args

    var slots: [65] u32
    var count = 0'u64
    defer
    {
        for i in count do discard Win32.TlsFree(slots[i])
    }

    var expandedSlot = Win32.TLS_OUT_OF_INDEXES
    while count < slots.count
    {
        let slot = Win32.TlsAlloc()
        Swag.assert(slot != Win32.TLS_OUT_OF_INDEXES)
        slots[count] = slot
        count        += 1
        if slot >= 64
        {
            expandedSlot = slot
            break
        }
    }
    Swag.assert(expandedSlot != Win32.TLS_OUT_OF_INDEXES)

    var alternate = previous[]
    Swag.assert(Win32.TlsSetValue(expandedSlot, &alternate) != 0)
    defer discard Win32.TlsSetValue(expandedSlot, null)
    hook(0, expandedSlot + 1, flags, arguments)
    defer
    {
        hook(0, previousSlot, flags, arguments)
        discard Swag.getContext()
    }

    // The direct TEB array ends at slot 63. Modules adopted into a larger slot
    // must still see context replacement and propagate fallible calls correctly.
    Swag.assert(readContext() == &alternate)
    Swag.assert(Win32.TlsSetValue(expandedSlot, previous) != 0)
    Swag.assert(readContext() == previous)
    Swag.assert(catchesFailure())
}

func verifyDynamicallyLoadedRuntimeContext()
{
    const Prefix = "--dynamic-runtime-library="
    var path = ""
    for argument in Env.arguments() where argument.count > Prefix.count and argument[0 until Prefix.count] == Prefix do
        path = argument[Prefix.count until argument.count]

    Swag.assert(path.count != 0)
    var library = expect NativeLibrary.load(path)

    let symbol = library.symbol("ctx_dynamic_catches_core_failure")
    Swag.assert(symbol != null)
    let catchesCoreFailure = cast(func()->bool) symbol
    Swag.assert(catchesCoreFailure())

    verifyExpandedContextSlot(&library)

    let countsSymbol = library.symbol("ctx_dynamic_lifecycle_counts")
    Swag.assert(countsSymbol != null)
    let lifecycleCounts = cast(func()->u64) countsSymbol
    Swag.assert(lifecycleCounts() == 0x0000000100000001)

    var second = expect NativeLibrary.load(path)
    Swag.assert(lifecycleCounts() == 0x0000000100000001)

    var dropCount = 0'u32
    let setDropCounterSymbol = library.symbol("ctx_dynamic_set_drop_counter")
    Swag.assert(setDropCounterSymbol != null)
    let setDropCounter = cast(func(*u32)) setDropCounterSymbol
    setDropCounter(&dropCount)

    library.close()
    Swag.assert(dropCount == 0)
    second.close()
    Swag.assert(dropCount == 1)

    var reloaded = expect NativeLibrary.load(path)
    let reloadedCountsSymbol = reloaded.symbol("ctx_dynamic_lifecycle_counts")
    Swag.assert(reloadedCountsSymbol != null)
    let reloadedLifecycleCounts = cast(func()->u64) reloadedCountsSymbol
    Swag.assert(reloadedLifecycleCounts() == 0x0000000100000001)

    let reloadedSetDropCounterSymbol = reloaded.symbol("ctx_dynamic_set_drop_counter")
    Swag.assert(reloadedSetDropCounterSymbol != null)
    let reloadedSetDropCounter = cast(func(*u32)) reloadedSetDropCounterSymbol
    reloadedSetDropCounter(&dropCount)
    reloaded.close()
    Swag.assert(dropCount == 2)
}

#main {}

#test
{
    verifyDynamicallyLoadedRuntimeContext()
}
