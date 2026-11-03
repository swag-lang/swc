#global private     //

using Swag

const BufSize = 4096'u64

struct ScratchAlignmentProbeAllocator
{
    calls: u32
    #[Swag.Align(16)]
    storage: [128] u8
}

impl IAllocator for ScratchAlignmentProbeAllocator
{
    mtd impl alloc(request: *AllocatorRequest)
    {
        .calls += 1
        if .calls == 1
        {
            request.address = &.storage[0]
            return
        }

        if request.alignment != 0 and request.alignment < #alignof(ScratchAllocator.LeakHeader) do
            request.address = &.storage[32 + request.alignment]
        else do
            request.address = &.storage[32]
    }

    mtd impl realloc(request: *AllocatorRequest) { request.address = null }
    mtd impl free(_: *AllocatorRequest) {}
}

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
    Swag.require(req.address != null)
    Swag.require(scratch.used >= 64)

    req.size = 64
    itf.free(&req)
    Swag.require(req.address == null)

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
    Swag.require(scratch.used >= 100)

    let usedAfterFirst = scratch.used

    var req2: AllocatorRequest
    req2.size = 200
    itf.alloc(&req2)
    Swag.require(scratch.used >= usedAfterFirst + 200)

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
    Swag.require(scratch.used > usedBefore)

    // Free last block reclaims
    req2.size = 64
    itf.free(&req2)
    Swag.require(scratch.used == usedBefore)

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
    Swag.require(scratch.used == usedBefore)

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
    Swag.require(req.address == null)

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
    Swag.require(req.address == null)

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

    let ptr = cast([*] u8, unwrap req.address)
    for i in 256 do
        ptr[i] = cast(u8, ((i * 3 + 5) & 0xFF))

    for i in 256 do
        Swag.require(ptr[i] == cast(u8, ((i * 3 + 5) & 0xFF)))

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
        Swag.require(req.address != null)
        ptrs[i] = req.address
    }

    // Pointers should be distinct and in increasing order (linear allocator)
    for i in 1 until 4 do
        Swag.require(cast(u64, ptrs[i]) > cast(u64, ptrs[i - 1]))

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
    Swag.require(req1.address != null)

    // This should overflow to the underlying allocator (leak)
    var req2: AllocatorRequest
    req2.size = 256
    itf.alloc(&req2)
    Swag.require(req2.address != null)
    Swag.require(scratch.totalLeak >= 256)

    // Write to it to verify usability
    let ptr = cast([*] u8, req2.address)
    ptr[0]   = 0xAA
    ptr[255] = 0xBB
    Swag.require(ptr[0] == 0xAA)
    Swag.require(ptr[255] == 0xBB)

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
    Swag.require(scratch.totalLeak >= 128)

    // Free the leak
    req2.size = 128
    itf.free(&req2)
    Swag.require(scratch.totalLeak == 0)

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

    Swag.require(scratch.used > 0)
    Swag.require(scratch.totalLeak > 0)

    var freeAll: AllocatorRequest
    itf.freeAll(&freeAll)

    Swag.require(scratch.used == 0)
    Swag.require(scratch.firstLeak == null)

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
    Swag.require(peak >= 512)

    // Free last
    req.size = 512
    itf.free(&req)

    // maxUsed should still reflect the peak
    Swag.require(scratch.maxUsed == peak)

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
    Swag.require(peak >= 200)

    // Free leak
    req2.size = 200
    itf.free(&req2)

    // maxLeak still reflects peak
    Swag.require(scratch.maxLeak == peak)

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

    let ptr = cast([*] u8, unwrap req.address)
    for i in 32 do
        ptr[i] = cast(u8, (i + 1))

    req.oldSize = 32
    req.size    = 128
    itf.realloc(&req)
    Swag.require(req.address != null)

    let newPtr = cast([*] u8, req.address)
    for i in 32 do
        Swag.require(newPtr[i] == cast(u8, (i + 1)))

    scratch.release()
}

// Sequential alloc-free cycles
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    for 20
    {
        var req: AllocatorRequest
        req.size = 64
        itf.alloc(&req)
        Swag.require(req.address != null)

        // Free last immediately to reclaim
        req.size = 64
        itf.free(&req)
    }

    // Buffer should be back to 0 since we always free the last
    Swag.require(scratch.used == 0)

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
    Swag.require(req.address != null)

    let ptr = cast([*] u8, req.address)
    ptr[0] = 0xFF
    Swag.require(ptr[0] == 0xFF)

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
    Swag.require(scratch.used == 0)

    // Allocate again
    var req2: AllocatorRequest
    req2.size = 512
    itf.alloc(&req2)
    Swag.require(req2.address != null)
    Swag.require(scratch.used >= 512)

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
        Swag.require(leaks[i].address != null)
    }

    Swag.require(scratch.totalLeak >= 300)

    // Free leaks one by one
    for i in 3
    {
        leaks[i].size = 100
        itf.free(&leaks[i])
    }

    Swag.require(scratch.totalLeak == 0)

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

    let vals = cast([*] u32, unwrap req.address)
    for i in 10 do
        vals[i] = cast(u32, (i * 777 + 11))

    for i in 10 do
        Swag.require(vals[i] == cast(u32, (i * 777 + 11)))

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
    Swag.require(cast(u64, buffered.address) % 64 == 0)

    var overflow: AllocatorRequest
    overflow.size      = BufSize
    overflow.alignment = 128
    itf.alloc(&overflow)
    Swag.require(cast(u64, overflow.address) % 128 == 0)

    overflow.size = BufSize
    itf.free(&overflow)
    Swag.require(scratch.totalLeak == 0)

    scratch.release()
}

// Small payload alignments must not leave the overflow bookkeeping header misaligned.
#test
{
    var backing: ScratchAlignmentProbeAllocator
    var scratch: ScratchAllocator
    scratch.setCapacity(1, Swag.makeInterface(&backing, #typeof(backing), IAllocator))
    let itf: IAllocator = &scratch

    var fill: AllocatorRequest
    fill.size = 1
    itf.alloc(&fill)

    for alignment in [0'u32, 1, 2, 4]
    {
        var overflow: AllocatorRequest
        overflow.size      = 24
        overflow.alignment = alignment
        itf.alloc(&overflow)

        let effectiveAlignment = alignment != 0 ? alignment : cast(u32, #sizeof(*void))
        Swag.require(overflow.address != null)
        Swag.require(cast(u64, overflow.address) % cast(u64, effectiveAlignment) == 0)
        Swag.require(cast(u64, scratch.firstLeak) % cast(u64, #alignof(ScratchAllocator.LeakHeader)) == 0)
        Swag.require(cast(u64, scratch.firstLeak) + #sizeof(ScratchAllocator.LeakHeader) == cast(u64, overflow.address))
        overflow.size = 24
        itf.free(&overflow)
        Swag.require(scratch.totalLeak == 0)
    }

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
    let data       = cast([*] u8, unwrap req.address)
    for i in 128 do
        data[i] = cast(u8, i)

    req.oldSize = 128
    req.size    = 32
    itf.realloc(&req)

    Swag.require(req.address != null)
    Swag.require(req.address != oldAddress)
    Swag.require(scratch.totalLeak == 32)
    let resized = cast([*] u8, req.address)
    for i in 32 do
        Swag.require(resized[i] == cast(u8, i))

    req.size = 32
    itf.free(&req)
    Swag.require(scratch.totalLeak == 0)

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
    Swag.require(scratch.block == null)
    Swag.require(scratch.used == 0)
    Swag.require(scratch.capacity == 0)
    Swag.require(scratch.allocator == null)
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
    Swag.require(req.address == null)

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
    Swag.require(req.address != null)

    let ptr = cast([*] u8, req.address)
    ptr[0]   = 1
    ptr[199] = 2
    Swag.require(ptr[0] == 1)
    Swag.require(ptr[199] == 2)

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
    Swag.require(req.address != null)

    let ptr = cast([*] u8, req.address)
    ptr[0]   = 1
    ptr[199] = 2
    Swag.require(ptr[0] == 1)
    Swag.require(ptr[199] == 2)

    scratch.release()
}

// Capacity does not commit a buffer until the first nonempty allocation
#test
{
    var alloc:   Allocator
    var scratch: ScratchAllocator
    let itf = makeScratchAllocator(&scratch, &alloc)

    Swag.require(scratch.capacity == BufSize)
    Swag.require(scratch.block == null)
    Swag.require(alloc.stats().countAlloc == 0)

    var empty: AllocatorRequest
    itf.alloc(&empty)
    Swag.require(scratch.block == null)
    Swag.require(alloc.stats().countAlloc == 0)

    var first: AllocatorRequest
    first.size = 1
    itf.alloc(&first)
    Swag.require(first.address != null)
    Swag.require(scratch.block != null)
    Swag.require(alloc.stats().countAlloc == 1)

    scratch.release()
}

// Alignment keeps the full 64 bits of an address
#test
{
    const High = 0x0000_0134_0000_0000'u64

    Swag.require(ScratchAllocator.align(High, 16) == High)
    Swag.require(ScratchAllocator.align(High + 1, 16) == High + 16)
    Swag.require(ScratchAllocator.align(High + 15, 16) == High + 16)
    Swag.require(ScratchAllocator.align(High + 16, 16) == High + 16)
    Swag.require(ScratchAllocator.align(High + 9, 8) == High + 16)
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

        let address = cast(u64, unwrap req.address)
        Swag.require(address % cast(u64, alignment) == 0)
        Swag.require(address >= cast(u64, scratch.block))
    }

    scratch.release()
}
