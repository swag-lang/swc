#global private

func pushNullAllocatorContext()->bool
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.allocator = null
    Swag.setContext(cxt)

    return Swag.getContext().allocator == null
}

#[Swag.Macro]
func pushAllocatorLike(allocator: IAllocator?, stmt: #code)
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.allocator = allocator
    Swag.setContext(cxt)

    #inject(stmt)
}

func pushNullAllocatorMacroContext()->bool
{
    var result = false
    pushAllocatorLike(null)
    {
        result = Swag.getContext().allocator == null
    }

    return result
}

#test
{
    Swag.require(Swag.getContext().allocator != null)
    Swag.require(pushNullAllocatorContext())
    Swag.require(Swag.getContext().allocator != null)
}

#test
{
    Swag.require(Swag.getContext().allocator != null)
    Swag.require(pushNullAllocatorMacroContext())
    Swag.require(Swag.getContext().allocator != null)
}
