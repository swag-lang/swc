using Core

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
    let catchesCoreFailure = cast(func()->bool) symbol!
    Swag.assert(catchesCoreFailure())

    let countsSymbol = library.symbol("ctx_dynamic_lifecycle_counts")
    Swag.assert(countsSymbol != null)
    let lifecycleCounts = cast(func()->u64) countsSymbol!
    Swag.assert(lifecycleCounts() == 0x0000000100000001)

    var second = expect NativeLibrary.load(path)
    Swag.assert(lifecycleCounts() == 0x0000000100000001)

    var dropCount            = 0'u32
    let setDropCounterSymbol = library.symbol("ctx_dynamic_set_drop_counter")
    Swag.assert(setDropCounterSymbol != null)
    let setDropCounter = cast(func(*u32)) setDropCounterSymbol!
    setDropCounter(&dropCount)

    library.close()
    Swag.assert(dropCount == 0)
    second.close()
    Swag.assert(dropCount == 1)

    var reloaded             = expect NativeLibrary.load(path)
    let reloadedCountsSymbol = reloaded.symbol("ctx_dynamic_lifecycle_counts")
    Swag.assert(reloadedCountsSymbol != null)
    let reloadedLifecycleCounts = cast(func()->u64) reloadedCountsSymbol!
    Swag.assert(reloadedLifecycleCounts() == 0x0000000100000001)

    let reloadedSetDropCounterSymbol = reloaded.symbol("ctx_dynamic_set_drop_counter")
    Swag.assert(reloadedSetDropCounterSymbol != null)
    let reloadedSetDropCounter = cast(func(*u32)) reloadedSetDropCounterSymbol!
    reloadedSetDropCounter(&dropCount)
    reloaded.close()
    Swag.assert(dropCount == 2)
}

#main {}

#test
{
    verifyDynamicallyLoadedRuntimeContext()
}
