#global private
func runtimeSetupWorks()->bool
{
    let cxt = @getcontext()
    if !cxt.allocator or !cxt.tempAllocator.capacity or !cxt.errorAllocator.capacity do
        return false

    let ptr = cast([*] u8) cxt.tempAllocator.alloc(2)
    if !ptr do
        return false

    ptr[0] = 7
    ptr[1] = 9
    return ptr[0] == 7 and ptr[1] == 9
}

#test
{
    @assert(runtimeSetupWorks())

    const V = #run runtimeSetupWorks()
    #assert(V)
}

#test
{
    func writeContextValue()->bool
    {
        @getcontext().user0 = 0xC0FFEE
        return true
    }

    func contextStartsClean()->bool
    {
        return @getcontext().user0 == 0
    }

    const A = #run writeContextValue()
    const B = #run contextStartsClean()
    #assert(A and B)
}
