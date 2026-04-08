#global fileprivate //

using Swag

func makeDebugAllocator(da: *DebugAllocator, sa: *SystemAllocator)->IAllocator
{
    let sysItf = @mkinterface(sa, #typeof(dref sa), IAllocator)
    da.setup(sysItf)
    da.detectLeaks = false
    return @mkinterface(da, #typeof(dref da), IAllocator)
}

// Basic alloc and free
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(da.countAlloc == 1)
    @assert(da.sizeAlloc == 64)

    req.mode = .Free
    req.size = 64
    itf.req(&req)
    @assert(req.address == null)
    @assert(da.countAlloc == 0)
    @assert(da.sizeAlloc == 0)
}

// Newly allocated memory is filled with 0xAB
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 32
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 32 do
        @assert(ptr[i] == 0xAB)

    req.mode = .Free
    req.size = 32
    itf.req(&req)
}

// Free null address is a no-op
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Free
    req.address = null
    itf.req(&req)
    @assert(req.address == null)
    @assert(da.countAlloc == 0)
}

// Alloc with size 0 returns null
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)
    @assert(da.countAlloc == 0)
}

// Realloc from null acts like alloc
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Realloc
    req.address = null
    req.size = 100
    itf.req(&req)
    @assert(req.address != null)
    @assert(da.countAlloc == 1)
    @assert(da.sizeAlloc == 100)

    // New alloc from null should be filled with 0xAB
    let ptr = cast([*] u8) req.address
    for i in 100 do
        @assert(ptr[i] == 0xAB)

    req.mode = .Free
    req.size = 100
    itf.req(&req)
}

// Realloc grow preserves data, new bytes filled with 0xAB
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 16
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 16 do
        ptr[i] = cast(u8) i

    req.mode = .Realloc
    req.oldSize = 16
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(da.countAlloc == 1)
    @assert(da.sizeAlloc == 64)

    let newPtr = cast([*] u8) req.address
    // Original data preserved
    for i in 16 do
        @assert(newPtr[i] == cast(u8) i)
    // New area filled with 0xAB
    for i in 16 until 64 do
        @assert(newPtr[i] == 0xAB)

    req.mode = .Free
    req.size = 64
    itf.req(&req)
}

// Realloc shrink preserves leading data
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 128 do
        ptr[i] = cast(u8) (i & 0xFF)

    req.mode = .Realloc
    req.oldSize = 128
    req.size = 32
    itf.req(&req)
    @assert(req.address != null)
    @assert(da.countAlloc == 1)
    @assert(da.sizeAlloc == 32)

    let newPtr = cast([*] u8) req.address
    for i in 32 do
        @assert(newPtr[i] == cast(u8) (i & 0xFF))

    req.mode = .Free
    req.size = 32
    itf.req(&req)
}

// Write and read data through allocated memory
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 256
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 256 do
        ptr[i] = cast(u8) ((i * 13 + 7) & 0xFF)

    for i in 256 do
        @assert(ptr[i] == cast(u8) ((i * 13 + 7) & 0xFF))

    req.mode = .Free
    req.size = 256
    itf.req(&req)
}

// Multiple allocations tracked correctly
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var reqs: [4] AllocatorRequest
    var sizes: [4] u64 = [32, 64, 128, 256]

    for i in 4
    {
        reqs[i].mode = .Alloc
        reqs[i].size = sizes[i]
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)
    }

    @assert(da.countAlloc == 4)
    @assert(da.sizeAlloc == 32 + 64 + 128 + 256)

    // Free in reverse order
    for #reverse i in 4
    {
        reqs[i].mode = .Free
        reqs[i].size = sizes[i]
        itf.req(&reqs[i])
    }

    @assert(da.countAlloc == 0)
    @assert(da.sizeAlloc == 0)
}

// Free in forward order
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var reqs: [3] AllocatorRequest
    for i in 3
    {
        reqs[i].mode = .Alloc
        reqs[i].size = (i + 1) * 50
        itf.req(&reqs[i])
    }

    @assert(da.countAlloc == 3)

    for i in 3
    {
        reqs[i].mode = .Free
        reqs[i].size = (i + 1) * 50
        itf.req(&reqs[i])
    }

    @assert(da.countAlloc == 0)
    @assert(da.sizeAlloc == 0)
}

// checkAllMemory passes on valid state
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 100
    itf.req(&req)

    da.checkAllMemory()

    req.mode = .Free
    req.size = 100
    itf.req(&req)

    da.checkAllMemory()
}

// assertIsAllocated on valid block
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)

    da.assertIsAllocated(req.address)

    req.mode = .Free
    req.size = 64
    itf.req(&req)
}

// assertIsAllocated with null is no-op
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    da.assertIsAllocated(null)
}

// AssertIsAllocated mode via interface
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 48
    itf.req(&req)
    let addr = req.address

    var checkReq: AllocatorRequest
    checkReq.mode = .AssertIsAllocated
    checkReq.address = addr
    itf.req(&checkReq)

    req.mode = .Free
    req.size = 48
    itf.req(&req)
}

// AssertIsAllocated with null via interface is no-op
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var checkReq: AllocatorRequest
    checkReq.mode = .AssertIsAllocated
    checkReq.address = null
    itf.req(&checkReq)
}

// Allocation IDs increment
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    let startId = da.nextId

    var req1: AllocatorRequest
    req1.mode = .Alloc
    req1.size = 16
    itf.req(&req1)
    @assert(da.nextId == startId + 1)

    var req2: AllocatorRequest
    req2.mode = .Alloc
    req2.size = 16
    itf.req(&req2)
    @assert(da.nextId == startId + 2)

    req1.mode = .Free
    req1.size = 16
    itf.req(&req1)

    req2.mode = .Free
    req2.size = 16
    itf.req(&req2)
}

// Alignment is respected
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var alignments: [5] u32 = [8, 16, 32, 64, 128]
    for a in 5
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 256
        req.alignment = alignments[a]
        itf.req(&req)
        @assert(req.address != null)
        @assert(cast(u64) req.address % cast(u64) alignments[a] == 0)

        req.mode = .Free
        req.size = 256
        itf.req(&req)
    }
}

// Sequential alloc-free cycles
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    for i in 30
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = (i + 1) * 8
        itf.req(&req)
        @assert(req.address != null)
        @assert(da.countAlloc == 1)

        req.mode = .Free
        req.size = (i + 1) * 8
        itf.req(&req)
        @assert(da.countAlloc == 0)
    }
}

// Free quarantine tracking (sizeFree increases after free)
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)
    da.maxFreeSize = 1024 * 1024

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 200
    itf.req(&req)

    let beforeFree = da.sizeFree
    req.mode = .Free
    req.size = 200
    itf.req(&req)
    @assert(da.sizeFree == beforeFree + 200)
}

// Realloc chain: grow several times
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 8
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 8 do
        ptr[i] = cast(u8) (i + 10)

    var prevSize = 8'u64
    var sizes: [3] u64 = [32, 128, 512]
    for s in 3
    {
        req.mode = .Realloc
        req.oldSize = prevSize
        req.size = sizes[s]
        itf.req(&req)
        @assert(req.address != null)
        @assert(da.countAlloc == 1)
        @assert(da.sizeAlloc == sizes[s])

        let p = cast([*] u8) req.address
        for i in 8 do
            @assert(p[i] == cast(u8) (i + 10))

        prevSize = sizes[s]
    }

    req.mode = .Free
    req.size = 512
    itf.req(&req)
}

// Small allocation (1 byte)
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    @assert(ptr[0] == 0xAB)
    ptr[0] = 0x42
    @assert(ptr[0] == 0x42)

    req.mode = .Free
    req.size = 1
    itf.req(&req)
}

// Large allocation
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1024 * 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(da.sizeAlloc == 1024 * 64)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0x01
    ptr[1024 * 64 - 1] = 0x02
    @assert(ptr[0] == 0x01)
    @assert(ptr[1024 * 64 - 1] == 0x02)

    req.mode = .Free
    req.size = 1024 * 64
    itf.req(&req)
}

// Multiple allocations all valid, then checkAllMemory
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var reqs: [5] AllocatorRequest
    for i in 5
    {
        reqs[i].mode = .Alloc
        reqs[i].size = (i + 1) * 20
        itf.req(&reqs[i])
    }

    da.checkAllMemory()

    // Free some
    reqs[0].mode = .Free
    reqs[0].size = 20
    itf.req(&reqs[0])

    reqs[2].mode = .Free
    reqs[2].size = 60
    itf.req(&reqs[2])

    da.checkAllMemory()

    // Free rest
    reqs[1].mode = .Free
    reqs[1].size = 40
    itf.req(&reqs[1])

    reqs[3].mode = .Free
    reqs[3].size = 80
    itf.req(&reqs[3])

    reqs[4].mode = .Free
    reqs[4].size = 100
    itf.req(&reqs[4])

    @assert(da.countAlloc == 0)
    @assert(da.sizeAlloc == 0)
    da.checkAllMemory()
}

// 32-bit typed writes
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 40
    req.alignment = 8
    itf.req(&req)

    let vals = cast([*] u32) req.address
    for i in 10 do
        vals[i] = cast(u32) (i * 1000 + 42)

    for i in 10 do
        @assert(vals[i] == cast(u32) (i * 1000 + 42))

    req.mode = .Free
    req.size = 40
    itf.req(&req)
}

// Realloc same size
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 64 do
        ptr[i] = cast(u8) (i & 0xFF)

    req.mode = .Realloc
    req.oldSize = 64
    req.size = 64
    itf.req(&req)
    @assert(da.countAlloc == 1)
    @assert(da.sizeAlloc == 64)

    let newPtr = cast([*] u8) req.address
    for i in 64 do
        @assert(newPtr[i] == cast(u8) (i & 0xFF))

    req.mode = .Free
    req.size = 64
    itf.req(&req)
}

// FreeAll mode clears all tracking
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req1: AllocatorRequest
    req1.mode = .Alloc
    req1.size = 50
    itf.req(&req1)

    var req2: AllocatorRequest
    req2.mode = .Alloc
    req2.size = 75
    itf.req(&req2)

    @assert(da.countAlloc == 2)

    var freeAll: AllocatorRequest
    freeAll.mode = .FreeAll
    itf.req(&freeAll)

    @assert(da.countAlloc == 0)
    @assert(da.sizeAlloc == 0)
}

// All distinct pointers
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var ptrs: [6] *void
    for i in 6
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 32
        itf.req(&req)
        ptrs[i] = req.address
    }

    for i in 6
    {
        for j in 6
        {
            if i != j do
                @assert(ptrs[i] != ptrs[j])
        }
    }

    for i in 6
    {
        var req: AllocatorRequest
        req.mode = .Free
        req.address = ptrs[i]
        req.size = 32
        itf.req(&req)
    }
}

// Realloc from 1 byte to large
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0x42

    req.mode = .Realloc
    req.oldSize = 1
    req.size = 4096
    itf.req(&req)
    @assert(req.address != null)

    let newPtr = cast([*] u8) req.address
    @assert(newPtr[0] == 0x42)
    // New area filled with 0xAB
    for i in 1 until 4096 do
        @assert(newPtr[i] == 0xAB)

    req.mode = .Free
    req.size = 4096
    itf.req(&req)
}

// Alignment 256 with checkAllMemory
#test
{
    var sa: SystemAllocator
    var da: DebugAllocator
    let itf = makeDebugAllocator(&da, &sa)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 512
    req.alignment = 256
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 256 == 0)

    da.checkAllMemory()

    req.mode = .Free
    req.size = 512
    itf.req(&req)
}
