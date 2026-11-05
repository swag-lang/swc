#global private
#global #[Swag.Sanity(.Lifecycle, true)]
using Swag

#[Swag.NoInline]
func allocateByte()->*u8
{
    var request: AllocatorRequest
    request.size = 1
    Swag.getContext().allocator!.alloc(&request)
    return cast(*u8, unwrap request.address)
}

#[Swag.NoInline]
func releaseByte(pointer: *void)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = 1
    Swag.getContext().allocator!.free(&request)
}

// Loading a pointer by value does not borrow the array's slot.
#test
{
    var slots: [2] (*u8?)
    slots[0] = allocateByte()
    releaseByte(unwrap slots[0])
}

// The same rule holds through a slice and a contextual pointer conversion.
#test
{
    var slots: [2] (*u8?)
    slots[0] = allocateByte()
    let view = cast([..] (*u8?), slots)
    releaseByte(unwrap view[0])
}

// An unrelated borrowed element does not taint the allocated sibling.
#test
{
    var value: u8
    var slots: [2] (*u8?)
    slots[0] = &value
    slots[1] = allocateByte()
    let view = cast([..] (*u8?), slots)
    releaseByte(unwrap view[1])
}

// The pointer stored in the element can still borrow stack storage.
func rejectBorrowedElement()
{
    var value: u8
    var slots: [2] (*u8?)
    slots[0] = &value
    releaseByte(unwrap slots[0])     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectBorrowedSliceElement()
{
    var value: u8
    var slots: [2] (*u8?)
    slots[0] = &value
    let view = cast([..] (*u8?), slots)
    releaseByte(unwrap view[0])     // swc-expected-error {{sanity_err_free_borrowed}}
}
