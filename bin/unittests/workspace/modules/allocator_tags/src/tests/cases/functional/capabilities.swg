#global if #command == Swag.CompilerCommand.Test

#test
{
    Swag.require(#hastag("Swag.AllocatorSafety") == #gettag("test.allocatorSafety", bool, #cfg == "devmode"))
    Swag.require(#hastag("Swag.AllocatorDiagnostics") == #gettag("test.allocatorDiagnostics", bool, #cfg == "devmode"))

    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let itf = Swag.makeInterface(&allocator, #typeof(allocator), Swag.IAllocator)
    for size in [64'u64, 128 * 1024]
    {
        var request = Swag.AllocatorRequest{size: size}
        itf.alloc(&request)
        Swag.require(request.address != null)
        itf.free(&request)
    }
    Swag.require(allocator.stats().countAlloc == 0)
}
