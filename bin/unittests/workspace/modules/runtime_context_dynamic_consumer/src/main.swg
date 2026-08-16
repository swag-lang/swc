using Core

func verifyDynamicallyLoadedRuntimeContext()
{
    const Prefix = "--dynamic-runtime-library="
    var path = ""
    for argument in Env.arguments() where @countof(argument) > @countof(Prefix) and argument[0 until @countof(Prefix)] == Prefix do
        path = argument[@countof(Prefix) until @countof(argument)]

    @assert(@countof(path) != 0)
    var library = expect NativeLibrary.load(path)
    defer library.close()

    let symbol = library.symbol("ctx_dynamic_catches_core_failure")
    @assert(symbol != null)
    let catchesCoreFailure = cast(func()->bool) symbol!
    @assert(catchesCoreFailure())
}

#main {}

#test
{
    verifyDynamicallyLoadedRuntimeContext()
}
