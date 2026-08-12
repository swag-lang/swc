internal struct TestAllocationHeader
{
    totalSize: u64
    _padding:  u64
}

internal const TestAllocationHeaderSize = #sizeof(TestAllocationHeader)

internal func testAlloc(size: u64)->#null [*] void
{
    if size > Swag.U64.Max - TestAllocationHeaderSize do
        return null

    var request: Swag.AllocatorRequest
    request.size      = size + TestAllocationHeaderSize
    request.alignment = 16
    let allocator = @getcontext().allocator!
    allocator.alloc(&request)
    if !request.address do
        return null

    let header = cast(*TestAllocationHeader) request.address
    header.totalSize = request.size
    header._padding  = 0
    return cast([*] void) (cast([*] u8) header + TestAllocationHeaderSize)
}

internal func testRealloc(ptr: #null [*] void, size: u64)->#null [*] void
{
    if !ptr do
        return testAlloc(size)
    if !size
    {
        testFree(ptr)
        return null
    }
    if size > Swag.U64.Max - TestAllocationHeaderSize do
        return null

    let header = cast(*TestAllocationHeader) (cast([*] u8) ptr! - TestAllocationHeaderSize)
    var request: Swag.AllocatorRequest
    request.address   = header
    request.oldSize   = header.totalSize
    request.size      = size + TestAllocationHeaderSize
    request.alignment = 16
    let allocator = @getcontext().allocator!
    allocator.realloc(&request)
    if !request.address do
        return null

    let replacement = cast(*TestAllocationHeader) request.address
    replacement.totalSize = request.size
    replacement._padding  = 0
    return cast([*] void) (cast([*] u8) replacement + TestAllocationHeaderSize)
}

internal func testFree(ptr: #null [*] void)
{
    if !ptr do
        return

    let header = cast(*TestAllocationHeader) (cast([*] u8) ptr! - TestAllocationHeaderSize)
    var request: Swag.AllocatorRequest
    request.address = header
    request.size    = header.totalSize
    let allocator = @getcontext().allocator!
    allocator.free(&request)
}
