#global private

func pushNullAllocatorContext()->bool
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = dref prev
    cxt.allocator = null
    @setcontext(cxt)

    return @getcontext().allocator == null
}

#[Swag.Macro]
func pushAllocatorLike(allocator: IAllocator, stmt: #code void)
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = dref prev
    cxt.allocator = allocator
    @setcontext(cxt)

    #macro
    {
        #inject(#up stmt)
    }
}

func pushNullAllocatorMacroContext()->bool
{
    var result = false
    pushAllocatorLike(null)
    {
        result = @getcontext().allocator == null
    }

    return result
}

#test
{
    @assert(@getcontext().allocator != null)
    @assert(pushNullAllocatorContext())
    @assert(@getcontext().allocator != null)
}

#test
{
    @assert(@getcontext().allocator != null)
    @assert(pushNullAllocatorMacroContext())
    @assert(@getcontext().allocator != null)
}
