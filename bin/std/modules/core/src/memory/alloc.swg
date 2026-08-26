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

    let hintLength = @countof(request.hint)
    if hintLength
    {
        let shownHintLength = @min(hintLength, AllocationPanicHintMaxBytes)
        message.addBytes(" [")
        message.addBytes(@mkstring(@dataof(request.hint), shownHintLength))
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
    @panic(cast(string) message.toSlice()!, request.callerLoc)
}

// Asserts that a byte range belongs to the selected allocator.
// A null buffer is accepted and performs no check.
func assertIsAllocated(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    let talloc = (allocator orelse @getcontext().allocator)!
    talloc.assertAllocated(&req)
}

// Releases a byte range through the selected allocator.
// A null buffer is accepted and performs no operation.
func free(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !buffer do
        return

    var req: AllocatorRequest
    req.callerLoc = loc
    req.size      = size
    req.address   = buffer
    req.hint      = hint

    let talloc = (allocator orelse @getcontext().allocator)!
    talloc.free(&req)
}

// Releases every allocation owned by the selected allocator, when supported.
func freeAll(allocator: #null IAllocator, hint: #null string = null, loc = #callerlocation)
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint

    let talloc = (allocator orelse @getcontext().allocator)!
    talloc.freeAll(&req)
}

// Resizes a byte allocation, preserving its existing contents.
// The returned pointer is non-null; a zero new size raises a panic.
func realloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.address   = buffer
    req.size      = newSize
    req.oldSize   = oldSize
    req.alignment = alignment

    if !newSize do
        panicAllocationFailure("Memory.realloc", &req, true)

    let talloc = (allocator orelse @getcontext().allocator)!
    talloc.realloc(&req)

    if !req.address
    {
        req.address = buffer
        panicAllocationFailure("Memory.realloc", &req, true)
    }

    return req.address!
}

// Allocates an uninitialized byte range.
// The returned pointer is non-null; a zero size raises a panic.
func alloc(size: u64, allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment

    if !size do
        panicAllocationFailure("Memory.alloc", &req, false)

    let talloc = (allocator orelse @getcontext().allocator)!
    talloc.alloc(&req)

    if !req.address do
        panicAllocationFailure("Memory.alloc", &req, false)
    return req.address!
}

// Allocates an uninitialized byte range from the current temporary allocator.
func tempAlloc(size: u64, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] void
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment

    if !size do
        panicAllocationFailure("Memory.tempAlloc", &req, false)

    @getcontext().tempAllocator.IAllocator.alloc(&req)
    if !req.address do
        panicAllocationFailure("Memory.tempAlloc", &req, false)
    return req.address!
}

// Allocates and default-initializes a value described at runtime.
// Returns null after reporting a panic when the type requires explicit initialization.
func new(type: typeinfo, allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->#null *u8
{
    let userHint = hint orelse type.fullname
    if !canDefaultInit(type)
    {
        @panic("Memory.new cannot default-initialize this type", loc)
        return null
    }

    let ptr = alloc(cast(u64) type.sizeof, allocator, alignment, userHint, loc)
    defaultInit(ptr, type)
    return ptr
}

// Allocates and default-initializes one value of T.
func(T) new(allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->*T
{
    let userHint = hint orelse #stringof(T)
    let ptr      = cast(*T) alloc(#sizeof(T), allocator, alignment, userHint, loc)
    @init(ptr, 1)
    return ptr
}

// Drops and releases one value of T.
func(T) delete(ptr: #null *T, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !ptr do
        return
    let userHint = hint orelse #stringof(T)
    assertIsAllocated(ptr, #sizeof(T), allocator, userHint, loc)
    @drop(ptr)
    free(ptr, #sizeof(T), allocator, userHint, loc)
}

// Drops and releases a value described at runtime.
func delete(ptr: #null *void, type: typeinfo, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !ptr do
        return

    Debug.assert(type != null)
    let userHint = hint orelse type.name
    assertIsAllocated(ptr, cast(u64) type.sizeof, allocator, userHint, loc)

    dropType(ptr, type)

    free(ptr, cast(u64) type.sizeof, allocator, userHint, loc)
}

// Allocates and default-initializes num contiguous values of T.
func(T) new(num: u64, allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] T
{
    Debug.assert(num > 0)

    let userHint = hint orelse #stringof(T)
    let ptr      = cast([*] T) alloc(#sizeof(T) * num, allocator, alignment, userHint, loc)
    @init(ptr, num)
    return ptr
}

// Drops and releases num contiguous values of T.
func(T) delete(ptr: #null [*] T, num: u64, allocator: #null IAllocator = null, hint: #null string = null, loc = #callerlocation)
{
    if !ptr do
        return
    Debug.assert(num > 0)

    let userHint = hint orelse #stringof(T)
    assertIsAllocated(ptr, #sizeof(T) * num, allocator, userHint, loc)
    @drop(ptr, num)
    free(ptr, #sizeof(T) * num, allocator, userHint, loc)
}
