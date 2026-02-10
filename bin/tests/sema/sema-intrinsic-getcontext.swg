#global internal

#test
{
    var v = @getcontext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
    #assert(#defined(v.flags))
}

#test
{
    var v = @getcontext()
    #assert(#defined(v.panic))
}

#test
{
    var v = @getcontext()
    var f = v.flags
    var b = f & .ByteCode
}
