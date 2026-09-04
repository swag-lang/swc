#global private     //

using Swag

const BufSize = 4096'u64

func makeScratchAllocator(scratch: *ScratchAllocator, alloc: *Allocator)->IAllocator
{
    alloc.setup()
    alloc.configure(false, false, false, false, false)
    let itf = Swag.makeInterface(alloc, #typeof(alloc[]), IAllocator)
    scratch.setCapacity(BufSize, itf)
    return Swag.makeInterface(scratch, #typeof(scratch[]), IAllocator)
}

// Basic alloc and free
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)
    Swag.assert(req.address != null)
    Swag.assert(scratch.used >= 64)

    req.size = 64
    itf.free(&req)
    Swag.assert(req.address == null)

    scratch.release()
}

// Alloc fits in buffer, used advances
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 100
    itf.alloc(&req)
    Swag.assert(scratch.used >= 100)

    let usedAfterFirst = scratch.used

    var req2: AllocatorRequest
    req2.size = 200
    itf.alloc(&req2)
    Swag.assert(scratch.used >= usedAfterFirst + 200)

    scratch.release()
}

// Free last allocation reclaims space
#test
{
    var alloc:   Allocator
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
    Swag.assert(scratch.used > usedBefore)

    // Free last block reclaims
    req2.size = 64
    itf.free(&req2)
    Swag.assert(scratch.used == usedBefore)

    scratch.release()
}

// Free non-last allocation does not reclaim
#test
{
    var alloc:   Allocator
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
    Swag.assert(scratch.used == usedBefore)

    scratch.release()
}

// Alloc size 0 returns null
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 0
    itf.alloc(&req)
    Swag.assert(req.address == null)

    scratch.release()
}

// Free null is no-op
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.address = null
    itf.free(&req)
    Swag.assert(req.address == null)

    scratch.release()
}

// Write and read data
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 256
    itf.alloc(&req)

    let ptr = cast([*] u8) req.address!
    for i in 256 do
        ptr[i] = cast(u8) ((i * 3 + 5) & 0xFF)

    for i in 256 do
        Swag.assert(ptr[i] == cast(u8) ((i * 3 + 5) & 0xFF))

    scratch.release()
}

// Multiple allocations fill buffer sequentially
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var ptrs: [4] (*void?)
    for i in 4
    {
        var req: AllocatorRequest
        req.size = 64
        itf.alloc(&req)
        Swag.assert(req.address != null)
        ptrs[i] = req.address
    }

    // Pointers should be distinct and in increasing order (linear allocator)
    for i in 1 until 4 do
        Swag.assert(cast(u64) ptrs[i] > cast(u64) ptrs[i - 1])

    scratch.release()
}

// Overflow to leak: allocation larger than remaining capacity
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill most of the buffer
    var req1: AllocatorRequest
    req1.size = BufSize - 64
    itf.alloc(&req1)
    Swag.assert(req1.address != null)

    // This should overflow to the underlying allocator (leak)
    var req2: AllocatorRequest
    req2.size = 256
    itf.alloc(&req2)
    Swag.assert(req2.address != null)
    Swag.assert(scratch.totalLeak >= 256)

    // Write to it to verify usability
    let ptr = cast([*] u8) req2.address!
    ptr[0]   = 0xAA
    ptr[255] = 0xBB
    Swag.assert(ptr[0] == 0xAA)
    Swag.assert(ptr[255] == 0xBB)

    scratch.release()
}

// Leak is freed when explicitly freed
#test
{
    var alloc:   Allocator
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
    Swag.assert(scratch.totalLeak >= 128)

    // Free the leak
    req2.size = 128
    itf.free(&req2)
    Swag.assert(scratch.totalLeak == 0)

    scratch.release()
}

// FreeAll clears used and leaks
#test
{
    var alloc:   Allocator
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

    Swag.assert(scratch.used > 0)
    Swag.assert(scratch.totalLeak > 0)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)

    Swag.assert(scratch.used == 0)
    Swag.assert(scratch.firstLeak == null)

    scratch.release()
}

// maxUsed tracks peak usage
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 512
    itf.alloc(&req)

    let peak = scratch.maxUsed
    Swag.assert(peak >= 512)

    // Free last
    req.size = 512
    itf.free(&req)

    // maxUsed should still reflect the peak
    Swag.assert(scratch.maxUsed == peak)

    scratch.release()
}

// maxLeak tracks peak leak
#test
{
    var alloc:   Allocator
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
    Swag.assert(peak >= 200)

    // Free leak
    req2.size = 200
    itf.free(&req2)

    // maxLeak still reflects peak
    Swag.assert(scratch.maxLeak == peak)

    scratch.release()
}

// Realloc within buffer copies data
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 32
    itf.alloc(&req)

    let ptr = cast([*] u8) req.address!
    for i in 32 do
        ptr[i] = cast(u8) (i + 1)

    req.oldSize = 32
    req.size    = 128
    itf.realloc(&req)
    Swag.assert(req.address != null)

    let newPtr = cast([*] u8) req.address!
    for i in 32 do
        Swag.assert(newPtr[i] == cast(u8) (i + 1))

    scratch.release()
}

// Sequential alloc-free cycles
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    for i in 20
    {
        var req: AllocatorRequest
        req.size = 64
        itf.alloc(&req)
        Swag.assert(req.address != null)

        // Free last immediately to reclaim
        req.size = 64
        itf.free(&req)
    }

    // Buffer should be back to 0 since we always free the last
    Swag.assert(scratch.used == 0)

    scratch.release()
}

// Small allocation (1 byte)
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 1
    itf.alloc(&req)
    Swag.assert(req.address != null)

    let ptr = cast([*] u8) req.address!
    ptr[0] = 0xFF
    Swag.assert(ptr[0] == 0xFF)

    scratch.release()
}

// FreeAll then reuse
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    // Fill some space
    var req: AllocatorRequest
    req.size = 1024
    itf.alloc(&req)

    // FreeAll resets
    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)
    Swag.assert(scratch.used == 0)

    // Allocate again
    var req2: AllocatorRequest
    req2.size = 512
    itf.alloc(&req2)
    Swag.assert(req2.address != null)
    Swag.assert(scratch.used >= 512)

    scratch.release()
}

// Multiple leaks tracked and freed
#test
{
    var alloc:   Allocator
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
        Swag.assert(leaks[i].address != null)
    }

    Swag.assert(scratch.totalLeak >= 300)

    // Free leaks one by one
    for i in 3
    {
        leaks[i].size = 100
        itf.free(&leaks[i])
    }

    Swag.assert(scratch.totalLeak == 0)

    scratch.release()
}

// 32-bit typed writes
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size      = 40
    req.alignment = 8
    itf.alloc(&req)

    let vals = cast([*] u32) req.address!
    for i in 10 do
        vals[i] = cast(u32) (i * 777 + 11)

    for i in 10 do
        Swag.assert(vals[i] == cast(u32) (i * 777 + 11))

    scratch.release()
}

// Alignment applies to both buffer and overflow allocations
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var prefix: AllocatorRequest
    prefix.size = 1
    itf.alloc(&prefix)

    var buffered: AllocatorRequest
    buffered.size      = 32
    buffered.alignment = 64
    itf.alloc(&buffered)
    Swag.assert(cast(u64) buffered.address % 64 == 0)

    var overflow: AllocatorRequest
    overflow.size      = BufSize
    overflow.alignment = 128
    itf.alloc(&overflow)
    Swag.assert(cast(u64) overflow.address % 128 == 0)

    overflow.size = BufSize
    itf.free(&overflow)
    Swag.assert(scratch.totalLeak == 0)

    scratch.release()
}

// Reallocating an overflow allocation copies only the retained bytes and frees the old block
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var fill: AllocatorRequest
    fill.size = BufSize
    itf.alloc(&fill)

    var req: AllocatorRequest
    req.size = 128
    itf.alloc(&req)
    let oldAddress = req.address
    let data       = cast([*] u8) req.address!
    for i in 128 do
        data[i] = cast(u8) i

    req.oldSize = 128
    req.size    = 32
    itf.realloc(&req)

    Swag.assert(req.address != null)
    Swag.assert(req.address != oldAddress)
    Swag.assert(scratch.totalLeak == 32)
    let resized = cast([*] u8) req.address!
    for i in 32 do
        Swag.assert(resized[i] == cast(u8) i)

    req.size = 32
    itf.free(&req)
    Swag.assert(scratch.totalLeak == 0)

    scratch.release()
}

// Release frees the buffer
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)

    scratch.release()
    Swag.assert(scratch.block == null)
    Swag.assert(scratch.used == 0)
    Swag.assert(scratch.capacity == 0)
    Swag.assert(scratch.allocator == null)
}

// Realloc with size 0 frees
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.size = 64
    itf.alloc(&req)

    req.oldSize = 64
    req.size    = 0
    itf.realloc(&req)
    Swag.assert(req.address == null)

    scratch.release()
}

// Realloc from null acts like alloc
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.address = null
    req.size    = 200
    itf.realloc(&req)
    Swag.assert(req.address != null)

    let ptr = cast([*] u8) req.address!
    ptr[0]   = 1
    ptr[199] = 2
    Swag.assert(ptr[0] == 1)
    Swag.assert(ptr[199] == 2)

    scratch.release()
}

// Realloc from null ignores a stale old size instead of copying from address zero.
// 'Array.opPostCopy' produces exactly this request: it clears the buffer of a copy
// and reallocates it, leaving the old size describing a block that is not there.
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    var req: AllocatorRequest
    req.address = null
    req.oldSize = 64
    req.size    = 200
    itf.realloc(&req)
    Swag.assert(req.address != null)

    let ptr = cast([*] u8) req.address!
    ptr[0]   = 1
    ptr[199] = 2
    Swag.assert(ptr[0] == 1)
    Swag.assert(ptr[199] == 2)

    scratch.release()
}

// Capacity and block are set correctly
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    Swag.assert(scratch.capacity == BufSize)
    Swag.assert(scratch.block != null)

    scratch.release()
}

// Alignment keeps the full 64 bits of an address
#test
{
    const High = 0x0000_0134_0000_0000'u64

    Swag.assert(ScratchAllocator.align(High, 16) == High)
    Swag.assert(ScratchAllocator.align(High + 1, 16) == High + 16)
    Swag.assert(ScratchAllocator.align(High + 15, 16) == High + 16)
    Swag.assert(ScratchAllocator.align(High + 16, 16) == High + 16)
    Swag.assert(ScratchAllocator.align(High + 9, 8) == High + 16)
}

// Every allocation is aligned as requested, whatever the block address is
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    for alignment in [8'u32, 16, 32, 64, 128]
    {
        var req: AllocatorRequest
        req.size      = 24
        req.alignment = alignment
        itf.alloc(&req)

        let address = cast(u64) req.address!
        Swag.assert(address % cast(u64) alignment == 0)
        Swag.assert(address >= cast(u64) scratch.block)
    }

    scratch.release()
}
