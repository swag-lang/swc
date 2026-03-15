// swc-option suite-test

#global fileprivate

//#[Swag.PrintBc]
#test
{
    var a: s32 = undefined
    var b: *s32 = undefined
    @assert(#typeof(a) == s32)
    @assert(#typeof(b) == *s32)
}
