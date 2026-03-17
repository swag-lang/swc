#global fileprivate // 

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

/*#run
{
    @assert(@jit)
}
*/
