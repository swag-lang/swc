#global public
#global namespace Memory

using Swag

private func allocationSizeError(kind: string, size: u64, hint: #null string, location: Swag.SourceCodeLocation)->String
{
    var result: retval
    result.append(kind)
    result.append(" expects a non-zero size")
    result.append(", got ")
    result.appendFormat("%", size)
    if @countof(hint)
    {
        result.append(" [")
        result.append(hint)
        result.append("]")
    }

    result.append(" at ")
    result.append(location.fileName)
    result.append(":")
    result.appendFormat("%", location.lineStart + 1)
    return result
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

    let talloc = notnull (allocator orelse @getcontext().allocator)
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

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.free(&req)
}

// Releases every allocation owned by the selected allocator, when supported.
func freeAll(allocator: #null IAllocator, hint: #null string = null, loc = #callerlocation)
{
    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.freeAll(&req)
}

// Resizes a byte allocation, preserving its existing contents.
// The returned pointer is non-null; a zero new size raises a panic.
func realloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] void
{
    if !newSize do
        @panic(allocationSizeError("Memory.realloc", newSize, hint, loc), loc)

    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.address   = buffer
    req.size      = newSize
    req.oldSize   = oldSize
    req.alignment = alignment

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.realloc(&req)

    let address = req.address
    if !address do
        @panic("Memory.realloc returned null", loc)
    return address
}

// Allocates an uninitialized byte range.
// The returned pointer is non-null; a zero size raises a panic.
func alloc(size: u64, allocator: #null IAllocator = null, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] void
{
    if !size do
        @panic(allocationSizeError("Memory.alloc", size, hint, loc), loc)

    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment

    let talloc = notnull (allocator orelse @getcontext().allocator)
    talloc.alloc(&req)

    let address = req.address
    if !address do
        @panic("Memory.alloc returned null", loc)
    return address
}

// Allocates an uninitialized byte range from the current temporary allocator.
func tempAlloc(size: u64, alignment: u32 = 0, hint: #null string = null, loc = #callerlocation)->[*] void
{
    if !size do
        @panic(allocationSizeError("Memory.tempAlloc", size, hint, loc), loc)

    var req: AllocatorRequest
    req.callerLoc = loc
    req.hint      = hint
    req.size      = size
    req.alignment = alignment
    @getcontext().tempAllocator.IAllocator.alloc(&req)
    let address = req.address
    if !address do
        @panic("Memory.tempAlloc returned null", loc)
    return address
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
