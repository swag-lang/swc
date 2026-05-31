#global fileprivate

#test
{
    var v = @getcontext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
    @assert(#defined(v.allocator))
    @assert(#defined(v.tempAllocator))
    @assert(#defined(v.errorAllocator))
}

#test
{
    var v = @getcontext()
    #assert(#defined(v.panic))
    @assert(#defined(v.panic))
}

#test
{
    let prev = @getcontext()
    defer @setcontext(prev)

    var cxt = dref prev
    cxt.user0 = 0x5E7C0A7E

    @setcontext(cxt)
    @assert(@getcontext() == &cxt)
    @assert(@getcontext().user0 == 0x5E7C0A7E)
}

/*#run
{
    @assert(@jit)
}
*/
