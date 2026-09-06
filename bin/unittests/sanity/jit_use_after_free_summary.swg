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
func allocateForJitSummary()->*void
{
    var request: AllocatorRequest
    request.size = 4
    let allocator = Swag.getContext().allocator!
    allocator.alloc(&request)
    return request.address!
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseForJitSummary(pointer: *void)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = 4
    let allocator = Swag.getContext().allocator!
    allocator.free(&request)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseWrapperForJitSummary(pointer: *void)
{
    releaseForJitSummary(pointer)
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
