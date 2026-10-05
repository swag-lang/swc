#global export
#global namespace Memory

using Swag

private const AllocationPanicHintMaxBytes = 512'u64

private struct AllocationPanicBufferAllocator {}

private impl IAllocator for AllocationPanicBufferAllocator
{
    mtd impl alloc(request: *AllocatorRequest) { request.address = null }
    mtd impl realloc(request: *AllocatorRequest) { request.address = null }
    mtd impl free(request: *AllocatorRequest) {}
    mtd impl freeAll(request: *AllocatorRequest) {}
    mtd impl assertAllocated(request: *AllocatorRequest) {}
}

internal func appendAllocationFailure(message: *ConcatBuffer, operation: string, request: AllocatorRequest, includeOldAllocation: bool)
{
    message.addBytes(operation)
    message.addBytes(includeOldAllocation ? " cannot reallocate memory: requested size " : " cannot allocate memory: requested size ")
    Format.append(message, "%", request.size)
    message.addBytes(" bytes")

    if includeOldAllocation
    {
        message.addBytes(", old size ")
        Format.append(message, "%", request.oldSize)
        message.addBytes(" bytes")
    }

    message.addBytes(", alignment ")
    Format.append(message, "%", request.alignment)
    message.addBytes(" bytes")

    if includeOldAllocation
    {
        message.addBytes(", address 0x")
        Format.append(message, "%{X}", cast(u64) request.address)
    }

    let hintLength = request.hint.count
    if hintLength
    {
        let shownHintLength = Swag.min(hintLength, AllocationPanicHintMaxBytes)
        message.addBytes(" [")
        message.addBytes(Swag.makeString(request.hint.buffer, shownHintLength))
        if shownHintLength != hintLength do
            message.addBytes("...")
        message.addBytes("]")
    }
}

private func panicAllocationFailure(operation: string, request: *AllocatorRequest, includeOldAllocation: bool)
{
    // Allocation failures must not allocate again while constructing their panic message.
    var storage:           [1024] u8
    var stackAllocator:    AllocationPanicBufferAllocator
    var message:           ConcatBuffer
    let stackAllocatorItf: IAllocator = &stackAllocator
    message.allocator = stackAllocatorItf
    message.setFirstBucket(storage)
    appendAllocationFailure(&message, operation, request[], includeOldAllocation)
    Swag.panic(cast(string) message.toSlice()!, request.callerLoc)
}

// Asserts that the `size` bytes at `buffer` were allocated by `allocator`.
//
// A null `allocator` selects the context allocator. A null `buffer` performs no check.
func assertIsAllocated(buffer: [*] void?, size: u64, allocator: IAllocator? = null, hint: string? = null, loc = #callerlocation)
{
    if not buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    (allocator orelse Swag.getContext().allocator)!.assertAllocated(&req)
}

// Releases the `size` bytes at `buffer` through `allocator`.
//
// A null `allocator` selects the context allocator. A null `buffer` does nothing.
#[Swag.Inline]
func free(buffer: [*] void?, size: u64, allocator: IAllocator? = null, hint: string? = null, loc = #callerlocation)
{
    if not buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    (allocator orelse Swag.getContext().allocator)!.free(&req)
}

// Releases every allocation owned by `allocator`, when the allocator supports it.
//
// A null `allocator` selects the context allocator.
func freeAll(allocator: IAllocator?, hint: string? = null, loc = #callerlocation)
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint

    (allocator orelse Swag.getContext().allocator)!.freeAll(&req)
}

// Resizes the allocation at `buffer` from `oldSize` to `newSize` bytes and returns its possibly moved address.
//
// The contents are preserved up to the smaller size. A null `allocator` selects the context
// allocator, and a zero `alignment` the default one. A zero `newSize` or an allocation failure
// raises a panic, so the result is never null.
func realloc(buffer: [*] void?, newSize: u64, oldSize: u64, allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.address   = buffer
    req.size      = newSize
    req.oldSize   = oldSize
    req.alignment = alignment

    if not newSize do
        panicAllocationFailure("Memory.realloc", &req, true)

    (allocator orelse Swag.getContext().allocator)!.realloc(&req)

    if not req.address
    {
        req.address = buffer
        panicAllocationFailure("Memory.realloc", &req, true)
    }

    return req.address!
}

// Allocates `size` uninitialized bytes and returns their address.
//
// A null `allocator` selects the context allocator, and a zero `alignment` the default one. A zero
// `size` or an allocation failure raises a panic, so the result is never null.
#[Swag.Inline]
func alloc(size: u64, allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->[*] void
{
    var selected = allocator
    if size != 0
    {
        // Identity is enough to enter the runtime fast path. Other descriptors, including
        // equivalent copies from a shared library, keep the interface's normal dispatch.
        selected = (selected orelse Swag.getContext().allocator)!
        let expected: typeinfo = Swag.Allocator
        if cast(const *void) Swag.kindOf(selected) == cast(const *void) expected
        {
            let runtime = cast(*Swag.Allocator?) selected.buffer
            if runtime
            {
                let address = runtime.allocateFast(size, alignment)
                if address != 0 do
                    return cast([*] void) address
            }
        }
    }

    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment

    if not size do
        panicAllocationFailure("Memory.alloc", &req, false)

    (selected orelse Swag.getContext().allocator)!.alloc(&req)

    if not req.address do
        panicAllocationFailure("Memory.alloc", &req, false)
    return req.address!
}

// Allocates `size` uninitialized bytes from the context's temporary allocator and returns their address.
//
// A zero `size` or an allocation failure raises a panic, so the result is never null. The bytes
// stay allocated until [[Core.Memory.releaseTemporaryAllocations]].
func tempAlloc(size: u64, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment

    if not size do
        panicAllocationFailure("Memory.tempAlloc", &req, false)

    Swag.getContext().tempAllocator.IAllocator.alloc(&req)
    if not req.address do
        panicAllocationFailure("Memory.tempAlloc", &req, false)
    return req.address!
}
