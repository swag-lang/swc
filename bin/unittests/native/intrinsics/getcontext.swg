#global private

#test
{
    var v = Swag.getContext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
    Swag.require(#defined(v.allocator))
    Swag.require(#defined(v.tempAllocator))
    Swag.require(#defined(v.errorAllocator))
}

#test
{
    var v = Swag.getContext()
    #assert(#defined(v.panic))
    Swag.require(#defined(v.panic))
}

#test
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.user0 = 0x5E7C0A7E

    Swag.setContext(cxt)
    Swag.require(Swag.getContext() == &cxt)
    Swag.require(Swag.getContext().user0 == 0x5E7C0A7E)
}

/*#run
{
    Swag.assert(Swag.jit())
}
*/
