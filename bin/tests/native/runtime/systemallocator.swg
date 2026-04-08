#global fileprivate //

using Swag

// Basic allocation and free
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0xAB
    ptr[127] = 0xCD
    @assert(ptr[0] == 0xAB)
    @assert(ptr[127] == 0xCD)

    req.mode = .Free
    itf.req(&req)
    @assert(req.address == null)
}

// Free null address is a no-op
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Free
    req.address = null
    itf.req(&req)
    @assert(req.address == null)
}

// Alloc with size 0 returns null
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)
}

// Realloc with size 0 frees the memory
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)

    req.mode = .Realloc
    req.oldSize = 64
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)
}

// Realloc from null acts like alloc
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Realloc
    req.address = null
    req.size = 256
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 1
    ptr[255] = 2
    @assert(ptr[0] == 1)
    @assert(ptr[255] == 2)

    req.mode = .Free
    itf.req(&req)
}

// Realloc grow preserves data
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 32
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 32 do
        ptr[i] = cast(u8) i

    req.mode = .Realloc
    req.oldSize = 32
    req.size = 256
    itf.req(&req)
    @assert(req.address != null)

    let newPtr = cast([*] u8) req.address
    for i in 32 do
        @assert(newPtr[i] == cast(u8) i)

    req.mode = .Free
    itf.req(&req)
}

// Realloc shrink preserves leading data
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 256
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 256 do
        ptr[i] = cast(u8) (i & 0xFF)

    req.mode = .Realloc
    req.oldSize = 256
    req.size = 32
    itf.req(&req)
    @assert(req.address != null)

    let newPtr = cast([*] u8) req.address
    for i in 32 do
        @assert(newPtr[i] == cast(u8) (i & 0xFF))

    req.mode = .Free
    itf.req(&req)
}

// Default alignment (pointer size)
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    itf.req(&req)
    @assert(req.address != null)

    let addr = cast(u64) req.address
    @assert(addr % #sizeof(*void) == 0)

    req.mode = .Free
    itf.req(&req)
}

// Explicit alignment 16
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 100
    req.alignment = 16
    itf.req(&req)
    @assert(req.address != null)

    let addr = cast(u64) req.address
    @assert(addr % 16 == 0)

    req.mode = .Free
    itf.req(&req)
}

// Explicit alignment 32
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 200
    req.alignment = 32
    itf.req(&req)
    @assert(req.address != null)

    let addr = cast(u64) req.address
    @assert(addr % 32 == 0)

    req.mode = .Free
    itf.req(&req)
}

// Explicit alignment 64
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 300
    req.alignment = 64
    itf.req(&req)
    @assert(req.address != null)

    let addr = cast(u64) req.address
    @assert(addr % 64 == 0)

    req.mode = .Free
    itf.req(&req)
}

// Explicit alignment 128
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 500
    req.alignment = 128
    itf.req(&req)
    @assert(req.address != null)

    let addr = cast(u64) req.address
    @assert(addr % 128 == 0)

    req.mode = .Free
    itf.req(&req)
}

// Explicit alignment 256
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1024
    req.alignment = 256
    itf.req(&req)
    @assert(req.address != null)

    let addr = cast(u64) req.address
    @assert(addr % 256 == 0)

    req.mode = .Free
    itf.req(&req)
}

// Multiple alignment values in a loop
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var alignments: [6] u32 = [8, 16, 32, 64, 128, 256]
    for a in 6
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = 512
        req.alignment = alignments[a]
        itf.req(&req)
        @assert(req.address != null)

        let addr = cast(u64) req.address
        @assert(addr % cast(u64) alignments[a] == 0)

        req.mode = .Free
        itf.req(&req)
    }
}

// Multiple concurrent allocations
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var ptrs: [8] *void
    for i in 8
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = (i + 1) * 64
        itf.req(&req)
        @assert(req.address != null)
        ptrs[i] = req.address
    }

    // Verify all pointers are distinct
    for i in 8
    {
        for j in 8
        {
            if i != j do
                @assert(ptrs[i] != ptrs[j])
        }
    }

    // Free all
    for i in 8
    {
        var req: AllocatorRequest
        req.mode = .Free
        req.address = ptrs[i]
        req.size = (i + 1) * 64
        itf.req(&req)
        @assert(req.address == null)
    }
}

// Write and read pattern to verify memory is usable
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1024
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 1024 do
        ptr[i] = cast(u8) ((i * 7 + 13) & 0xFF)

    for i in 1024 do
        @assert(ptr[i] == cast(u8) ((i * 7 + 13) & 0xFF))

    req.mode = .Free
    itf.req(&req)
}

// Realloc with alignment preserves alignment constraint
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 64
    req.alignment = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 64 == 0)

    req.mode = .Realloc
    req.oldSize = 64
    req.size = 256
    req.alignment = 64
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 64 == 0)

    // Write to verify usability at new size
    let newPtr = cast([*] u8) req.address
    newPtr[0] = 0xAA
    newPtr[255] = 0xBB
    @assert(newPtr[0] == 0xAA)
    @assert(newPtr[255] == 0xBB)

    req.mode = .Free
    itf.req(&req)
}

// Small allocation (1 byte)
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0xFF
    @assert(ptr[0] == 0xFF)

    req.mode = .Free
    itf.req(&req)
}

// Large allocation
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1024 * 1024
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0x01
    ptr[1024 * 1024 - 1] = 0x02
    @assert(ptr[0] == 0x01)
    @assert(ptr[1024 * 1024 - 1] == 0x02)

    req.mode = .Free
    itf.req(&req)
}

// Large allocation with alignment
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1024 * 1024
    req.alignment = 256
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 256 == 0)

    req.mode = .Free
    itf.req(&req)
}

// Sequential alloc-free cycles
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    for i in 50
    {
        var req: AllocatorRequest
        req.mode = .Alloc
        req.size = (i + 1) * 16
        itf.req(&req)
        @assert(req.address != null)

        let ptr = cast([*] u8) req.address
        ptr[0] = cast(u8) i

        req.mode = .Free
        itf.req(&req)
        @assert(req.address == null)
    }
}

// Realloc chain: grow several times
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 16
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    for i in 16 do
        ptr[i] = cast(u8) i

    var prevSize = 16'u64
    var sizes: [4] u64 = [64, 256, 1024, 4096]
    for s in 4
    {
        req.mode = .Realloc
        req.oldSize = prevSize
        req.size = sizes[s]
        itf.req(&req)
        @assert(req.address != null)

        // Verify original 16 bytes survived
        let p = cast([*] u8) req.address
        for i in 16 do
            @assert(p[i] == cast(u8) i)

        prevSize = sizes[s]
    }

    req.mode = .Free
    itf.req(&req)
}

// Alloc via .Alloc always nulls address before allocating
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)
    @assert(req.address != null)

    req.mode = .Free
    itf.req(&req)

    // Alloc zeroes address before delegating to realloc path
    req.mode = .Alloc
    req.size = 128
    itf.req(&req)
    @assert(req.address != null)

    req.mode = .Free
    itf.req(&req)
}

// 32-bit typed writes via allocator
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 40
    req.alignment = 8
    itf.req(&req)
    @assert(req.address != null)

    let vals = cast([*] u32) req.address
    for i in 10 do
        vals[i] = cast(u32) (i * 1000 + 42)

    for i in 10 do
        @assert(vals[i] == cast(u32) (i * 1000 + 42))

    req.mode = .Free
    itf.req(&req)
}

// 64-bit typed writes via allocator
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 80
    req.alignment = 8
    itf.req(&req)
    @assert(req.address != null)

    let vals = cast([*] u64) req.address
    for i in 10 do
        vals[i] = cast(u64) i * 0x0102030405060708'u64

    for i in 10 do
        @assert(vals[i] == cast(u64) i * 0x0102030405060708'u64)

    req.mode = .Free
    itf.req(&req)
}

// Realloc null with size 0 returns null
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Realloc
    req.address = null
    req.size = 0
    itf.req(&req)
    @assert(req.address == null)
}

// Multiple allocations with different alignments, all active at once
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var reqs: [5] AllocatorRequest
    var aligns: [5] u32 = [8, 16, 32, 64, 128]

    for i in 5
    {
        reqs[i].mode = .Alloc
        reqs[i].size = 256
        reqs[i].alignment = aligns[i]
        itf.req(&reqs[i])
        @assert(reqs[i].address != null)
        @assert(cast(u64) reqs[i].address % cast(u64) aligns[i] == 0)
    }

    // Write unique patterns to each
    for i in 5
    {
        let ptr = cast([*] u8) reqs[i].address
        for j in 256 do
            ptr[j] = cast(u8) ((i + j) & 0xFF)
    }

    // Verify patterns are intact
    for i in 5
    {
        let ptr = cast([*] u8) reqs[i].address
        for j in 256 do
            @assert(ptr[j] == cast(u8) ((i + j) & 0xFF))
    }

    // Free all
    for i in 5
    {
        reqs[i].mode = .Free
        itf.req(&reqs[i])
    }
}

// Realloc shrink with alignment
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 4096
    req.alignment = 128
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    req.mode = .Realloc
    req.oldSize = 4096
    req.size = 64
    req.alignment = 128
    itf.req(&req)
    @assert(req.address != null)
    @assert(cast(u64) req.address % 128 == 0)

    // Write to verify usability at new size
    let newPtr = cast([*] u8) req.address
    newPtr[0] = 0xDE
    newPtr[63] = 0xAD
    @assert(newPtr[0] == 0xDE)
    @assert(newPtr[63] == 0xAD)

    req.mode = .Free
    itf.req(&req)
}

// Alloc size 2 (tiny, odd)
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 2
    itf.req(&req)
    @assert(req.address != null)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0xAA
    ptr[1] = 0xBB
    @assert(ptr[0] == 0xAA)
    @assert(ptr[1] == 0xBB)

    req.mode = .Free
    itf.req(&req)
}

// Realloc from 1 byte to large
#test
{
    var alloc: SystemAllocator
    var itf = @mkinterface(&alloc, #typeof(alloc), IAllocator)

    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 1
    itf.req(&req)

    let ptr = cast([*] u8) req.address
    ptr[0] = 0x42

    req.mode = .Realloc
    req.oldSize = 1
    req.size = 8192
    itf.req(&req)
    @assert(req.address != null)

    let newPtr = cast([*] u8) req.address
    @assert(newPtr[0] == 0x42)

    req.mode = .Free
    itf.req(&req)
}
