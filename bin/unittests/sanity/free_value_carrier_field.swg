#global private
using Swag

#[Swag.NoInline]
func allocate(size: u64)->*void
{
    var request: AllocatorRequest
    request.size = size
    Swag.getContext().allocator!.alloc(&request)
    return unwrap request.address
}
#[Swag.NoInline]
func release(pointer: *void, size: u64)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = size
    Swag.getContext().allocator!.free(&request)
}
struct Owner
{
    target:        const *void?
    spare:         const *void?
    width, height: s32
    owned:         bool
}
#[Swag.NoInline]
func target(value: Owner)->*void => cast #unconst (*void, unwrap value.target)
#[Swag.NoInline]
func dropValue(value: Owner)
{
    if value.owned do
        release(target(value), 8)
}
#test
{
    let owner = cast(*Owner, allocate(#sizeof(Owner)))
    Swag.init(owner, 1)
    owner.target = allocate(8)
    owner.owned  = true
    dropValue(owner[])
    owner.width = 17
    Swag.require(owner.width == 17)
    release(owner, #sizeof(Owner))
}

// Reading an ordinary pointer field retains its lifetime bound.
func rejectEscapingField()->*void
{
    var value: s32
    let owner = Owner{target: &value}
    return target(owner)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Exact field provenance still rejects releasing a caller's stack value.
func rejectReleaseKnownField()
{
    var value: s32
    let owner = Owner{target: &value}
    release(cast #unconst (*void, unwrap owner.target), #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}
