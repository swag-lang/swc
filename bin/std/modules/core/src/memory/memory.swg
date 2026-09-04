#global public
#global namespace Memory

using Swag

// Copies bytes between non-overlapping memory regions.
// A null pointer is accepted only when size is zero.
#[Inline]
func copy(destination: [*] void?, source: const [*] void?, size: u64)
{
    if size do
        Swag.memcpy(destination, source, size)
}

// Copies bytes between memory regions that may overlap.
// A null pointer is accepted only when size is zero.
#[Inline]
func copyOverlapping(destination: [*] void?, source: const [*] void?, size: u64)
{
    if size do
        Swag.memmove(destination, source, size)
}

// Compares two byte sequences lexicographically.
#[Inline]
func compare(left, right: const [*] void?, size: u64)->s32
{
    if !size do
        return 0
    return Swag.memcmp(left, right, size)
}

// Returns whether two values have identical object representations.
#[Inline]
func(T) bytesEqual(left, right: const *T)->bool
{
    return Swag.memcmp(left, right, #sizeof(T)) == 0
}

// Fills raw storage with zero bytes.
// Use `Swag.init` instead when resetting a declared value to its language defaults.
#[Inline]
func clear(dest: [*] void, size: u64)
{
    if size do
        Swag.memset(dest, 0, size)
}

// Fills raw storage with a repeated byte value.
#[Inline]
func set(dest: [*] void, value: u8, size: u64)
{
    if size do
        Swag.memset(dest, value, size)
}

// Rounds a value up to the requested power-of-two alignment.
// An alignment of zero uses the native pointer alignment.
#[Inline]
func align(value: u64, alignment: u32)->u64
{
    Debug.assert(!alignment or !(alignment & (alignment - 1)), "alignment must be a power of two")
    let toAlign: u64 = cast(u64) (alignment != 0 ? alignment : cast(u32) #sizeof(*void)) - 1
    return (value + toAlign) & ~toAlign
}

// Rounds a pointer up to the requested power-of-two alignment.
#[Inline]
func align(value: const [*] void, alignment: u32)->const [*] void
{
    return cast() align(cast(u64) value, alignment)
}

// Releases every allocation owned by the current temporary allocator.
func releaseTemporaryAllocations()
{
    Swag.getContext().tempAllocator.releaseAll()
}

// Runs a code block with allocator installed as the current allocator.
#[Swag.Macro]
func withAllocator(allocator: Swag.IAllocator?, stmt: #code)
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.allocator = allocator
    Swag.setContext(cxt)

    #inject(stmt)
}

// Runs a code block with the temporary allocator installed as the current allocator.
#[Swag.Macro]
func withTemporaryAllocator(stmt: #code)
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.allocator = Swag.getContext().tempAllocator
    Swag.setContext(cxt)

    #inject(stmt)
}
