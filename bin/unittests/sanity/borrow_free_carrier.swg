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

#[Swag.NoInline]
func identityComposed(target: *s32)->*s32 => identity(identityWrapped(target))

#[Swag.NoInline]
func identityBound(target: *s32)->*s32
{
    let borrowed = identityWrapped(target)
    return identity(borrowed)
}

#[Swag.NoInline]
func releaseComposed(target: *s32) { release(identity(target), #sizeof(s32)) }

#[Swag.NoInline]
func createComposed(target: *s32)->*Carrier => createWrapped(identity(target))

#[Swag.NoInline]
func carrierIdentity(carrier: *Carrier)->*Carrier => carrier

#[Swag.NoInline]
func createThroughIdentity(target: *s32)->*Carrier => carrierIdentity(createWrapped(target))

#[Swag.NoInline]
func independent(target: *s32)->*s32 => cast(*s32) allocate(#sizeof(s32))

#[Swag.NoInline]
func independentComposed(target: *s32)->*s32 => identity(independent(target))

var stash:       *s32?
var stableValue: s32

#[Swag.NoInline]
func storeInFreshCarrier(target: *s32, value: *s32)
{
    let carrier = carrierIdentity(create(target))
    carrier.target = value
    release(carrier, #sizeof(Carrier))
}

#[Swag.NoInline]
func storeComposed(target: *s32) { stash = identity(identity(target)) }

func rejectStoreComposedParameter()
{
    var value: s32
    storeComposed(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct Owner { data: *s32? }
impl Owner
{
    mtd opDrop()
    {
        if .data do
            release(.data, #sizeof(s32))
    }

    #[Swag.NoInline]
    mtd const view()->*s32 => .data!

    #[Swag.NoInline]
    mtd const forwardedView()->*s32 => identity(.view())

    #[Swag.NoInline]
    mtd clearThroughView()
    {
        release(identity(.view()), #sizeof(s32))
        .data = null
    }
}

func rejectReadAfterComposedPayloadRelease(owner: *Owner)->s32
{
    let view = owner.forwardedView()
    owner.clearThroughView()     // swc-expected-error {{sanity_err_borrow_invalidated}}
    return view[]
}

func rejectEscapeComposedParameter()->*s32
{
    var value: s32
    return identityComposed(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func rejectReleaseBoundParameter()
{
    var value: s32
    release(identityBound(&value), #sizeof(s32))     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectComposedRelease()
{
    var value: s32
    releaseComposed(&value)     // swc-expected-error {{sanity_err_free_borrowed}}
}

func rejectEscapeComposedCarrier()->*Carrier
{
    var value: s32
    return createComposed(&value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

#test
{
    var value: s32 = 31
    release(createComposed(&value), #sizeof(Carrier))
    release(createThroughIdentity(&value), #sizeof(Carrier))
    release(independentComposed(&value), #sizeof(s32))
    storeInFreshCarrier(&stableValue, &value)
    Swag.assert(value == 31)

    var owner = Owner{data: cast(*s32) allocate(#sizeof(s32))}
    owner.data![] = 17
    let before = owner.forwardedView()[]
    owner.clearThroughView()
    Swag.assert(before == 17 and not owner.data)
}

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
