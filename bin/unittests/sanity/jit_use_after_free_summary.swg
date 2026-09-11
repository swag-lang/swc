#global private
using Swag

// Keep the allocation alive while #run executes. The compile-time diagnostic can then
// be tested without allowing a missing diagnostic to corrupt the compiler process.
struct RetainedAllocation
{
    late base: IAllocator
    request:   AllocatorRequest
}

impl IAllocator for RetainedAllocation
{
    mtd impl alloc(request: *AllocatorRequest) { .base.alloc(request) }
    mtd impl realloc(request: *AllocatorRequest) { .base.realloc(request) }
    mtd impl free(request: *AllocatorRequest) { .request = request[] }
    mtd impl freeAll(request: *AllocatorRequest) { discard request }
    mtd impl assertAllocated(request: *AllocatorRequest) { .base.assertAllocated(request) }
}

impl RetainedAllocation
{
    mtd opDrop() { if .request.address do .base.free(&.request) }
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func allocateForJitSummary(size: u64 = 4)->*void
{
    var request: AllocatorRequest
    request.size = size
    let allocator = Swag.getContext().allocator!
    allocator.alloc(&request)
    return request.address!
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseForJitSummary(pointer: *void, size: u64 = 4)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = size
    let allocator = Swag.getContext().allocator!
    allocator.free(&request)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func identityForJitSummary(pointer: *void)->*void => pointer

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func recursiveIdentityForJitSummary(pointer: *void, depth: u32)->*void
{
    if depth == 0 do return pointer
    return recursiveForwardForJitSummary(pointer, depth - 1)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func recursiveForwardForJitSummary(pointer: *void, depth: u32)->*void => recursiveIdentityForJitSummary(pointer, depth)

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func identityWrapperForJitSummary(pointer: *void)->*void => recursiveIdentityForJitSummary(identityForJitSummary(pointer), 2)

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseGuardedForJitSummary(pointer: *void)
{
    releaseForJitSummary(identityWrapperForJitSummary(pointer))
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseWrapperForJitSummary(pointer: *void)
{
    releaseGuardedForJitSummary(pointer)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func probeJitSummary()->s32
{
    let pointer = cast(*s32) allocateForJitSummary()
    pointer[] = 42
    releaseWrapperForJitSummary(pointer)     // swc-expected-note {{sanity_note_pointer_released_here}}
    return pointer[]                         // swc-expected-error {{sanity_err_use_after_free}}
}

#run
{
    let base = Swag.getContext().allocator!
    var retained: RetainedAllocation
    retained.base = base
    let context = Swag.getContext()
    context.allocator = &retained
    defer context.allocator = base
    Swag.assert(probeJitSummary() == 42)
}

struct JitCarrier { late target: *void }

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func createCarrierForJitSummary(pointer: *void)->*JitCarrier
{
    let carrier = cast(*JitCarrier) allocateForJitSummary(#sizeof(JitCarrier))
    carrier.target = pointer
    return carrier
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseCarrierForJitSummary(pointer: *void)
{
    releaseForJitSummary(identityForJitSummary(createCarrierForJitSummary(pointer)), #sizeof(JitCarrier))
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func allocateIndependentForJitSummary(pointer: *void)->*void => allocateForJitSummary()

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseIndependentForJitSummary(pointer: *void)
{
    releaseForJitSummary(identityForJitSummary(allocateIndependentForJitSummary(pointer)))
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func probeIndependentJitSummary()->s32
{
    let pointer = cast(*s32) allocateForJitSummary()
    defer releaseForJitSummary(pointer)
    pointer[] = 42
    releaseCarrierForJitSummary(pointer)
    releaseIndependentForJitSummary(pointer)
    return pointer[]
}

struct JitOwner
{
    data:   [*] s32?
    marker: s32 = 42
}

impl JitOwner
{
    mtd opDrop() { if .data do releaseForJitSummary(.data) }

    #[Swag.NoInline]
    mtd const view()->*void => .data!

    #[Swag.NoInline]
    mtd const forwardedView()->*void => identityWrapperForJitSummary(.view())
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseOwnedForJitSummary(owner: *JitOwner)
{
    releaseForJitSummary(identityWrapperForJitSummary(owner.forwardedView()))
    owner.data = null
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func probeOwnedJitSummary()->s32
{
    var owner = JitOwner{data: cast([*] s32) allocateForJitSummary()}
    releaseOwnedForJitSummary(&owner)
    return owner.marker
}

#run
{
    Swag.assert(probeIndependentJitSummary() == 42)
    Swag.assert(probeOwnedJitSummary() == 42)
}
