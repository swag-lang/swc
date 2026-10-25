#run
{
    let cfg = unwrap Swag.compiler().getBuildCfg()
    // Only the test command supplies an entry point for this test-only module.
    cfg.backendKind = #command == Swag.CompilerCommand.Test ? .Executable : .Export

    // Setup can change language guards, but cannot change its allocator's compiled capabilities.
    let hasSafety      = #hastag("Swag.AllocatorSafety")
    let hasDiagnostics = #hastag("Swag.AllocatorDiagnostics")
    Swag.assert(hasSafety == #gettag("test.allocatorSafety", bool, #cfg == "devmode"))
    Swag.assert(hasDiagnostics == #gettag("test.allocatorDiagnostics", bool, #cfg == "devmode"))

    cfg.safetyGuards = .None
    #static if #hastag("Swag.AllocatorDiagnostics") do
        cfg.allocatorLeaks = false

    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let itf     = Swag.makeInterface(&allocator, #typeof(allocator), Swag.IAllocator)
    var request = Swag.AllocatorRequest{size: 64}
    itf.alloc(&request)
    Swag.assert(request.address != null)
    itf.free(&request)
    Swag.assert(allocator.stats().countAlloc == 0)

    Swag.assert(#hastag("Swag.AllocatorSafety") == hasSafety)
    Swag.assert(#hastag("Swag.AllocatorDiagnostics") == hasDiagnostics)
}
