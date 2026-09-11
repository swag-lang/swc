#global private
using Swag

#[Swag.NoInline]
func allocate(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    Swag.getContext().allocator!.alloc(&req)
    return req.address!
}

#[Swag.NoInline]
func release(ptr: *void, size: u64)
{
    var req: AllocatorRequest
    req.address = ptr
    req.size    = size
    Swag.getContext().allocator!.free(&req)
}

struct Carrier { late target: *s32 }

#[Swag.NoInline]
func create(target: *s32)->*Carrier
{
    let carrier = cast(*Carrier) allocate(#sizeof(Carrier))
    carrier.target = target
    return carrier
}

#[Swag.NoInline]
func createWrapped(target: *s32)->*Carrier
{
    return create(target)
}

#[Swag.NoInline]
func identity(target: *s32)->*s32
{
    return target
}

#[Swag.NoInline]
func identityWrapped(target: *s32)->*s32
{
    return identity(target)
}

#[Swag.NoInline]
func nullableIdentity(target: *s32)->*s32? => target

// Releasing the allocation does not release the local its field references.
#test
{
    var value: s32 = 42
    let carrier    = create(&value)
    Swag.assert(carrier.target[] == 42)
    release(carrier, #sizeof(Carrier))
    Swag.assert(value == 42)
}

#test
{
    var value: s32 = 17
    let carrier    = createWrapped(&value)
    Swag.assert(carrier.target[] == 17)
    release(carrier, #sizeof(Carrier))
    Swag.assert(value == 17)
}

// The same distinction applies before any factory summary is involved.
#test
{
    var value: s32 = 9
    let carrier    = cast(*Carrier) allocate(#sizeof(Carrier))
    carrier.target = &value
    release(carrier, #sizeof(Carrier))
    Swag.assert(value == 9)
}

// A real alias still cannot be freed, including through a chain of wrappers.
func rejectReleaseAlias()
{
    var value: s32
    let borrowed = identityWrapped(&value)
    release(borrowed, #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectReleaseNestedAlias()
{
    var value: s32
    release(identity(&value), #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectReleaseDeepNestedAlias()
{
    var value: s32
    release(identity(identityWrapped(&value)), #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectReleaseAssertedNestedAlias()
{
    var value: s32
    release(nullableIdentity(&value)!, #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectEscapeNestedAlias()->*s32
{
    var value: s32
    return identity(identityWrapped(&value))     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A nested factory still returns a separate allocation, not the borrowed target.
#test
{
    var value: s32 = 23
    release(createWrapped(identity(&value)), #sizeof(Carrier))
    Swag.assert(value == 23)
}

func rejectReleaseCarrierTarget()
{
    var value: s32
    let carrier = cast(*Carrier) allocate(#sizeof(Carrier))
    carrier.target = &value
    release(carrier.target, #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}

// Separate allocation changes the release rule, but keeps the lifetime dependency.
func rejectEscapingCarrier()->*Carrier
{
    var value: s32
    return createWrapped(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}
