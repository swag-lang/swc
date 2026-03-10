// swc-option suite-test

#global fileprivate

//#[Swag.PrintBc]
#test
{
    let a: *s32 = null
    @assert(a == null)
}
