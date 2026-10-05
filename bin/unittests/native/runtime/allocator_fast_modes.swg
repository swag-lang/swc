#global private

using Swag

// A ready page must not bypass filling, tracking, or electric mode after reconfiguration.
#test
{
    for mode in 3
    {
        var allocator: Allocator
        allocator.setup()
        defer allocator.releaseAll()
        let itf: IAllocator = &allocator

        var request: AllocatorRequest
        request.size = 32
        itf.alloc(&request)
        Swag.assert(request.address != null)
        itf.free(&request)

        allocator.configure(mode == 2, true, false, mode == 1, mode == 0)
        let address = allocator.allocateFast(32, 0)
        Swag.assert(address == 0)
    }
}
