#global private

using Swag

func contractAllocator(allocator: *Allocator, electric = false)->IAllocator
{
    allocator.setup()
    allocator.configure(electric, false, false, false, false)
    return Swag.makeInterface(allocator, #typeof(allocator[]), IAllocator)
}

// An eight-byte page slot can need a new address when its alignment is strengthened.
#test
{
    var allocator: Allocator
    let itf = contractAllocator(&allocator)
    var blocks:    [2] AllocatorRequest
    for &block in blocks
    {
        block.size      = 8
        block.alignment = 8
        itf.alloc(block)
        Swag.assert(block.address != null)
    }
    defer for &block in blocks do itf.free(block)

    let index   = (cast(u64) blocks[0].address & 15) != 0 ? 0 : 1
    let request = &blocks[index]
    Swag.assert((cast(u64) request.address & 15) == 8)
    let bytes = cast([*] u8) request.address!
    for i in 8 do bytes[i] = cast(u8) (i + 17)
    request.oldSize   = 8
    request.alignment = 16
    itf.realloc(request)
    Swag.assert(request.address != null)
    Swag.assert((cast(u64) request.address & 15) == 0)
    for i in 8 do Swag.assert((cast([*] u8) request.address)[i] == cast(u8) (i + 17))
    let aligned = request.address
    for alignment in [16'u32, 8'u32, 0'u32]
    {
        request.alignment = alignment
        itf.realloc(request)
        Swag.assert(request.address == aligned)
    }
}

// Class slack is not readable storage when an electric allocation abuts its guard.
#test
{
    var allocator: Allocator
    let itf = contractAllocator(&allocator, electric: true)
    for alignment in [16'u32, 64'u32]
    {
        var request: AllocatorRequest
        request.size      = 129
        request.alignment = alignment
        itf.alloc(&request)
        Swag.assert(request.address != null)
        defer itf.free(&request)
        for i in 129 do (cast([*] u8) request.address)[i] = cast(u8) i
        request.oldSize = 129
        request.size    = 200
        itf.realloc(&request)
        Swag.assert(request.address != null)
        for i in 129 do Swag.assert((cast([*] u8) request.address)[i] == cast(u8) i)
        request.oldSize = 200
        request.size    = 17
        itf.realloc(&request)
        Swag.assert(request.address != null)
        Swag.assert((cast(u64) request.address & (alignment - 1)) == 0)
        for i in 17 do Swag.assert((cast([*] u8) request.address)[i] == cast(u8) i)
    }
}

// Allocation arithmetic must reject impossible sizes even without overflow guards.
#test
{
    for electric in [false, true]
    {
        var allocator: Allocator
        let itf = contractAllocator(&allocator, electric)
        for alignment in [0'u32, 64'u32, 0x8000_0000'u32]
        {
            for size in [Swag.U64.Max, Swag.U64.Max - 4095, Swag.U64.Max - 8191]
            {
                var request: AllocatorRequest
                request.size      = size
                request.alignment = alignment
                itf.alloc(&request)
                defer itf.free(&request)
                Swag.assert(request.address == null)
            }
        }
        Swag.assert(allocator.stats().countAlloc == 0)
    }
}

// Bulk release must return ordinary header allocations as well as tracked ones.
#test
{
    for tracked in [false, true]
    {
        var allocator: Allocator
        let itf = contractAllocator(&allocator)
        allocator.configure(false, false, false, tracked, false)
        let before = allocator.stats().sizeCommitted
        for size in [131072'u64, 1048576'u64]
        {
            var request: AllocatorRequest
            request.size = size
            itf.alloc(&request)
            Swag.assert(request.address != null)
            request.alignment = 64
            itf.alloc(&request)
            Swag.assert(request.address != null)
        }
        Swag.assert(allocator.stats().sizeCommitted > before)
        var request: AllocatorRequest
        itf.freeAll(&request)
        Swag.assert(allocator.stats().countAlloc == 0)
        Swag.assert(allocator.stats().sizeCommitted == before)
        itf.freeAll(&request)
        Swag.assert(allocator.stats().sizeCommitted == before)
        request.size      = 8
        request.alignment = 64
        itf.alloc(&request)
        Swag.assert(request.address != null)
        itf.freeAll(&request)
        Swag.assert(allocator.stats().sizeCommitted == before)

        // Switching the active thread heap may retire another allocator's pages. Check page
        // ownership separately from the process-wide commitment delta of the headers above.
        request.alignment = 0
        itf.alloc(&request)
        Swag.assert(request.address != null)
        itf.freeAll(&request)
        Swag.assert(allocator.stats().countPage == 0)
        Swag.assert(allocator.stats().countAlloc == 0)
    }
}

// A rejected realloc leaves the old allocation live even though the output address is null.
#test
{
    var allocator: Allocator
    let itf = contractAllocator(&allocator)
    var request:   AllocatorRequest
    request.size = 129
    itf.alloc(&request)
    let original = request
    Swag.assert(original.address != null)
    (cast([*] u8) original.address)[0] = 73
    let before = allocator.stats().sizeCommitted
    for size in [Swag.U64.Max, 200'u64]
    {
        request           = original
        request.oldSize   = original.size
        request.size      = size
        request.alignment = size == 200 ? 3'u32 : 16'u32
        itf.realloc(&request)
        Swag.assert(request.address == null)
        Swag.assert(allocator.stats().countAlloc == 1)
        Swag.assert(allocator.stats().sizeCommitted == before)
        Swag.assert((cast([*] u8) original.address)[0] == 73)
    }
    request = original
    itf.free(&request)
}
