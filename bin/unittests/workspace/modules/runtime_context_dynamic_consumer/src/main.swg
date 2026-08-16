using Core

func verifyDynamicallyLoadedRuntimeContext()
{
    const Prefix = "--dynamic-runtime-library="
    var path = ""
    for argument in Env.arguments() where @countof(argument) > @countof(Prefix) and argument[0 until @countof(Prefix)] == Prefix do
        path = argument[@countof(Prefix) until @countof(argument)]

    @assert(@countof(path) != 0)
    var library = expect NativeLibrary.load(path)

    let symbol = library.symbol("ctx_dynamic_catches_core_failure")
    @assert(symbol != null)
    let catchesCoreFailure = cast(func()->bool) symbol!
    @assert(catchesCoreFailure())

    let countsSymbol = library.symbol("ctx_dynamic_lifecycle_counts")
    @assert(countsSymbol != null)
    let lifecycleCounts = cast(func()->u64) countsSymbol!
    @assert(lifecycleCounts() == 0x0000000100000001)

    var second = expect NativeLibrary.load(path)
    @assert(lifecycleCounts() == 0x0000000100000001)

    var dropCount = 0'u32
    let setDropCounterSymbol = library.symbol("ctx_dynamic_set_drop_counter")
    @assert(setDropCounterSymbol != null)
    let setDropCounter = cast(func(*u32)) setDropCounterSymbol!
    setDropCounter(&dropCount)

    library.close()
    @assert(dropCount == 0)
    second.close()
    @assert(dropCount == 1)

    var reloaded = expect NativeLibrary.load(path)
    let reloadedCountsSymbol = reloaded.symbol("ctx_dynamic_lifecycle_counts")
    @assert(reloadedCountsSymbol != null)
    let reloadedLifecycleCounts = cast(func()->u64) reloadedCountsSymbol!
    @assert(reloadedLifecycleCounts() == 0x0000000100000001)

    let reloadedSetDropCounterSymbol = reloaded.symbol("ctx_dynamic_set_drop_counter")
    @assert(reloadedSetDropCounterSymbol != null)
    let reloadedSetDropCounter = cast(func(*u32)) reloadedSetDropCounterSymbol!
    reloadedSetDropCounter(&dropCount)
    reloaded.close()
    @assert(dropCount == 2)
}

#main {}

#test
{
    verifyDynamicallyLoadedRuntimeContext()
}
