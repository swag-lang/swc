#global public
#global namespace Memory
using Swag

// Copy one block of memory to a given address
#[Inline]
func copy(dest: #null [*] void, src: #null const [*] void, size: u64)
{
    if size do
        @memcpy(dest, src, size)
}

// Move one block of memory to a given address
#[Inline]
func copyOver(dest: #null [*] void, src: #null const [*] void, size: u64)
{
    if size do
        @memmove(dest, src, size)
}

// Compare two blocks of memory
#[Inline]
func compare(dest, src: #null const [*] void, size: u64)->s32
{
    if !size do
        return 0
    return @memcmp(dest, src, size)
}

// Compare two blocks of memory
#[Inline]
func(T) equals(dest, src: const *T)->bool
{
    return @memcmp(dest, src, #sizeof(T)) == 0
}

// Clear one block of memory
#[Inline]
func clear(dest: [*] void, size: u64)
{
    if size do
        @memset(dest, 0, size)
}

// Set the content of one block of memory to a specific byte value
#[Inline]
func set(dest: [*] void, value: u8, size: u64)
{
    if size do
        @memset(dest, value, size)
}

// Align a value to the given amount
#[Inline]
func align(value: u64, alignment: u32)->u64
{
    let toAlign: u64 = cast(u64) (alignment orelse cast(u32) #sizeof(*void)) - 1
    return (value + toAlign) & ~toAlign
}

// Align a pointer to the given amount
#[Inline]
func align(value: const [*] void, alignment: u32)->const [*] void
{
    return cast() align(cast(u64) value, alignment)
}

// Clear the temporary allocator
func freeTemp()
{
    @getcontext().tempAllocator.releaseAll()
}

// Push a new allocator for the given block of code
#[Swag.Macro]
func pushAllocator(allocator: Swag.IAllocator, stmt: #code)
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = dref prev
    cxt.allocator = allocator
    @setcontext(cxt)

    #inject(stmt)
}

// Push the temporary allocator for the given block of code
#[Swag.Macro]
func pushTempAllocator(stmt: #code)
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = dref prev
    cxt.allocator = @getcontext().tempAllocator
    @setcontext(cxt)

    #inject(stmt)
}
