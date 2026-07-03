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
}
