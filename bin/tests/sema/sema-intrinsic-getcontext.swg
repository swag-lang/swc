#global internal

#test
{
    var v = @getcontext()
    #assert(#defined(v.allocator))
}
