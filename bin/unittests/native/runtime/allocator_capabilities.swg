#global private

#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    Swag.assert(allocator.detectLeaks == #hastag("Swag.AllocatorDiagnostics"))
    allocator.configure(false, false, false, false, false)

    let itf     = Swag.makeInterface(&allocator, #typeof(allocator), Swag.IAllocator)
    var request = Swag.AllocatorRequest{size: 128}
    itf.alloc(&request)
    Swag.assert(request.address != null)
    itf.free(&request)
    Swag.assert(allocator.stats().countAlloc == 0)
}

#static if not #hastag("Swag.AllocatorDiagnostics")
{
    #test
    {
        for mode in 5
        {
            let caught = Swag.catchPanic(func|mode|() {
                var allocator: Swag.Allocator
                allocator.setup()
                allocator.configure(mode == 0, mode == 1, mode == 2, mode == 3, mode == 4)
            })
            Swag.assert(caught.raised)
            Swag.assert(caught.message() == "allocator diagnostics need compiler tag 'Swag.AllocatorDiagnostics'; add '--tag Swag.AllocatorDiagnostics' before compiling")
        }
    }
}
