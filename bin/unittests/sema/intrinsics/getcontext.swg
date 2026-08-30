#global private

func semaTest001()
{
    var v = Swag.getContext()
    #assert(#defined(v.allocator))
    #assert(#defined(v.tempAllocator))
    #assert(#defined(v.errorAllocator))
}

func semaTest002()
{
    var v = Swag.getContext()
    #assert(#defined(v.panic))
}

/*#run
{
    Swag.assert(Swag.jit())
}
*/
