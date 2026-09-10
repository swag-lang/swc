#global private
func runtimeSetupWorks()->bool
{
    let cxt = Swag.getContext()
    if not cxt.allocator or not cxt.tempAllocator.capacity or not cxt.errorAllocator.capacity do
        return false

    let ptr = cast([*] u8?) cxt.tempAllocator.alloc(2)
    if not ptr do
        return false

    ptr[0] = 7
    ptr[1] = 9
    return ptr[0] == 7 and ptr[1] == 9
}

#test
{
    Swag.assert(runtimeSetupWorks())
}
