#global private //

using Swag

const BufSize = 4096'u64

func makeScratchAllocator(scratch: *ScratchAllocator, alloc: *Allocator)->IAllocator
{
    alloc.setup()
    alloc.configure(false, false, false, false, false)
    let itf = @mkinterface(alloc, #typeof(dref alloc), IAllocator)
    scratch.setCapacity(BufSize, itf)
    return @mkinterface(scratch, #typeof(dref scratch), IAllocator)
}

// Basic alloc and free
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)
    @assert(req.address != null)
    @assert(scratch.used >= 64)

    req.size = 64
    itf.free(&req)
    @assert(req.address == null)

    scratch.release()
}

// Alloc fits in buffer, used advances
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 100
    itf.alloc(&req)
    @assert(scratch.used >= 100)

    let usedAfterFirst = scratch.used

    var req2: AllocatorRequest
    req2.size = 200
    itf.alloc(&req2)
    @assert(scratch.used >= usedAfterFirst + 200)

    scratch.release()
}

// Free last allocation reclaims space
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 128
    itf.alloc(&req)

    let usedBefore = scratch.used

    // Allocate another block
    var req2: AllocatorRequest
    req2.size = 64
    itf.alloc(&req2)
    @assert(scratch.used > usedBefore)

    // Free last block reclaims
    req2.size = 64
    itf.free(&req2)
    @assert(scratch.used == usedBefore)

    scratch.release()
}

// Free non-last allocation does not reclaim
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req1: AllocatorRequest
    req1.size = 64
    itf.alloc(&req1)

    var req2: AllocatorRequest
    req2.size = 64
    itf.alloc(&req2)

    let usedBefore = scratch.used

    // Free first block (not last) does nothing to used
    req1.size = 64
    itf.free(&req1)
    @assert(scratch.used == usedBefore)

    scratch.release()
}

// Alloc size 0 returns null
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 0
    itf.alloc(&req)
    @assert(req.address == null)

    scratch.release()
}

// Free null is no-op
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.address = null
    itf.free(&req)
    @assert(req.address == null)

    scratch.release()
}

// Write and read data
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 256
    itf.alloc(&req)

    let ptr = cast([*] u8) req.address
    for i in 256 do
        ptr[i] = cast(u8) ((i * 3 + 5) & 0xFF)

    for i in 256 do
        @assert(ptr[i] == cast(u8) ((i * 3 + 5) & 0xFF))

    scratch.release()
}

// Multiple allocations fill buffer sequentially
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var ptrs: [4] *void
    for i in 4
    {
        var req: AllocatorRequest
        req.size = 64
        itf.alloc(&req)
        @assert(req.address != null)
        ptrs[i] = req.address
    }

    // Pointers should be distinct and in increasing order (linear allocator)
    for i in 1 until 4 do
        @assert(cast(u64) ptrs[i] > cast(u64) ptrs[i - 1])

    scratch.release()
}

// Overflow to leak: allocation larger than remaining capacity
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill most of the buffer
    var req1: AllocatorRequest
    req1.size = BufSize - 64
    itf.alloc(&req1)
    @assert(req1.address != null)

    // This should overflow to the underlying allocator (leak)
    var req2: AllocatorRequest
    req2.size = 256
    itf.alloc(&req2)
    @assert(req2.address != null)
    @assert(scratch.totalLeak >= 256)

    // Write to it to verify usability
    let ptr = cast([*] u8) req2.address
    ptr[0] = 0xAA
    ptr[255] = 0xBB
    @assert(ptr[0] == 0xAA)
    @assert(ptr[255] == 0xBB)

    scratch.release()
}

// Leak is freed when explicitly freed
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill buffer
    var req1: AllocatorRequest
    req1.size = BufSize - 64
    itf.alloc(&req1)

    // Leak allocation
    var req2: AllocatorRequest
    req2.size = 128
    itf.alloc(&req2)
    @assert(scratch.totalLeak >= 128)

    // Free the leak
    req2.size = 128
    itf.free(&req2)
    @assert(scratch.totalLeak == 0)

    scratch.release()
}

// FreeAll clears used and leaks
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Allocate in buffer
    var req1: AllocatorRequest
    req1.size = 100
    itf.alloc(&req1)

    // Force leak
    var req2: AllocatorRequest
    req2.size = BufSize
    itf.alloc(&req2)

    @assert(scratch.used > 0)
    @assert(scratch.totalLeak > 0)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)

    @assert(scratch.used == 0)
    @assert(scratch.firstLeak == null)

    scratch.release()
}

// maxUsed tracks peak usage
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 512
    itf.alloc(&req)

    let peak = scratch.maxUsed
    @assert(peak >= 512)

    // Free last
    req.size = 512
    itf.free(&req)

    // maxUsed should still reflect the peak
    @assert(scratch.maxUsed == peak)

    scratch.release()
}

// maxLeak tracks peak leak
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill buffer
    var req1: AllocatorRequest
    req1.size = BufSize - 64
    itf.alloc(&req1)

    // Leak
    var req2: AllocatorRequest
    req2.size = 200
    itf.alloc(&req2)

    let peak = scratch.maxLeak
    @assert(peak >= 200)

    // Free leak
    req2.size = 200
    itf.free(&req2)

    // maxLeak still reflects peak
    @assert(scratch.maxLeak == peak)

    scratch.release()
}

// Realloc within buffer copies data
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 32
    itf.alloc(&req)

    let ptr = cast([*] u8) req.address
    for i in 32 do
        ptr[i] = cast(u8) (i + 1)

    req.oldSize = 32
    req.size = 128
    itf.realloc(&req)
    @assert(req.address != null)

    let newPtr = cast([*] u8) req.address
    for i in 32 do
        @assert(newPtr[i] == cast(u8) (i + 1))

    scratch.release()
}

// Sequential alloc-free cycles
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    for i in 20
    {
        var req: AllocatorRequest
        req.size = 64
        itf.alloc(&req)
        @assert(req.address != null)

        // Free last immediately to reclaim
        req.size = 64
        itf.free(&req)
    }

    // Buffer should be back to 0 since we always free the last
    @assert(scratch.used == 0)

    scratch.release()
}

// Small allocation (1 byte)
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 1
    itf.alloc(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0xFF
    @assert(ptr[0] == 0xFF)

    scratch.release()
}

// FreeAll then reuse
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill some space
    var req: AllocatorRequest
    req.size = 1024
    itf.alloc(&req)

    // FreeAll resets
    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    @assert(scratch.used == 0)

    // Allocate again
    var req2: AllocatorRequest
    req2.size = 512
    itf.alloc(&req2)
    @assert(req2.address != null)
    @assert(scratch.used >= 512)

    scratch.release()
}

// Multiple leaks tracked and freed
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill buffer
    var fill: AllocatorRequest
    fill.size = BufSize - 64
    itf.alloc(&fill)

    // Create several leaks
    var leaks: [3] AllocatorRequest
    for i in 3
    {
        leaks[i].size = 100
        itf.alloc(&leaks[i])
        @assert(leaks[i].address != null)
    }

    @assert(scratch.totalLeak >= 300)

    // Free leaks one by one
    for i in 3
    {
        leaks[i].size = 100
        itf.free(&leaks[i])
    }

    @assert(scratch.totalLeak == 0)

    scratch.release()
}

// 32-bit typed writes
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 40
    req.alignment = 8
    itf.alloc(&req)

    let vals = cast([*] u32) req.address
    for i in 10 do
        vals[i] = cast(u32) (i * 777 + 11)

    for i in 10 do
        @assert(vals[i] == cast(u32) (i * 777 + 11))

    scratch.release()
}

// Release frees the buffer
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)

    scratch.release()
    @assert(scratch.block == null)
    @assert(scratch.used == 0)
}

// Realloc with size 0 frees
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)

    req.oldSize = 64
    req.size = 0
    itf.realloc(&req)
    @assert(req.address == null)

    scratch.release()
}

// Realloc from null acts like alloc
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.address = null
    req.size = 200
    itf.realloc(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 1
    ptr[199] = 2
    @assert(ptr[0] == 1)
    @assert(ptr[199] == 2)

    scratch.release()
}

// Capacity and block are set correctly
#test
{
    var alloc: Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    @assert(scratch.capacity == BufSize)
    @assert(scratch.block != null)

    scratch.release()
}