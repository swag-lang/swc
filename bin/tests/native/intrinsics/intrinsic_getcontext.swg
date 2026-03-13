#global fileprivate // swc-option suite-test

#test
{
    var v = @getcontext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
}

#test
{
    var v = @getcontext()
    #assert(#defined(v.panic))
}

/*#run
{
    @assert(@jit)
}
*/