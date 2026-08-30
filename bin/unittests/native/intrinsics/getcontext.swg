#global private

#test
{
    var v = Swag.getContext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
    Swag.assert(#defined(v.allocator))
    Swag.assert(#defined(v.tempAllocator))
    Swag.assert(#defined(v.errorAllocator))
}

#test
{
    var v = Swag.getContext()
    #assert(#defined(v.panic))
    Swag.assert(#defined(v.panic))
}

#test
{
    let prev = Swag.getContext()
    defer Swag.setContext(prev)

    var cxt = prev[]
    cxt.user0 = 0x5E7C0A7E

    Swag.setContext(cxt)
    Swag.assert(Swag.getContext() == &cxt)
    Swag.assert(Swag.getContext().user0 == 0x5E7C0A7E)
}

/*#run
{
    Swag.assert(Swag.jit())
}
*/
