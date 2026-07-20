#global private
using Swag

#[Swag.Macro]
func pushAllocatorMacro(allocator: #null IAllocator, stmt: #code)
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = dref prev
    cxt.allocator = allocator
    @setcontext(cxt)

    #inject(stmt)
}

func allocatorObject(allocator: #null IAllocator)->#null *void
{
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return runtimeItf.obj
}

func allocatorITable(allocator: #null IAllocator)->#null const *void
{
    let runtimeItf = cast(const *Swag.Interface) &allocator
    return cast(#null const *void) runtimeItf.itable
}

func pushAllocatorWithNull()->bool
{
    pushAllocatorMacro(null)
    {
        return @getcontext().allocator == null
    }

    return false
}

func pushAllocatorWithLocalInterface()->bool
{
    let tempAllocator = @getcontext().tempAllocator

    pushAllocatorMacro(tempAllocator)
    {
        return allocatorObject(@getcontext().allocator) != null and allocatorITable(@getcontext().allocator) != null
    }

    return false
}

#test
{
    @assert(pushAllocatorWithNull())
    @assert(pushAllocatorWithLocalInterface())
}
