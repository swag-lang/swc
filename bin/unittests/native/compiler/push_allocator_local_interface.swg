#global private
using Swag

#[Swag.Macro]
func pushAllocatorMacro(allocator: #null IAllocator, stmt: #code)
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.allocator = allocator
    Swag.setContext(cxt)

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
        return Swag.getContext().allocator == null
    }

    return false
}

func pushAllocatorWithLocalInterface()->bool
{
    let tempAllocator = Swag.getContext().tempAllocator

    pushAllocatorMacro(tempAllocator)
    {
        return allocatorObject(Swag.getContext().allocator) != null and allocatorITable(Swag.getContext().allocator) != null
    }

    return false
}

#test
{
    Swag.assert(pushAllocatorWithNull())
    Swag.assert(pushAllocatorWithLocalInterface())
}
