#global public
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
func alloc(size: u64, allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment

    if not size do
        panicAllocationFailure("Memory.alloc", &req, false)

    (allocator orelse Swag.getContext().allocator)!.alloc(&req)

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

// Allocates a value of the runtime type `type` and default-initializes it.
//
// Raises a panic, and returns null if the panic handler returns, when the type cannot be
// default-initialized.
func new(type: typeinfo, allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->*u8?
{
    let userHint = hint orelse type.fullname
    if not canDefaultInit(type)
    {
        Swag.panic("Memory.new cannot default-initialize this type", loc)
        return null
    }

    let ptr = alloc(cast(u64) type.sizeof, allocator, alignment, userHint, loc)
    defaultInit(ptr, type)
    return ptr
}

// Allocates one value of `T` and default-initializes it.
func(T) new(allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->*T
{
    let userHint = hint orelse #stringof(T)
    let ptr      = cast(*T) alloc(#sizeof(T), allocator, alignment, userHint, loc)
    Swag.init(ptr, 1)
    return ptr
}

// Drops the value at `ptr` and releases its storage.
//
// The storage must come from `allocator`, or from the context allocator when it is null. A null
// `ptr` does nothing.
func(T) delete(ptr: *T?, allocator: IAllocator? = null, hint: string? = null, loc = #callerlocation)
{
    if not ptr do
        return
    let userHint = hint orelse #stringof(T)
    assertIsAllocated(ptr, #sizeof(T), allocator, userHint, loc)
    Swag.drop(ptr)
    free(ptr, #sizeof(T), allocator, userHint, loc)
}

// Drops the value of the runtime type `type` at `ptr` and releases its storage.
//
// A null `ptr` does nothing.
func delete(ptr: *void?, type: typeinfo, allocator: IAllocator? = null, hint: string? = null, loc = #callerlocation)
{
    if not ptr do
        return

    Swag.assert(type != null)
    let userHint = hint orelse type.name
    assertIsAllocated(ptr, cast(u64) type.sizeof, allocator, userHint, loc)

    dropType(ptr, type)

    free(ptr, cast(u64) type.sizeof, allocator, userHint, loc)
}

// Allocates `num` contiguous values of `T` and default-initializes them.
//
// `num` must not be zero.
func(T) new(num: u64, allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->[*] T
{
    Swag.assert(num > 0)

    let userHint = hint orelse #stringof(T)
    let ptr      = cast([*] T) alloc(#sizeof(T) * num, allocator, alignment, userHint, loc)
    Swag.init(ptr, num)
    return ptr
}

// Drops the `num` contiguous values at `ptr` and releases their storage.
//
// A null `ptr` does nothing.
func(T) delete(ptr: [*] T?, num: u64, allocator: IAllocator? = null, hint: string? = null, loc = #callerlocation)
{
    if not ptr do
        return
    Swag.assert(num > 0)

    let userHint = hint orelse #stringof(T)
    assertIsAllocated(ptr, #sizeof(T) * num, allocator, userHint, loc)
    Swag.drop(ptr, num)
    free(ptr, #sizeof(T) * num, allocator, userHint, loc)
}
