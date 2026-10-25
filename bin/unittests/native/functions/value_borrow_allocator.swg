#global private
// The caller needs value-borrow guards and the allocator needs its early safety capability.
// An attribute on a test cannot add allocator instrumentation after bootstrap.
#global if #hastag("Swag.AllocatorSafety") and #safety(Swag.SafetyWhat.ValueBorrow)

struct Thing { value, padding1, padding2: u64 }

func mustReject(action: func||())
{
    let caught = Swag.catchPanic(action)
    Swag.assert(caught.raised)
    Swag.assert(caught.message() == "write overlaps storage borrowed by a value argument")
}

#[Swag.NoInline]
func invalidateAllocation(value: Thing, address: *void, operation: u32)->u64
{
    let allocator = unwrap Swag.getContext().allocator
    var request: Swag.AllocatorRequest
    request.address = address
    switch operation
    {
    case 0: allocator.free(&request)     // No caller size: the allocator must recover the extent.
    case 1:
        request.size = 262144
        allocator.realloc(&request)
    }
    return value.value
}

// Borrowing an interior element must prevent freeing or moving the whole allocation.
#test
{
    let allocator = unwrap Swag.getContext().allocator
    for size in [3 * #sizeof(Thing), 131072'u64]
    {
        var request: Swag.AllocatorRequest
        request.size = size
        allocator.alloc(&request)
        let address = unwrap request.address
        defer
        {
            request.address = address
            allocator.free(&request)
        }
        let elements = cast([*] Thing, address)
        Swag.init(elements, 3)
        elements[1].value = 113
        for operation in 2'u32
        {
            mustReject(func|elements, address, operation|() {
                discard invalidateAllocation(elements[1], address, operation)
            })
            Swag.assert(elements[1].value == 113)
        }
    }
}
