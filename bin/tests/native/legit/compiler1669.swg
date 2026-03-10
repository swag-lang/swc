// swc-option suite-test

#global fileprivate
#global skip
func function(x: s32, y: ...)
{
    @assert(x == 50)
}

#test
{
    let ptr = &function
    ptr(50)
}
