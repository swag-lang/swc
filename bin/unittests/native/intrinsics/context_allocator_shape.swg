#global private
using Swag

func contextPointerIsPresent()->bool
{
    return Swag.getContext() != null
}

func contextAllocatorFieldHasRuntimeShape()->bool
{
    let context    = Swag.getContext()
    let runtimeItf = cast(const *Swag.Interface) &context.allocator
    return runtimeItf != null and runtimeItf.obj != null and runtimeItf.itable != null
}

func copiedContextAllocatorHasRuntimeShape()->bool
{
    let allocator  = Swag.getContext().allocator
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return runtimeItf != null and runtimeItf.obj != null and runtimeItf.itable != null
}

func allocatorObject(allocator: IAllocator?)->*void?
{
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return runtimeItf.obj
}

func allocatorITable(allocator: IAllocator?)->const *void?
{
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return cast(const *void?) runtimeItf.itable
}

struct ContextTempAllocatorHolder
{
    allocator: IAllocator?
}

func contextTempAllocatorObject()->*void
{
    return cast(*void) &Swag.getContext().tempAllocator
}

func makeContextTempAllocatorHolder()->ContextTempAllocatorHolder
{
    var result: ContextTempAllocatorHolder
    result.allocator = Swag.getContext().tempAllocator
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

    let directItf = Swag.getContext().allocator!
    directItf.alloc(&req)
    if !req.address do
        return false

    directItf.free(&req)
    return true
}

func copiedContextAllocatorRoundtrip()->bool
{
    var req: AllocatorRequest
    req.size = 16

    let allocator = Swag.getContext().allocator!
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

    let allocator  = (cast(IAllocator?) null orelse Swag.getContext().allocator)!
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
    Swag.assert(contextPointerIsPresent())
    Swag.assert(contextAllocatorFieldHasRuntimeShape())
    Swag.assert(copiedContextAllocatorHasRuntimeShape())
    Swag.assert(returnedContextTempAllocatorPreservesObject())
    Swag.assert(directContextAllocatorRoundtrip())
    Swag.assert(copiedContextAllocatorRoundtrip())
    Swag.assert(coalescedContextAllocatorRoundtrip())
}
