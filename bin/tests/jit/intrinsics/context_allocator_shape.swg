#global fileprivate
using Swag

func contextPointerIsPresent()->bool
{
    return @getcontext() != null
}

func contextAllocatorFieldHasRuntimeShape()->bool
{
    let context = @getcontext()
    let runtimeItf = cast(const *Swag.Interface) &context.allocator
    return runtimeItf != null and runtimeItf.obj != null and runtimeItf.itable != null
}

func copiedContextAllocatorHasRuntimeShape()->bool
{
    let allocator = @getcontext().allocator
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return runtimeItf != null and runtimeItf.obj != null and runtimeItf.itable != null
}

func directContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 16

    @getcontext().allocator.req(&req)
    if !req.address do
        return false

    req.mode = .Free
    @getcontext().allocator.req(&req)
    return true
}

func copiedContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 16

    let allocator = @getcontext().allocator
    allocator.req(&req)
    if !req.address do
        return false

    req.mode = .Free
    allocator.req(&req)
    return true
}

func coalescedContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.mode = .Alloc
    req.size = 16

    let allocator = cast(IAllocator) null orelse @getcontext().allocator
    let runtimeItf = cast(const *Swag.Interface) &allocator
    if runtimeItf == null or runtimeItf.obj == null or runtimeItf.itable == null do
        return false

    allocator.req(&req)
    if !req.address do
        return false

    req.mode = .Free
    allocator.req(&req)
    return true
}

#test
{
    @assert(contextPointerIsPresent())
    @assert(contextAllocatorFieldHasRuntimeShape())
    @assert(copiedContextAllocatorHasRuntimeShape())
    @assert(directContextAllocatorRoundtrip())
    @assert(copiedContextAllocatorRoundtrip())
    @assert(coalescedContextAllocatorRoundtrip())
}
