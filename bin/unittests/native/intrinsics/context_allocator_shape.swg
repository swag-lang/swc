#global private
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

func allocatorObject(allocator: IAllocator)->*void
{
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return runtimeItf.obj
}

func allocatorITable(allocator: IAllocator)->const *void
{
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return runtimeItf.itable
}

struct ContextTempAllocatorHolder
{
    allocator: IAllocator
}

func contextTempAllocatorObject()->*void
{
    return cast(*void) &@getcontext().tempAllocator
}

func makeContextTempAllocatorHolder()->ContextTempAllocatorHolder
{
    var result: ContextTempAllocatorHolder
    result.allocator = @getcontext().tempAllocator
    return result
}

func returnedContextTempAllocatorPreservesObject()->bool
{
    let holder = makeContextTempAllocatorHolder()
    return allocatorObject(holder.allocator) == contextTempAllocatorObject() and allocatorITable(holder.allocator) != null
}

func directContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.size = 16

    @getcontext().allocator.alloc(&req)
    if !req.address do
        return false

    @getcontext().allocator.free(&req)
    return true
}

func copiedContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.size = 16

    let allocator = @getcontext().allocator
    allocator.alloc(&req)
    if !req.address do
        return false

    allocator.free(&req)
    return true
}

func coalescedContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.size = 16

    let allocator = cast(IAllocator) null orelse @getcontext().allocator
    let runtimeItf = cast(const *Swag.Interface) &allocator
    if runtimeItf == null or runtimeItf.obj == null or runtimeItf.itable == null do
        return false

    allocator.alloc(&req)
    if !req.address do
        return false

    allocator.free(&req)
    return true
}

#test
{
    @assert(contextPointerIsPresent())
    @assert(contextAllocatorFieldHasRuntimeShape())
    @assert(copiedContextAllocatorHasRuntimeShape())
    @assert(returnedContextTempAllocatorPreservesObject())
    @assert(directContextAllocatorRoundtrip())
    @assert(copiedContextAllocatorRoundtrip())
    @assert(coalescedContextAllocatorRoundtrip())
}