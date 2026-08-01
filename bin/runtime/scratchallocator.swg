#global namespace Swag

impl ScratchAllocator
{
    struct LeakHeader
    {
        prev:           #null *LeakHeader
        next:           #null *LeakHeader
        allocation:     *void
        allocationSize: u64
        userSize:       u64
    }

    // Adapt the value depending on the requested alignment
    func align(value: u64, alignment: u32)->u64
    {
        @assert(!alignment or !(alignment & (alignment - 1)))
        let toAlign = alignment != 0 ? alignment : #sizeof(*void)
        var result  = value & ~(toAlign - 1)
        if result < value do
            result += toAlign
        return result
    }

    // Free a block, if possible.
    mtd freeMem(addr: *void, size: u64)
    {
        let allocItf = notnull .allocator
        var req: AllocatorRequest
        req.address = addr
        req.size    = size
        allocItf.free(&req)
    }

    // Allocate a block
    mtd alloc(size: u64, alignment: u32 = 0)->#null *void
    {
        let allocItf = notnull .allocator
        var req: AllocatorRequest
        req.size      = size
        req.alignment = alignment
        allocItf.alloc(&req)
        return req.address
    }

    // Release the allocated block
    mtd release()
    {
        .releaseAll()

        if .block do
            .freeMem(.block, .capacity)

        @init(me, 1)
    }

    // Release all memory
    mtd releaseAll()
    {
        .used = 0
        while .firstLeak
        {
            let p = cast(*LeakHeader) .firstLeak
            let n = p.next
            .freeMem(p.allocation, p.allocationSize)
            .firstLeak = n
        }

        .totalLeak = 0
    }

    // This will call 'release' prior to changing the capacity, so this must
    // be called at an early stage
    mtd setCapacity(newCapacity: u64, allocator: IAllocator)
    {
        .release()
        .allocator = allocator
        .capacity  = newCapacity

        var req: AllocatorRequest
        req.size = .capacity
        .allocator.alloc(&req)
        .block = req.address
    }
}

impl IAllocator for ScratchAllocator
{
    mtd impl free(request: *AllocatorRequest)
    {
        @assert(.block != null)
        if !request.address do
            return
        let reqAddr = request.address

        // If this is the last allocated block in the buffer, we can free it
        // by changing the allocated used size
        let ptr = (.block + .used) - request.size
        if ptr == request.address
        {
            request.address = null
            .used           -= request.size
            return
        }

        // If the pointer is in the buffer, then we are done. We cannot free.
        if request.address >= .block and request.address < .block + .capacity
        {
            request.address = null
            return
        }

        // Otherwise we assume it's a leak. We unlink it, and free it with
        // the allocator
        var leak = cast([*] LeakHeader) reqAddr
        leak -= 1
        if !leak.prev do
            .firstLeak = leak.next
        else do
            leak.prev.next = leak.next
        if leak.next do
            leak.next.prev = leak.prev
        .totalLeak -= leak.userSize
        .freeMem(leak.allocation, leak.allocationSize)
        request.address = null
    }

    // Shared allocation path: in the buffer when there is room, otherwise a tracked
    // leak allocation. A non-null incoming 'request.address' is a reallocation: the
    // old payload ('request.oldSize' bytes) is copied into the new block.
    mtd allocBlock(request: *AllocatorRequest)
    {
        // Allocate in the buffer if there is enough room
        let block        = notnull .block
        let blockAddress = cast(u64) block
        let userAddress  = ScratchAllocator.align(blockAddress + .used, request.alignment)
        let usedAlign    = userAddress - blockAddress
        if usedAlign <= .capacity and request.size <= .capacity - usedAlign
        {
            request.address = cast(*void) userAddress
            .used           = usedAlign + request.size
            .maxUsed        = @max(.maxUsed, .used)
            return
        }

        // Otherwise this is a leak
        // We prepend a LeakHeader to the user block, and linked it in
        // the chained list of leak allocations (at the first position)
        let alignment   = request.alignment != 0 ? request.alignment : cast(u32) #sizeof(*void)
        let totalSize   = request.size + #sizeof(LeakHeader) + alignment - 1
        let allocation  = cast([*] u8) notnull .alloc(totalSize, alignment)
        let leakAddress = ScratchAllocator.align(cast(u64) (allocation + #sizeof(LeakHeader)), alignment) - #sizeof(LeakHeader)
        let ptr         = cast([*] LeakHeader) leakAddress
        let leak        = cast(#null [*] LeakHeader) .firstLeak
        if leak do
            leak.prev = ptr
        ptr.prev           = null
        ptr.next           = .firstLeak
        ptr.allocation     = allocation
        ptr.allocationSize = totalSize
        ptr.userSize       = request.size
        .firstLeak         = ptr
        request.address    = ptr + 1     // user block is after the header
        .totalLeak         += request.size
        .maxLeak           = @max(.maxLeak, .totalLeak)
    }

    mtd impl alloc(request: *AllocatorRequest)
    {
        @assert(.block != null)
        if request.size == 0
        {
            request.address = null
            return
        }

        request.address = null
        .allocBlock(request)
    }

    mtd impl realloc(request: *AllocatorRequest)
    {
        @assert(.block != null)
        if request.size == 0
        {
            .free(request)
            request.address = null
            return
        }

        let oldAddress = request.address
        let oldSize    = request.oldSize

        request.address = null
        .allocBlock(request)

        let newAddress = request.address
        if !newAddress
        {
            request.address = oldAddress
            return
        }

        @memcpy(newAddress, oldAddress, @min(oldSize, request.size))

        var freeRequest: AllocatorRequest
        freeRequest.address = oldAddress
        freeRequest.size    = oldSize
        .free(&freeRequest)
        request.address = newAddress
    }

    mtd impl freeAll(request: *AllocatorRequest)
    {
        @assert(.block != null)
        .releaseAll()
        request.address = null
    }

    mtd impl assertAllocated(request: *AllocatorRequest)
    {
    // Not supported: the scratch allocator does not track individual blocks.
    }
}
