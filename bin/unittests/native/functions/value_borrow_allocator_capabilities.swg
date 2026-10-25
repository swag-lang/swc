#global private
#global #[Swag.Safety(.ValueBorrow, true)]

struct AllocatorBorrowValue {value, padding1, padding2: u64}

#[Swag.NoInline, Swag.Sanity(.Lifecycle, false)]
func releaseBorrowedAllocation(value: AllocatorBorrowValue, request: *Swag.AllocatorRequest)->u64
{
    let observed = value.value
    Swag.getContext().allocator!.free(request)
    return observed
}

// The host allocator used by JIT and the native allocator obey the same early capability.
#test
{
    let allocator = unwrap Swag.getContext().allocator
    var request   = Swag.AllocatorRequest{size: #sizeof(AllocatorBorrowValue)}
    allocator.alloc(&request)
    Swag.assert(request.address != null)
    defer
    {
        if request.address do
            allocator.free(&request)
    }

    let value = cast(*AllocatorBorrowValue, request.address)
    Swag.init(value)
    value.value = 143
    var observed: u64
    let caught = Swag.catchPanic(func|value, &request, &observed|() {
        observed = releaseBorrowedAllocation(value[], &request)
    })
    Swag.assert(caught.raised == #hastag("Swag.AllocatorSafety"))
    if not caught.raised do
        Swag.assert(observed == 143)
}
