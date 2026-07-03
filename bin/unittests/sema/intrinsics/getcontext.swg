#global private

func semaTest001()
{
    var v = @getcontext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
}

func semaTest002()
{
    var v = @getcontext()
    #assert(#defined(v.panic))
}

/*#run
{
    @assert(@jit)
}
*/
