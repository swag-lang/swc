#global public
#global namespace Memory

using Swag

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

    let ptr = alloc(cast(u64, type.sizeof), allocator, alignment, userHint, loc)
    defaultInit(ptr, type)
    return ptr
}

// Allocates one value of `T` and default-initializes it.
func(T) new(allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->*T
{
    let userHint = hint orelse #stringof(T)
    let ptr      = cast(*T, alloc(#sizeof(T), allocator, alignment, userHint, loc))
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
    assertIsAllocated(ptr, cast(u64, type.sizeof), allocator, userHint, loc)

    dropType(ptr, type)

    free(ptr, cast(u64, type.sizeof), allocator, userHint, loc)
}

// Allocates `num` contiguous values of `T` and default-initializes them.
//
// `num` must not be zero.
func(T) new(num: u64, allocator: IAllocator? = null, alignment: u32 = 0, hint: string? = null, loc = #callerlocation)->[*] T
{
    Swag.assert(num > 0)

    let userHint = hint orelse #stringof(T)
    let ptr      = cast([*] T, alloc(#sizeof(T) * num, allocator, alignment, userHint, loc))
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
